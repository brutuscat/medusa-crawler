# frozen_string_literal: true

require 'fakeweb_helper'
require_relative '../../examples/nested_frames'

RSpec.describe NestedFrames do
  it 'adds frame and iframe sources to the crawl' do
    start_url = 'https://www.example.com/frames'
    frame_url = 'https://www.example.com/frame'
    iframe_url = 'https://www.example.com/iframe'
    stub_request(:get, start_url)
      .to_return(
        body: '<frame src="/frame"><iframe src="/iframe"></iframe>',
        headers: { 'Content-Type' => 'text/html' }
      )
    [frame_url, iframe_url].each do |url|
      stub_request(:get, url).to_return(body: 'Frame content', headers: { 'Content-Type' => 'text/html' })
    end

    crawl = described_class.crawl(start_url: start_url)

    expect(crawl.pages.keys.map(&:to_s)).to contain_exactly(start_url, frame_url, iframe_url)
  end

  it 'crawls nested frames from the local example', :smoke do
    WebMock.allow_net_connect!

    begin
      base_url = ENV.fetch('MEDUSA_SMOKE_BASE_URL')
      crawl = described_class.crawl(start_url: "#{base_url}/nested_frames", threads: 1)

      expect(crawl.pages.keys.map(&:to_s)).to include("#{base_url}/frame_top", "#{base_url}/frame_middle")
    ensure
      WebMock.disable_net_connect!
    end
  end
end
