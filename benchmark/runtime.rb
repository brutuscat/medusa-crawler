# frozen_string_literal: true

# Run with bundle exec; MEDUSA_BENCH_SOURCE selects another checkout while
# retaining the current checkout's exact Ruby/dependency resolution.
require 'optparse'
require 'json'
require 'digest'
require 'async'

options = { workers: 4, pages: 240, workload: 'public', context: 'plain' }
OptionParser.new do |parser|
  parser.on('--base-url URL') { |value| options[:base_url] = value }
  parser.on('--workers N', Integer) { |value| options[:workers] = value }
  parser.on('--pages N', Integer) { |value| options[:pages] = value }
  parser.on('--workload NAME', %w[public private graph redirects]) { |value| options[:workload] = value }
  parser.on('--context NAME', %w[plain async]) { |value| options[:context] = value }
end.parse!
raise ArgumentError, '--base-url is required' unless options[:base_url]
raise ArgumentError, 'workers and pages must be positive' unless options.values_at(:workers, :pages).all?(&:positive?)

source = File.realpath(ENV.fetch('MEDUSA_BENCH_SOURCE', File.expand_path('..', __dir__)))
$LOAD_PATH.unshift(File.join(source, 'lib'))
require 'medusa'
require File.join(source, 'examples/private_site_with_login')
raise 'Wrong source loaded' unless $LOADED_FEATURES.include?(File.join(source, 'lib/medusa/core.rb'))

# Measure each URI.open invocation, including redirects and Medusa retries.
# Net::HTTP may retry internally within one invocation. Medusa retry backoff
# is outside the active interval. The mutex covers only counters,
# never network I/O, so it works for both thread and fiber workers.
module RuntimeFetchMetrics
  @mutex = Mutex.new
  @active = @peak = @requests = 0
  @peak_threads = Thread.list.size

  class << self
    attr_reader :active, :peak, :requests, :peak_threads

    def enter
      @mutex.synchronize do
        @active += 1
        @requests += 1
        @peak = [@peak, @active].max
        @peak_threads = [@peak_threads, Thread.list.size].max
      end
    end

    def leave
      @mutex.synchronize { @active -= 1 }
    end
  end

  def open(...)
    RuntimeFetchMetrics.enter
    begin
      super
    ensure
      RuntimeFetchMetrics.leave
    end
  end
end
URI.singleton_class.prepend(RuntimeFetchMetrics)

base = URI(options.fetch(:base_url))
raise ArgumentError, 'Use the local smoke container' unless %w[localhost 127.0.0.1 ::1].include?(base.hostname)
public_paths = %w[/login /checkboxes /tables /large]
url_for = ->(path) { base.merge(path).to_s }
cookies = if options[:workload] == 'private'
  PrivateSiteWithLogin.login_cookies(
    login_url: url_for.call('/authenticate'), username: 'tomsmith', password: 'SuperSecretPassword!'
  )
end

expected = case options[:workload]
when 'graph'
  (['/'] + public_paths).to_h { |path| [url_for.call(path), 200] }
when 'redirects'
  { '/redirect' => 302, '/status_codes' => 200, '/status_codes/404' => 404, '/status_codes/500' => 500 }
    .to_h { |path, code| [url_for.call(path), code] }
else
  options[:pages].times.to_h do |index|
    path = options[:workload] == 'private' ? '/secure' : public_paths[index % public_paths.size]
    [url_for.call("#{path}?medusa_bench=#{index}"), 200]
  end
end
seeds = case options[:workload]
when 'graph' then [url_for.call('/')]
when 'redirects' then expected.keys.reject { |url| URI(url).path == '/status_codes' }
else expected.keys
end
# Duplicate seeds exercise admission/deduplication without adding HTTP work.
seeds += seeds.first(5)
seen = {}
after_calls = 0
thread_count_before = Thread.list.size
callback_threads = []

