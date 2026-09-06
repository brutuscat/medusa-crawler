# frozen_string_literal: true

require 'medusa'

module BasicAuth
  module_function

  def crawl(start_url:, username:, password:, **options, &block)
    Medusa.crawl(
      start_url,
      options.merge(http_basic_authentication: [username, password]),
      &block
    )
  end
end

if $PROGRAM_NAME == __FILE__
  crawl = BasicAuth.crawl(
    start_url: ENV.fetch('MEDUSA_SITE_URL'),
    username: ENV.fetch('MEDUSA_USERNAME'),
    password: ENV.fetch('MEDUSA_PASSWORD')
  )

  crawl.pages.each_value { |page| puts "#{page.code} #{page.url}" }
end
