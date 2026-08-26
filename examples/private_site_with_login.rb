# frozen_string_literal: true

require 'medusa'
require 'net/http'
require 'uri'
require 'webrick/cookie'

module PrivateSiteWithLogin
  module_function

  def login_cookies(login_url:, username:, password:, user_agent: "Medusa/#{Medusa::VERSION}")
    uri = URI(login_url)
    request = Net::HTTP::Post.new(uri)
    request['User-Agent'] = user_agent
    request.set_form_data('username' => username, 'password' => password)
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end

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
    user_agent = options.fetch(:user_agent, "Medusa/#{Medusa::VERSION}")
    cookies = login_cookies(
      login_url: login_url,
      username: username,
      password: password,
      user_agent: user_agent
    )

    Medusa.crawl(
      start_url,
      options.merge(user_agent: user_agent, cookies: cookies, accept_cookies: true),
      &block
    )
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
