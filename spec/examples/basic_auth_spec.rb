# frozen_string_literal: true

require 'fakeweb_helper'
require_relative '../../examples/basic_auth'

RSpec.describe BasicAuth do
  it 'crawls with HTTP Basic authentication' do
    url = 'https://www.example.com/basic_auth'
    stub_request(:get, url).with(basic_auth: %w[admin admin])
      .to_return(body: 'Authenticated', headers: { 'Content-Type' => 'text/html' })

    crawl = described_class.crawl(start_url: url, username: 'admin', password: 'admin')

    expect(crawl.pages[URI(url)]&.code).to eq(200)
  end

  it 'crawls the local Basic authentication page', :smoke do
    WebMock.allow_net_connect!
    url = "#{ENV.fetch('MEDUSA_SMOKE_BASE_URL')}/basic_auth"

    begin
      crawl = described_class.crawl(start_url: url, username: 'admin', password: 'admin', threads: 1)

      expect(crawl.pages[URI(url)]&.code).to eq(200)
      expect(crawl.pages[URI(url)]&.doc&.text).to include('Congratulations')
    ensure
      WebMock.disable_net_connect!
    end
  end
end
