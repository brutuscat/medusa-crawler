spec = Gem::Specification.new do |s|
  s.name = 'medusa-crawler'
  s.version = '1.0.0'
  s.summary = 'Medusa is a ruby crawler framework'
  s.authors = ['Mauro Asprea', 'Chris Kite']
  s.homepage = 'https://github.com/brutuscat/medusa-crawler'
  s.email = 'mauroasprea@gmail.com'
  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 2.3.0'

  # Make the description be the first block of the readme rdoc file
  open('README.rdoc') do |readme|
    s.description = readme.read.partition('---').first
  end

  s.require_path = 'lib'
  s.rdoc_options << '-m' << 'README.rdoc' << '-t' << 'Medusa'
  s.extra_rdoc_files = ['README.rdoc']
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
    README.rdoc
    Rakefile
  ] + Dir['lib/**/*.rb']

  s.test_files = Dir['spec/*.rb']
end
