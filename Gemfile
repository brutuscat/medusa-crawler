source 'https://rubygems.org'

gemspec

group :test, :development do
  gem 'rake', '>=0.9.2'
  gem 'rdoc', '>=3.12'
  gem 'rspec', '>=3.9'
  gem 'fakeweb', github: 'chrisk/fakeweb', ref: '2b08c1f'
  gem 'redis', '>=2.2.0'
  gem 'bson_ext', '>=1.3.1'
  gem 'pry'
  # A command line tool to easily handle events on file system modifications, wo we can continuously run specs.
  gem 'guard'
  # Guard plugin for rspec
  gem 'guard-rspec', require: false
  # Guard notification plugin
  gem 'terminal-notifier-guard'
end
