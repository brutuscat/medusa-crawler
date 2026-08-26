# frozen_string_literal: true

require 'fakeweb_helper'
require_relative '../../examples/private_site_with_login'

RSpec.describe PrivateSiteWithLogin do
  let(:login_url) { 'https://www.example.com/login' }
  let(:start_url) { 'https://www.example.com/private/' }

  it 'uses the session cookie returned by the login form to crawl private pages' do
    stub_request(:post, login_url)
      .with(
        body: { 'username' => 'user', 'password' => 'secret' },
        headers: { 'User-Agent' => "Medusa/#{Medusa::VERSION}" }
      )
      .to_return(status: 302, headers: { 'Set-Cookie' => 'session=abc123; Path=/; HttpOnly' })

    stub_request(:get, start_url)
      .with(headers: { 'Cookie' => 'session=abc123' })
      .to_return(body: '<a href="/private/next">Next</a>', headers: { 'Content-Type' => 'text/html' })

    stub_request(:get, 'https://www.example.com/private/next')
      .with(headers: { 'Cookie' => 'session=abc123' })
      .to_return(body: 'Private page', headers: { 'Content-Type' => 'text/html' })

    crawl = described_class.crawl(
      start_url: start_url,
      login_url: login_url,
      username: 'user',
      password: 'secret'
    )

    expect(crawl.pages.keys.map(&:to_s)).to contain_exactly(
      start_url,
      'https://www.example.com/private/next'
    )
  end

  it 'fails clearly when the login is rejected' do
    stub_request(:post, login_url).to_return(status: 401)

    expect do
      described_class.login_cookies(
        login_url: login_url,
        username: 'user',
        password: 'bad',
        user_agent: "Medusa/#{Medusa::VERSION}"
      )
    end.to raise_error('Login failed with HTTP 401')
  end

  it 'uses the same custom user agent for login and crawling' do
    user_agent = 'Private crawler/1.0'
    stub_request(:post, login_url)
      .with(headers: { 'User-Agent' => user_agent })
      .to_return(status: 302, headers: { 'Set-Cookie' => 'session=abc123; Path=/' })
    stub_request(:get, start_url)
      .with(headers: { 'Cookie' => 'session=abc123', 'User-Agent' => user_agent })
      .to_return(body: 'Private page', headers: { 'Content-Type' => 'text/html' })

    described_class.crawl(
      start_url: start_url,
      login_url: login_url,
      username: 'user',
      password: 'secret',
      user_agent: user_agent
    )

    expect(a_request(:post, login_url).with(headers: { 'User-Agent' => user_agent })).to have_been_made.once
    expect(a_request(:get, start_url).with(headers: { 'User-Agent' => user_agent })).to have_been_made.once
  end
end
