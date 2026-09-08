# frozen_string_literal: true

require 'medusa'
require 'tmpdir'
require 'timeout'
require 'webrick'

namespace :docs do
  desc 'Render and crawl Markdown/RDoc documentation for broken internal links'
  task :links do
    sources = Dir.glob(['*.md', '*.rdoc', 'docs/**/*.md', 'docs/**/*.rdoc']).sort
    abort 'No documentation files found' if sources.empty?

    Dir.mktmpdir('medusa-docs-') do |tmpdir|
      output = File.join(tmpdir, 'rdoc')
      sh Gem.ruby, '-S', 'rdoc', '--quiet', '--op', output, '--main', 'README.rdoc', *sources

      server = WEBrick::HTTPServer.new(
        BindAddress: '127.0.0.1',
        Port: 0,
        DocumentRoot: output,
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )
      port = server.listeners.first.addr[1]
      server_thread = Thread.new { server.start }

      begin
        Timeout.timeout(5) { sleep 0.01 until server.status == :Running }

        crawl = Medusa.crawl("http://127.0.0.1:#{port}/", threads: 2, read_timeout: 5)
        broken = crawl.pages.values.select do |page|
          page.error || !page.fetched? || page.code.to_i >= 400
        end

        broken.sort_by { |page| page.url.to_s }.each do |page|
          status = page.code || page.error&.class || 'unfetched'
          warn "#{status} #{page.url} (from #{page.referer})"
        end

        abort "#{broken.length} broken internal documentation link(s)" unless broken.empty?

        puts "Checked #{crawl.pages.size} rendered documentation pages: no broken internal links"
      ensure
        server.shutdown
        server_thread.join
      end
    end
  end
end
