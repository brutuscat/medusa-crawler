# frozen_string_literal: true

require 'medusa'
require 'net/http'
require 'uri'
require 'webrick/cookie'

module PrivateSiteWithLogin
  module_function

  def login_cookies(login_url:, username:, password:)
    response = Net::HTTP.post_form(
      URI(login_url),
      'username' => username,
      'password' => password
    )

    unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
      raise "Login failed with HTTP #{response.code}"
    end

    cookies = response.get_fields('Set-Cookie').to_a.flat_map do |header|
      WEBrick::Cookie.parse_set_cookies(header)
    end

    raise 'Login response did not set a session cookie' if cookies.empty?

    cookies.to_h { |cookie| [cookie.name, cookie.value] }
  end

  def crawl(start_url:, login_url:, username:, password:, **options, &block)
    cookies = login_cookies(login_url: login_url, username: username, password: password)

    Medusa.crawl(start_url, options.merge(cookies: cookies, accept_cookies: true), &block)
  end
end

if $PROGRAM_NAME == __FILE__
  site_url = ENV.fetch('MEDUSA_SITE_URL', 'https://www.example.com/private/')
  login_url = ENV.fetch('MEDUSA_LOGIN_URL', 'https://www.example.com/login')

  crawl = PrivateSiteWithLogin.crawl(
    start_url: site_url,
    login_url: login_url,
    username: ENV.fetch('MEDUSA_USERNAME'),
    password: ENV.fetch('MEDUSA_PASSWORD')
  )

  crawl.pages.each_value { |page| puts page.url if page.fetched? }
end
