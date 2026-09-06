# frozen_string_literal: true

require 'fakeweb_helper'
require_relative '../../examples/broken_images'

RSpec.describe BrokenImages do
  it 'reports image responses with error status codes' do
    start_url = 'https://www.example.com/images'
    missing_url = 'https://www.example.com/missing.png'
    stub_request(:get, start_url)
      .to_return(body: '<img src="/present.png"><img src="/missing.png">', headers: { 'Content-Type' => 'text/html' })
    stub_request(:get, 'https://www.example.com/present.png')
      .to_return(body: 'image', headers: { 'Content-Type' => 'image/png' })
    stub_request(:get, missing_url)
      .to_return(status: 404, body: 'missing', headers: { 'Content-Type' => 'image/png' })

    _, broken = described_class.crawl(start_url: start_url)

    expect(broken.map(&:url).map(&:to_s)).to eq([missing_url])
  end

  it 'reports broken images from the local example', :smoke do
    WebMock.allow_net_connect!

    begin
      _, broken = described_class.crawl(start_url: "#{ENV.fetch('MEDUSA_SMOKE_BASE_URL')}/broken_images", threads: 1)

      expect(broken).not_to be_empty
      expect(broken).to all(have_attributes(code: 404))
    ensure
      WebMock.disable_net_connect!
    end
  end
end
