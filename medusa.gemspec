spec = Gem::Specification.new do |s|
  s.name = "medusa"
  s.version = "0.0.2"
  s.authors = ["Chris Kite", "Mauro Asprea"]
  s.homepage = "https://github.com/brutuscat/medusa"
  s.platform = Gem::Platform::RUBY
  s.summary = "Medusa web-spider framework"
  s.executables = %w[medusa]
  s.require_path = "lib"
  s.rdoc_options << '-m' << 'README.md' << '-t' << 'Medusa'
  s.extra_rdoc_files = ["README.md"]
  s.add_dependency("nokogiri", ">= 1.3.0")
  s.add_dependency("robotex", ">= 1.0.0")

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
