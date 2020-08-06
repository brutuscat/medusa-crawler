spec = Gem::Specification.new do |s|
  s.name = 'medusa'
  s.version = '1.0.0.pre.1'
  s.authors = ['Mauro Asprea', 'Chris Kite']
  s.homepage = 'https://github.com/brutuscat/medusa-crawler'
  s.platform = Gem::Platform::RUBY
  s.summary = 'The Medusa Crawler'
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
