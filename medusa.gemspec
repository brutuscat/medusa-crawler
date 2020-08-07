spec = Gem::Specification.new do |s|
  s.name = 'medusa-crawler'
  s.version = '1.0.0.pre.1'
  s.authors = ['Mauro Asprea', 'Chris Kite']
  s.homepage = 'https://github.com/brutuscat/medusa-crawler'
  s.platform = Gem::Platform::RUBY
  s.summary = 'Medusa is a ruby crawler framework'
  s.description = <<~DESCRIPTION.strip
    == Medusa: a ruby crawler framework {rdoc-image:https://badge.fury.io/rb/medusa-crawler.svg}[https://badge.fury.io/rb/medusa-crawler] rdoc-image:https://github.com/brutuscat/medusa-crawler/workflows/Ruby/badge.svg?event=push

    Medusa is a framework for the ruby language to crawl and collect useful information about the pages
    it visits. It is versatile, allowing you to write your own specialized tasks quickly and easily.

    === Features

    * Choose the links to follow on each page with +focus_crawl+
    * Multi-threaded design for high performance
    * Tracks +301+ HTTP redirects
    * Allows exclusion of URLs based on regular expressions
    * HTTPS support
    * Records response time for each page
    * Obey _robots.txt_ directives (optional, but recommended)
    * In-memory or persistent storage of pages during crawl, provided by Moneta[https://github.com/moneta-rb/moneta]
    * Inherits OpenURI behavior (redirects, automatic charset and encoding detection, proxy configuration options).

    <b>Do you have an idea or a suggestion? {Open an issue and talk about it}[https://github.com/brutuscat/medusa-crawler/issues/new]</b>
  DESCRIPTION

  s.executables = %w[medusa]
  s.require_path = 'lib'
  s.rdoc_options << '-m' << 'README.md' << '-t' << 'Medusa'
  s.extra_rdoc_files = ['README.md']
  s.add_runtime_dependency('moneta', '~> 1.3', '>= 1.3.0')
  s.add_runtime_dependency('nokogiri', '~> 1.3', '>= 1.3.0')
  s.add_runtime_dependency('robotex', '~> 1.0', '>= 1.0.0')
  s.cert_chain  = ['certs/brutuscat.pem']
  s.signing_key = File.expand_path('~/.ssh/gem-private_key.pem') if $0 =~ /gem\z/
  s.licenses    = %w[MIT]

  s.metadata = {
    'bug_tracker_uri' => 'https://github.com/brutuscat/medusa-crawler/issues',
    'source_code_uri' => "https://github.com/brutuscat/medusa-crawler/tree/v#{s.version}",
    'description_markup_format' => 'rdoc',
  }

  s.files = %w[
    VERSION
    LICENSE.txt
    CHANGELOG.md
    CONTRIBUTORS.md
    README.md
    Rakefile
  ] + Dir['lib/**/*.rb']

  s.test_files = Dir['spec/*.rb']
end
