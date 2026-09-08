# frozen_string_literal: true

require 'tmpdir'
require_relative 'support/docs_server'
require_relative 'support/medusa_docs_scanner'

namespace :docs do
  desc 'Render and crawl Markdown/RDoc documentation for broken internal links'
  task :links do
    sources = Dir.glob(['*.md', '*.rdoc', 'docs/**/*.md', 'docs/**/*.rdoc']).sort
    abort 'No documentation files found' if sources.empty?

    Dir.mktmpdir('medusa-docs-') do |tmpdir|
      output = File.join(tmpdir, 'rdoc')
      sh Gem.ruby, '-S', 'rdoc', '--quiet', '--op', output, '--main', 'README.rdoc', *sources

      DocumentationCheck::Server.new(output).with_url do |url|
        crawl, broken = DocumentationCheck::MedusaDocsScanner.scan(url)

        broken.sort_by { |page| page.url.to_s }.each do |page|
          status = page.code || page.error&.class || 'unfetched'
          warn "#{status} #{page.url} (from #{page.referer})"
        end

        abort "#{broken.length} broken internal documentation link(s)" unless broken.empty?

        puts "Checked #{crawl.pages.size} rendered documentation pages: no broken internal links"
      end
    end
  end
end