fingerprint = lambda do |page|
  if options[:workload] == 'private'
    message = page.doc.at_css('h4.subheader')&.text&.strip
    raise "Unauthenticated page: #{page.url}" unless message&.start_with?('Welcome to the Secure Area')
    # Session flash messages may be consumed concurrently; compare the stable
    # authenticated content rather than the server's session-dependent banner.
    Digest::SHA256.hexdigest(message)
  else
    Digest::SHA256.hexdigest(page.body)
  end
end

run_crawl = lambda do
  Medusa.crawl(seeds, threads: options[:workers], read_timeout: 15, http_cache: false,
    cookies: cookies, accept_cookies: !cookies.nil?) do |crawl|
    crawl.focus_crawl do |page|
      options[:workload] == 'graph' ? page.links.select { |link| expected.key?(link.to_s) } : []
    end
    crawl.on_every_page do |page|
      key = page.url.to_s
      raise "Duplicate callback: #{key}" if seen.key?(key)
      raise "Fetch failed: #{key}: #{page.error}" if page.error
      raise "Unexpected status: #{key}: #{page.code}" unless expected[key] == page.code
      callback_threads << Thread.current.object_id
      seen[key] = [page.code, fingerprint.call(page), page.depth]
    end
    crawl.after_crawl { after_calls += 1 }
  end
end

cpu_before = Process.times
wall_before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
async_ticks = 0
crawl = if options[:context] == 'async'
  Async do |parent|
    ticker = parent.async do |task|
      loop do
        task.sleep(0.001)
        async_ticks += 1
      end
    end
    begin
      run_crawl.call
    ensure
      ticker.stop
    end
  end.wait
else
  run_crawl.call
end
seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall_before
cpu_after = Process.times

raise 'Missing or unexpected callbacks' unless seen.keys.sort == expected.keys.sort
raise 'Missing or unexpected stored pages' unless crawl.pages.keys.sort == expected.keys.sort
crawl.pages.each do |url, page|
  raise "Incorrect stored page: #{url}" unless page.fetched? &&
    seen.fetch(url) == [page.code, fingerprint.call(page), page.depth]
end
raise 'after_crawl must run once' unless after_calls == 1
raise 'Callbacks left the caller thread' unless callback_threads.uniq == [Thread.current.object_id]
raise 'Active requests exceeded limit' unless RuntimeFetchMetrics.peak <= options[:workers]
raise 'Requests remain active' unless RuntimeFetchMetrics.active.zero?
raise 'Unexpected OpenURI call count' unless RuntimeFetchMetrics.requests == expected.size
workers = crawl.instance_variable_get(:@tentacles)
raise 'Incorrect worker pool size' unless workers.size == options[:workers]
raise 'Workers remain alive' unless workers.all? do |worker|
  worker.is_a?(Thread) ? !worker.alive? : worker.finished?
end
if options[:workload] == 'graph'
  raise 'Incorrect traversal depths' unless seen.all? { |url, (_, _, depth)| depth == (URI(url).path == '/' ? 0 : 1) }
end
if Medusa::Core.const_defined?(:SchedulerQueue, false)
  raise 'Fiber requests did not overlap' if options[:workers] > 1 && expected.size > 1 && RuntimeFetchMetrics.peak < 2
  raise 'Async caller did not progress' if options[:context] == 'async' && async_ticks.zero?
end

puts JSON.generate(
  source: source, ruby: RUBY_DESCRIPTION, async: Async::VERSION, workload: options[:workload],
  context: options[:context], workers: options[:workers], pages: seen.size,
  seconds: seconds, pages_per_second: seen.size / seconds,
  cpu_seconds: cpu_after.utime + cpu_after.stime - cpu_before.utime - cpu_before.stime,
  peak_active_requests: RuntimeFetchMetrics.peak, requests: RuntimeFetchMetrics.requests,
  owned_workers: workers.size,
  peak_ruby_threads: RuntimeFetchMetrics.peak_threads, async_ticks: async_ticks,
  ruby_threads_before: thread_count_before, ruby_threads_after: Thread.list.size,
  result_digest: Digest::SHA256.hexdigest(JSON.generate(seen.sort)), correctness: 'PASS'
)
