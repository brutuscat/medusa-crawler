# frozen_string_literal: true

require_relative '../../examples/private_site_with_login'

site_url = 'https://the-internet.herokuapp.com/secure'
page = nil
message = nil

3.times do |attempt|
  message = nil
  crawl = PrivateSiteWithLogin.crawl(
    start_url: site_url,
    login_url: 'https://the-internet.herokuapp.com/authenticate',
    username: 'tomsmith',
    password: 'SuperSecretPassword!',
    threads: 1,
    read_timeout: 15
  ) do |crawler|
    crawler.focus_crawl { [] }
    crawler.on_pages_like(%r{/secure\z}) do |crawled_page|
      message = crawled_page.doc&.at_css('h4.subheader')&.text&.strip if crawled_page.code == 200
    end
  end

  page = crawl.pages[URI(site_url)]
  break if page&.code == 200 && message&.start_with?('Welcome to the Secure Area')

  warn "Authenticated crawl attempt #{attempt + 1} failed; retrying" if attempt < 2
end

abort "Expected #{site_url} to return HTTP 200, got #{page&.code || 'no response'}" unless page&.code == 200
abort 'Authenticated content was not found' unless message&.start_with?('Welcome to the Secure Area')

puts "Extracted from authenticated page: #{message}"
