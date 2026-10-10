require 'medusa/core'
require 'fakeweb_helper'
require_relative '../support/local_http_server'
require 'async'
require 'timeout'

module Medusa
  RSpec.describe Core do

    before(:each) do
      WebMock.reset!
    end

    def expect_worker_tasks_finished(core)
      tasks = core.instance_variable_get(:@tentacles)
      expect(tasks).not_to be_empty
      expect(tasks).to all(satisfy(&:finished?))
    end

    def expect_worker_tasks_running(core)
      tasks = core.instance_variable_get(:@tentacles)
      expect(tasks).not_to be_empty
      expect(tasks).to all(satisfy(&:alive?))
    end

    def allow_local_http
      WebMock.disable_net_connect!(allow_localhost: true)
    end

    def close_local_http(server, *gates)
      gates.compact.each(&:close)
      server&.close
    ensure
      WebMock.disable_net_connect!
    end

    def finish_crawl_thread(thread)
      thread.join(5)
      thread.kill.join if thread.alive?
    end

    def wait_for_async(task, timeout: 5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      until yield
        raise Timeout::Error, 'timed out waiting for an async spec condition' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        task.sleep(0.001)
      end
    end

    def blocked_pair
      gate = LocalHTTPServer::Gate.new
      slow_started = Queue.new
      server = nil
      server = LocalHTTPServer.new do |request|
        case request.path
        when '/blocked-root'
          %(<a href="#{server.url('/blocked-slow')}">slow</a><a href="#{server.url('/blocked-fast')}">fast</a>)
        when '/blocked-slow'
          slow_started << true
          gate.wait(request.path)
          'slow page'
        when '/blocked-fast'
          slow_started.pop
          'fast page'
        else
          'fast page'
        end
      end

      [server, gate, slow_started, server.url('/blocked-root'), server.url('/blocked-slow'), server.url('/blocked-fast')]
    end

    it 'constructs the default HTTP cache when enabled' do
      page = FakePage.new('cached')

      crawl = Medusa.crawl(page.url, http_cache: true)

      expect(crawl.pages[page.url].from_cache?).to be(false)
    end

    it 'keeps the pre-2.0 Tentacle constructor and shares one cache across workers' do
      page = FakePage.new('shared-cache')
      worker_caches = Queue.new

      expect(Tentacle.instance_method(:initialize).parameters).to eq(
        [[:req, :link_queue], [:req, :page_queue], [:opt, :opts]]
      )
      allow(Tentacle).to receive(:new).and_wrap_original do |constructor, *arguments|
        worker_caches << arguments.fetch(2).fetch(:http_cache)
        constructor.call(*arguments)
      end

      Medusa.crawl(page.url, http_cache: true, threads: 2)

      caches = 2.times.map { worker_caches.pop }
      expect(caches).to all(be_a(HTTP::Cache))
      expect(caches.uniq.size).to eq(1)
    end

    it 'does not reuse a response that establishes a cookie across crawls' do
      storage = {}
      login_url = URI(SPEC_DOMAIN).merge('/cached-login').to_s
      private_url = URI(SPEC_DOMAIN).merge('/private').to_s
      login = stub_request(:get, login_url)
        .to_return(
          body: '<a href="/private">Private</a>',
          headers: {
            'Content-Type' => 'text/html',
            'Cache-Control' => 'max-age=60',
            'Set-Cookie' => 'session=first; Path=/'
          }
        )
        .then
        .to_return(
          body: '<a href="/private">Private</a>',
          headers: {
            'Content-Type' => 'text/html',
            'Cache-Control' => 'max-age=60',
            'Set-Cookie' => 'session=second; Path=/'
          }
        )
      first_private = stub_request(:get, private_url)
        .with(headers: {'Cookie' => 'session=first'})
        .to_return(body: 'first session', headers: {'Cache-Control' => 'no-store'})
      second_private = stub_request(:get, private_url)
        .with(headers: {'Cookie' => 'session=second'})
        .to_return(body: 'second session', headers: {'Cache-Control' => 'no-store'})
      options = {
        accept_cookies: true,
        threads: 1,
        http_cache: {storage:, strategy: :freshness}
      }

      Medusa.crawl(login_url, options)
      Medusa.crawl(login_url, options)

      expect(login).to have_been_requested.twice
      expect(first_private).to have_been_requested.once
      expect(second_private).to have_been_requested.once
    end

    it 'rejects the same unsupported cache configuration as HTTP' do
      page = FakePage.new('invalid-cache')

      expect { Medusa.crawl(page.url, http_cache: Object.new) }.to raise_error(ArgumentError, /http_cache/)
    end

    it 'uses the configured fiber worker limit with real HTTP and a backlog' do
      [1, 2, 4].each do |workers|
        gate = LocalHTTPServer::Gate.new
        server = LocalHTTPServer.new do |_request|
          gate.wait
          '<html></html>'
        end
        urls = (0...(workers + 5)).map { server.url("/limit-#{workers}-#{_1}") }
        allow_local_http
        crawl_thread = Thread.new { Medusa.crawl(urls, threads: workers) }

        begin
          Timeout.timeout(5) { workers.times { gate.arrivals.pop } }
          expect(server.active_requests).to eq(workers)

          gate.release(urls.size)
          crawl = Timeout.timeout(5) { crawl_thread.value }

          expect(crawl.pages.size).to eq(urls.size)
          expect(crawl.instance_variable_get(:@tentacles).size).to eq(workers)
          expect(server.request_count).to eq(urls.size)
          expect(server.peak_active_requests).to eq(workers)
          expect_worker_tasks_finished(crawl)
        ensure
          close_local_http(server, gate)
          crawl_thread.join
        end
      end
    end

    it 'restores the caller scheduler and finishes its worker tasks after a synchronous crawl' do
      server = LocalHTTPServer.new { |_request| '<html>done</html>' }
      allow_local_http
      caller_scheduler = Fiber.scheduler

      begin
        crawl = Medusa.crawl(server.url('/sync'), threads: 2)

        expect(crawl.pages.size).to eq(1)
        expect(Fiber.scheduler).to equal(caller_scheduler)
        expect_worker_tasks_finished(crawl)
      ensure
        close_local_http(server)
      end
    end

    it 'rejects an unsupported active scheduler before clearing configured storage' do
      storage = Storage.Moneta(:Memory)
      expect(storage).not_to receive(:clear)
      allow(Fiber).to receive(:scheduler).and_return(Object.new)

      expect { Medusa.crawl(SPEC_DOMAIN, storage: storage) }
        .to raise_error(ArgumentError, /Async/)
    end

    it 'reuses an Async caller reactor while another task makes progress during a fetch' do
      gate = LocalHTTPServer::Gate.new
      server = LocalHTTPServer.new do |_request|
        gate.wait
        '<html>heartbeat</html>'
      end
      allow_local_http
      async_thread = Thread.new do
        Async do |parent|
          caller_scheduler = Fiber.scheduler
          heartbeat = 0
          crawl_task = parent.async { Medusa.crawl(server.url('/heartbeat'), threads: 1) }
          heartbeat_task = parent.async do |task|
            wait_for_async(task) { gate.arrivals.size == 1 }
            10.times do
              heartbeat += 1
              task.sleep(0)
            end
            gate.release
          end

          crawl = crawl_task.wait
          heartbeat_task.wait
          [crawl, heartbeat, caller_scheduler, Fiber.scheduler]
        end.wait
      end

      begin
        crawl, heartbeat, scheduler_before, scheduler_after = Timeout.timeout(5) { async_thread.value }
        expect(crawl.pages.size).to eq(1)
        expect(heartbeat).to eq(10)
        expect(scheduler_after).to equal(scheduler_before)
        expect_worker_tasks_finished(crawl)
      ensure
        close_local_http(server, gate)
        finish_crawl_thread(async_thread)
      end
    end

    it 'yields to other fibers during an HTTP timeout retry delay' do
      gate = LocalHTTPServer::Gate.new
      server = LocalHTTPServer.new do |_request|
        gate.wait
        '<html>retried</html>'
      end
      allow_local_http
      stub_const('Medusa::HTTP::RETRY_LIMIT', 1)
      url = server.url('/read-timeout-retry')
      open_calls = 0
      received_read_timeouts = []
      allow(URI).to receive(:open).and_wrap_original do |open, requested_url, *arguments|
        open_calls += 1 if requested_url.to_s == url
        received_read_timeouts << arguments.last[:read_timeout]
        open.call(requested_url, *arguments)
      end
      retry_delays = Queue.new
      allow_any_instance_of(HTTP).to receive(:sleep).and_wrap_original do |sleep_method, duration|
        retry_delays << duration
        sleep_method.call(duration)
      end

      async_thread = Thread.new do
        Async do |parent|
          heartbeat = 0
          crawl_task = parent.async do
            Medusa.crawl(url, threads: 1, read_timeout: 0.05)
          end
          heartbeat_task = parent.async do |task|
            wait_for_async(task) { !retry_delays.empty? }
            10.times do
              heartbeat += 1
              task.sleep(0)
            end
            gate.close
          end

          crawl = crawl_task.wait
          heartbeat_task.wait
          [crawl, heartbeat, retry_delays.size.times.map { retry_delays.pop }]
        end.wait
      end

      begin
        crawl, heartbeat, delays = Timeout.timeout(5) { async_thread.value }
        expect(crawl.pages.size).to eq(1)
        expect(crawl.pages.values).to all(be_fetched)
        expect(crawl.pages.values.map(&:code)).to eq([200])
        expect(heartbeat).to eq(10)
        expect(delays).to eq([2])
        expect(open_calls).to eq(2)
        expect(received_read_timeouts).to eq([0.05, 0.05])
        expect(server.request_count).to be >= 2
        expect_worker_tasks_finished(crawl)
      ensure
        close_local_http(server, gate)
        finish_crawl_thread(async_thread)
      end
    end

    it 'keeps two concurrent crawls isolated when one callback fails' do
      bad_gate = LocalHTTPServer::Gate.new
      good_gate = LocalHTTPServer::Gate.new
      server = LocalHTTPServer.new do |request|
        (request.path == '/isolated-bad' ? bad_gate : good_gate).wait(request.path)
        "#{request.path} response"
      end
      allow_local_http
      bad_url = server.url('/isolated-bad')
      good_url = server.url('/isolated-good')
      failure = RuntimeError.new('one crawl failed')
      async_thread = Thread.new do
        Async do |parent|
          bad_core = nil
          good_core = nil
          bad_task = parent.async do
            begin
              Medusa.crawl(bad_url, threads: 1) do |crawler|
                bad_core = crawler
                crawler.on_every_page { raise failure }
              end
            rescue StandardError => error
              error
            end
          end
          good_task = parent.async do
            Medusa.crawl(good_url, threads: 1) { |crawler| good_core = crawler }
          end

          wait_for_async(parent) { bad_gate.arrivals.size == 1 && good_gate.arrivals.size == 1 }
          bad_gate.release
          bad_result = bad_task.wait
          good_running_after_failure = good_task.alive?
          good_workers_running_after_failure = good_core.instance_variable_get(:@tentacles).map(&:alive?)
          good_gate.release
          [bad_result, good_task.wait, bad_core, good_core,
           good_running_after_failure, good_workers_running_after_failure]
        end.wait
      end

      begin
        bad_result, good_result, bad_core, good_core, good_running, good_workers_running = Timeout.timeout(5) { async_thread.value }
        expect(bad_result).to equal(failure)
        expect(good_result.pages.size).to eq(1)
        expect(bad_core).not_to equal(good_core)
        expect(good_running).to be(true)
        expect(good_workers_running).to eq([true])
        expect_worker_tasks_finished(bad_core)
        expect_worker_tasks_finished(good_core)
      ensure
        close_local_http(server, bad_gate, good_gate)
        finish_crawl_thread(async_thread)
      end
    end

    it 'cleans up blocked workers when the caller cancels a crawl task' do
      gate = LocalHTTPServer::Gate.new
      server = LocalHTTPServer.new do |request|
        gate.wait(request.path)
        'blocked response'
      end
      allow_local_http
      urls = [server.url('/cancel-one'), server.url('/cancel-two')]
      async_thread = Thread.new do
        Async do |parent|
          core = nil
          after_crawl_called = false
          sibling_ready = Queue.new
          sibling_release = Queue.new
          sibling_task = parent.async do |task|
            sibling_ready << true
            wait_for_async(task) { !sibling_release.empty? }
            sibling_release.pop
            :sibling_survived
          end
          crawl_task = parent.async do
            Medusa.crawl(urls, threads: 2) do |crawler|
              core = crawler
              crawler.after_crawl { after_crawl_called = true }
            end
          end
          wait_for_async(parent) { !sibling_ready.empty? }
          wait_for_async(parent) { gate.arrivals.size == 2 }
          crawl_task.cancel
          wait_for_async(parent) { crawl_task.finished? }
          crawl_task.wait
          sibling_was_running = sibling_task.alive?
          sibling_release << true
          [crawl_task.finished?, crawl_task.cancelled?, core, after_crawl_called,
           sibling_was_running, sibling_task.wait]
        end.wait
      end

      begin
        finished, cancelled, core, after_crawl_called, sibling_was_running, sibling_result = Timeout.timeout(5) { async_thread.value }
        expect(finished).to be(true)
        expect(cancelled).to be(true)
        expect(after_crawl_called).to be(false)
        expect(sibling_was_running).to be(true)
        expect(sibling_result).to eq(:sibling_survived)
        expect_worker_tasks_finished(core)
      ensure
        close_local_http(server, gate)
        finish_crawl_thread(async_thread)
      end
    end

    it 'shares a session across overlapping tentacle requests' do
      root_url = URI(SPEC_DOMAIN).merge('/session').to_s
      child_urls = %w[one two].map { URI(SPEC_DOMAIN).merge("/session/#{_1}").to_s }
      root_body = child_urls.map { |url| %(<a href="#{url}">#{url}</a>) }.join
      stub_request(:get, root_url).to_return(
        body: root_body,
        headers: {'Content-Type' => 'text/html', 'Set-Cookie' => 'session=shared; Path=/'}
      )

      arrivals = Queue.new
      releases = Queue.new
      received_cookies = Queue.new
      child_urls.each do |url|
        stub_request(:get, url).to_return do |request|
          received_cookies << request.headers['Cookie']
          arrivals << true
          releases.pop
          {body: 'Private page', headers: {'Content-Type' => 'text/html'}}
        end
      end

      visited = []
      crawl_thread = Thread.new do
        Medusa.crawl(root_url, threads: 2, accept_cookies: true) do |crawler|
          crawler.on_every_page { visited << _1.url.to_s }
        end
      end
      overlap_error = begin
        Timeout.timeout(5) { child_urls.size.times { arrivals.pop } }
        nil
      rescue Timeout::Error => error
        error
      ensure
        child_urls.size.times { releases << true }
      end
      crawl = crawl_thread.value

      expect(overlap_error).to be_nil
      expect(child_urls.size.times.map { received_cookies.pop }).to contain_exactly('session=shared', 'session=shared')
      expect(visited).to contain_exactly(root_url, *child_urls)
      expect(crawl.pages.values).to all(be_fetched)
    end

    it 'waits for in-flight fetches and follows links discovered by a late page' do
      root_url = URI(SPEC_DOMAIN).merge('/completion-root').to_s
      slow_url = URI(SPEC_DOMAIN).merge('/completion-slow').to_s
      branch_url = URI(SPEC_DOMAIN).merge('/completion-branch').to_s
      late_url = URI(SPEC_DOMAIN).merge('/completion-late').to_s
      stub_request(:get, root_url).to_return(
        body: %(<a href="#{slow_url}">slow</a><a href="#{branch_url}">branch</a>),
        headers: {'Content-Type' => 'text/html'}
      )
      slow_started = Queue.new
      release_slow = Queue.new
      late_started = Queue.new
      stub_request(:get, slow_url).to_return do
        slow_started << true
        release_slow.pop
        {body: 'slow page', headers: {'Content-Type' => 'text/html'}}
      end
      stub_request(:get, branch_url).to_return(
        body: %(<a href="#{late_url}">late</a>),
        headers: {'Content-Type' => 'text/html'}
      )
      stub_request(:get, late_url).to_return do
        late_started << true
        {body: 'late page', headers: {'Content-Type' => 'text/html'}}
      end

      visited = Queue.new
      after_crawl = Queue.new
      crawl_thread = Thread.new do
        Medusa.crawl(root_url, threads: 2) do |crawler|
          crawler.on_every_page { visited << _1.url.to_s }
          crawler.after_crawl { after_crawl << true }
        end
      end

      begin
        Timeout.timeout(5) do
          slow_started.pop
          late_started.pop
        end
        expect(crawl_thread).to be_alive
        expect(after_crawl).to be_empty
      ensure
        release_slow << true
        crawl_thread.join
      end

      crawl = crawl_thread.value
      expect(crawl.pages.size).to eq(4)
      expect(4.times.map { visited.pop }).to contain_exactly(root_url, slow_url, branch_url, late_url)
      expect(after_crawl.pop).to be(true)
    end

    it 'reserves seed and discovered URLs using PageStore URL identity' do
      seed_url = URI(SPEC_DOMAIN).merge('/duplicate-seed').to_s
      child_url = URI(SPEC_DOMAIN).merge('/duplicate-child').to_s
      seed_request = stub_request(:get, seed_url).to_return(body: '<html></html>')
      child_request = stub_request(:get, child_url).to_return(body: '<html></html>')
      https_seed = URI(seed_url).tap { _1.scheme = 'https' }.to_s
      https_request = stub_request(:get, https_seed).to_return(body: '<html></html>')

      crawl = Medusa.crawl([seed_url, https_seed], threads: 2) do |crawler|
        crawler.focus_crawl { [URI(child_url), URI(child_url)] }
      end

      expect(crawl.pages.size).to eq(2)
      expect(seed_request).to have_been_requested.once
      expect(child_request).to have_been_requested.once
      expect(https_request).not_to have_been_requested
    end

    it 'processes every redirect response page before completing its fetch task' do
      source = FakePage.new('redirect-source', links: ['redirect-child'], redirect: 'redirect-target')
      FakePage.new('redirect-child')
      visited = []
      events = []

      crawl = Medusa.crawl(source.url, threads: 2) do |crawler|
        crawler.on_every_page { events << _1.url.to_s; visited << _1.url.to_s }
        crawler.after_crawl { events << :after_crawl }
      end

      expect(crawl.pages.size).to eq(3)
      expect(visited).to contain_exactly(source.url, SPEC_DOMAIN + 'redirect-target', SPEC_DOMAIN + 'redirect-child')
      expect(events.last).to eq(:after_crawl)
    end

    it 'runs callbacks serially on one caller-thread fiber while fetches use sibling fibers' do
      root_url = URI(SPEC_DOMAIN).merge('/serialized-callback-root').to_s
      child_urls = %w[one two].map { URI(SPEC_DOMAIN).merge("/serialized-callback-#{_1}").to_s }
      stub_request(:get, root_url).to_return(
        body: child_urls.map { |url| %(<a href="#{url}">child</a>) }.join,
        headers: {'Content-Type' => 'text/html'}
      )
      request_contexts = Queue.new
      child_urls.each do |url|
        stub_request(:get, url).to_return do
          request_contexts << [Thread.current.object_id, Fiber.current.object_id]
          {body: 'child page', headers: {'Content-Type' => 'text/html'}}
        end
      end
      callback_contexts = []
      caller_thread = Thread.current.object_id

      Medusa.crawl(root_url, threads: 2) do |crawler|
        crawler.on_every_page { callback_contexts << [Thread.current.object_id, Fiber.current.object_id] }
      end

      requests = request_contexts.size.times.map { request_contexts.pop }
      expect(callback_contexts.map(&:first)).to all(eq(caller_thread))
      expect(callback_contexts.map(&:last).uniq.size).to eq(1)
      expect(requests.map(&:first)).to all(eq(caller_thread))
      expect(requests.map(&:last)).not_to include(callback_contexts.first.last)
    end

    it 're-raises worker failures and finishes owned tasks while a peer request is blocked' do
      server, gate, slow_started, root_url, _slow_url, fast_url = blocked_pair
      allow_local_http
      error = RuntimeError.new('unexpected worker failure')
      allow_any_instance_of(HTTP).to receive(:fetch_pages).and_wrap_original do |fetch, url, *arguments|
        if url.to_s == fast_url
          wait_for_async(Async::Task.current) { !slow_started.empty? }
          raise error
        end

        fetch.call(url, *arguments)
      end
      after_crawl_called = false
      core = nil
      crawl_thread = Thread.new do
        begin
          Medusa.crawl(root_url, threads: 2) do |crawler|
            core = crawler
            crawler.after_crawl { after_crawl_called = true }
          end
        rescue Exception => crawl_error
          crawl_error
        end
      end

      begin
        expect(Timeout.timeout(5) { gate.arrivals.pop }).to eq('/blocked-slow')
        expect(Timeout.timeout(5) { crawl_thread.value }).to equal(error)
        expect(after_crawl_called).to be(false)
        expect_worker_tasks_finished(core)
      ensure
        close_local_http(server, gate, slow_started)
        finish_crawl_thread(crawl_thread)
      end
    end

    it 're-raises callback failures and finishes owned tasks while a peer request is blocked' do
      server, gate, slow_started, root_url, _slow_url, fast_url = blocked_pair
      allow_local_http
      error = RuntimeError.new('page callback failed')
      after_crawl_called = false
      core = nil
      crawl_thread = Thread.new do
        begin
          Medusa.crawl(root_url, threads: 2) do |crawler|
            core = crawler
            crawler.on_every_page { |page| raise error if page.url.to_s == fast_url }
            crawler.after_crawl { after_crawl_called = true }
          end
        rescue Exception => crawl_error
          crawl_error
        end
      end

      begin
        expect(Timeout.timeout(5) { gate.arrivals.pop }).to eq('/blocked-slow')
        expect(Timeout.timeout(5) { crawl_thread.value }).to equal(error)
        expect(after_crawl_called).to be(false)
        expect_worker_tasks_finished(core)
      ensure
        close_local_http(server, gate, slow_started)
        finish_crawl_thread(crawl_thread)
      end
    end

    it 're-raises storage failures and finishes owned tasks while a peer request is blocked' do
      server, gate, slow_started, root_url, _slow_url, fast_url = blocked_pair
      allow_local_http
      error = RuntimeError.new('page storage failed')
      allow_any_instance_of(PageStore).to receive(:[]=).and_wrap_original do |write, url, page|
        raise error if url.to_s == fast_url

        write.call(url, page)
      end
      after_crawl_called = false
      core = nil
      crawl_thread = Thread.new do
        begin
          Medusa.crawl(root_url, threads: 2) do |crawler|
            core = crawler
            crawler.after_crawl { after_crawl_called = true }
          end
        rescue Exception => crawl_error
          crawl_error
        end
      end

      begin
        expect(Timeout.timeout(5) { gate.arrivals.pop }).to eq('/blocked-slow')
        expect(Timeout.timeout(5) { crawl_thread.value }).to equal(error)
        expect(after_crawl_called).to be(false)
        expect_worker_tasks_finished(core)
      ensure
        close_local_http(server, gate, slow_started)
        finish_crawl_thread(crawl_thread)
      end
    end

    RSpec.shared_examples_for "crawl" do
      it "should crawl all the html pages in a domain by following <a> href's" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'])
        pages << FakePage.new('1', :links => ['3'])
        pages << FakePage.new('2')
        pages << FakePage.new('3')

        expect(Medusa.crawl(pages[0].url, opts).pages.size).to eq(4)
      end

      it "should not follow links that leave the original domain" do
        pages = []
        pages << FakePage.new('0', :links => ['1'], :hrefs => 'http://www.other.com/')
        pages << FakePage.new('1')

        core = Medusa.crawl(pages[0].url, opts)

        expect(core.pages.size).to eq(2)
        expect(core.pages.keys).not_to include('http://www.other.com/')
      end

      it "should not follow redirects that leave the original domain" do
        pages = []
        pages << FakePage.new('0', :links => ['1'], :redirect => 'http://www.other.com/')
        pages << FakePage.new('1')

        core = Medusa.crawl(pages[0].url, opts)

        expect(core.pages.size).to eq(2)
        expect(core.pages.keys).not_to include('http://www.other.com/')
      end

      it "should follow http redirects" do
        pages = []
        pages << FakePage.new('0', :links => ['1'])
        pages << FakePage.new('1', :redirect => '2')
        pages << FakePage.new('2')

        expect(Medusa.crawl(pages[0].url, opts).pages.size).to eq(3)
      end

      it "should follow with HTTP basic authentication" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'], :auth => true)
        pages << FakePage.new('1', :links => ['3'], :auth => true)
        pages << FakePage.new('2', :auth => true)
        pages << FakePage.new('3', :auth => true)

        new_opts = opts.merge({:http_basic_authentication => AUTH})
        expect(Medusa.crawl(pages.first.url, new_opts).pages.size).to eq(4)
      end

      it "should accept multiple starting URLs" do
        pages = []
        pages << FakePage.new('0', :links => ['1'])
        pages << FakePage.new('1')
        pages << FakePage.new('2', :links => ['3'])
        pages << FakePage.new('3')

        expect(Medusa.crawl([pages[0].url, pages[2].url], opts).pages.size).to eq(4)
      end

      it "should include the query string when following links" do
        pages = []
        pages << FakePage.new('0', :links => ['1?foo=1'])
        pages << FakePage.new('1?foo=1')
        pages << FakePage.new('1')

        core = Medusa.crawl(pages[0].url, opts)

        expect(core.pages.size).to eq(2)
        expect(core.pages.keys).not_to include(pages[2].url)
      end

      it "should be able to skip links with query strings" do
        pages = []
        pages << FakePage.new('0', :links => ['1?foo=1', '2'])
        pages << FakePage.new('1?foo=1')
        pages << FakePage.new('2')

        core = Medusa.crawl(pages[0].url, opts) do |a|
          a.skip_query_strings = true
        end

        expect(core.pages.size).to eq(2)
      end

      it 'skips links based on a RegEx' do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'])
        pages << FakePage.new('1')
        pages << FakePage.new('2', :links => ['4?skip-me=no', '4?example=1&skip-me=yes'])
        pages << FakePage.new('3')
        pages << FakePage.new('4?skip-me=no')
        pages << FakePage.new('4?example=1&skip-me=yes')


        core = Medusa.crawl(pages[0].url, opts) do |a|
          a.skip_links_like(/1/, /3/, /skip-me=yes/)
        end

        expect(core.pages.size).to eq(3)
        expect(core.pages.keys).not_to include(pages[1].url)
        expect(core.pages.keys).not_to include(pages[3].url)
        expect(core.pages.keys).not_to include(pages[5].url)
      end

      it "should be able to call a block on every page" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'])
        pages << FakePage.new('1')
        pages << FakePage.new('2')

        count = 0
        Medusa.crawl(pages[0].url, opts) do |a|
          a.on_every_page { count += 1 }
        end

        expect(count).to eq(3)
      end

      it "should not discard page bodies by default" do
        Medusa.crawl(FakePage.new('0').url, opts).pages.values#.first.doc.should_not be_nil
      end

      it "should provide a focus_crawl method to select the links on each page to follow" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'])
        pages << FakePage.new('1')
        pages << FakePage.new('2')

        core = Medusa.crawl(pages[0].url, opts) do |a|
          a.focus_crawl {|p| p.links.reject{|l| l.to_s =~ /1/}}
        end

        expect(core.pages.size).to eq(2)
        expect(core.pages.keys).not_to include(pages[1].url)
      end

      it "should optionally delay between page requests" do
        delay = 0.25
        expect_any_instance_of(Tentacle).to receive(:sleep).with(delay).twice

        pages = []
        pages << FakePage.new('0', :links => '1')
        pages << FakePage.new('1')

        core = Medusa.crawl(pages[0].url, opts.merge({:delay => delay}))
        expect(core.pages.size).to eq(2)
      end

      it "should optionally obey the robots exclusion protocol" do
        pages = []
        pages << FakePage.new('0', :links => '1')
        pages << FakePage.new('1')
        pages << FakePage.new('robots.txt', body: "User-agent: *\nDisallow: /1", content_type: 'text/plain')
        core = Medusa.crawl(pages[0].url, opts.merge(obey_robots_txt: true))

        expect(core.pages.keys).to include(pages[0].url)
        expect(core.pages.keys).not_to include(pages[1].url)
      end

      it "should be able to set cookies to send with HTTP requests" do
        cookies = {:a => '1', :b => '2'}
        core = Medusa.crawl(FakePage.new('0').url) do |medusa|
          medusa.cookies = cookies
        end
        expect(core.opts[:cookies]).to eq(cookies)
      end

      it "should freeze the options once the crawl begins" do
        core = Medusa.crawl(FakePage.new('0').url) do |medusa|
          medusa.threads = 4
          medusa.on_every_page do
            expect{ medusa.threads = 2 }.to raise_error(RuntimeError)
          end
        end
        expect(core.opts[:threads]).to eq(4)
      end

      describe "many pages" do
        before(:each) do
          @pages, size = [], 5

          size.times do |n|
            # register this page with a link to the next page
            link = (n + 1).to_s if n + 1 < size
            @pages << FakePage.new(n.to_s, :links => Array(link))
          end
        end

        it "should track the page depth and referer" do
          core = Medusa.crawl(@pages[0].url, opts)
          previous_page = nil

          @pages.each_with_index do |page, i|
            page = core.pages[page.url]
            expect(page.depth).to eq(i)

            if previous_page
              expect(page.referer).to eq(previous_page.url)
            else
              expect(page.referer).to be_nil
            end
            previous_page = page
          end
        end

        it "should optionally limit the depth of the crawl" do
          core = Medusa.crawl(@pages[0].url, opts.merge({:depth_limit => 3}))
          expect(core.pages.size).to eq(4)
        end
      end

    end

    context 'using the default storage' do
      let(:opts) { Hash.new }

      it_should_behave_like "crawl"
    end

    describe "options" do
      before(:each) do
        FakePage.new
        FakePage.new('robots.txt', body: "User-agent: *\nDisallow: /1", content_type: 'text/plain')
      end

      it "should accept options for the crawl" do
        core = Medusa.crawl(SPEC_DOMAIN, :threads => 2,
                                          :discard_page_bodies => true,
                                          :user_agent => 'test',
                                          :obey_robots_txt => true,
                                          :depth_limit => 3)

        expect(core.opts[:threads]).to eq(2)
        expect(core.opts[:discard_page_bodies]).to eq(true)
        expect(core.opts[:delay]).to eq(0)
        expect(core.opts[:user_agent]).to eq('test')
        expect(core.opts[:obey_robots_txt]).to eq(true)
        expect(core.opts[:depth_limit]).to eq(3)
      end

      it "should accept options via setter methods in the crawl block" do
        core = Medusa.crawl(SPEC_DOMAIN) do |a|
          a.threads = 2
          a.discard_page_bodies = true
          a.user_agent = 'test'
          a.obey_robots_txt = true
          a.depth_limit = 3
        end

        expect(core.opts[:threads]).to eq(2)
        expect(core.opts[:discard_page_bodies]).to eq(true)
        expect(core.opts[:delay]).to eq(0)
        expect(core.opts[:user_agent]).to eq('test')
        expect(core.opts[:obey_robots_txt]).to eq(true)
        expect(core.opts[:depth_limit]).to eq(3)
      end

      it "should use 1 thread if a delay is requested" do
        allow_any_instance_of(Tentacle).to receive(:sleep)
        expect(Medusa.crawl(SPEC_DOMAIN, :delay => 1, :threads => 2).opts[:threads]).to be(1)
      end

      it 'rejects non-positive or non-integer worker limits before clearing storage' do
        [0, -1, '2'].each do |workers|
          storage = Storage.Moneta(:Memory)
          expect(storage).not_to receive(:clear)

          expect { Medusa.crawl(SPEC_DOMAIN, threads: workers, storage:) }
            .to raise_error(ArgumentError, /threads must be a positive Integer/)
        end

        allow_any_instance_of(Tentacle).to receive(:sleep)
        expect(Medusa.crawl(SPEC_DOMAIN, delay: 1, threads: 0).opts[:threads]).to eq(1)
      end
    end

  end
end
