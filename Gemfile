required_bundler = Gem::Version.new('4.0.13')
if Gem::Version.new(Bundler::VERSION) < required_bundler
  raise "Medusa development requires Bundler >= #{required_bundler}"
end

source 'https://rubygems.org', cooldown: 3

# This is a library: Gemfile.lock is intentionally not committed. Consumers
# resolve medusa-crawler inside their own dependency graph and lockfile.
gemspec

group :test, :development do
  gem 'rake', '>=0.9.2', '< 14'
  gem 'rdoc', '>=3.12', '< 7'
  gem 'rspec', '>=3.9', '< 4'
  gem 'webmock', '< 4'
end

group :debugging_tools, optional: true do
  gem 'pry-byebug', '< 4'
end
