# frozen_string_literal: true

require 'logger'
require 'medusa'

url = ARGV.fetch(0, 'https://www.example.com/')
cache_dir = ENV.fetch('MEDUSA_HTTP_CACHE_DIR', '.medusa-http-cache')
cache_store = Medusa::Storage.Moneta(:File, dir: cache_dir)
logger = Logger.new($stderr)
logger.level = Logger::DEBUG

Medusa.crawl(
  url,
  http_cache: {store: cache_store, strategy: :revalidation},
  logger: logger
) do |crawler|
  crawler.on_every_page do |page|
    source = page.from_cache? ? 'stored representation' : 'network representation'
    puts "#{page.code} #{source} #{page.url}"
  end
end
