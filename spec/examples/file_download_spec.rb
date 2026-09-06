# frozen_string_literal: true

require 'fakeweb_helper'
require 'tmpdir'
require_relative '../../examples/file_download'

RSpec.describe FileDownload do
  it 'writes linked non-HTML responses to the destination directory' do
    start_url = 'https://www.example.com/download'
    file_url = 'https://www.example.com/files/report.txt'
    stub_request(:get, start_url)
      .to_return(body: '<a href="/files/report.txt">Report</a>', headers: { 'Content-Type' => 'text/html' })
    stub_request(:get, file_url)
      .to_return(body: 'report contents', headers: { 'Content-Type' => 'text/plain' })

    Dir.mktmpdir do |directory|
      described_class.crawl(start_url: start_url, destination: directory)

      expect(File.binread(File.join(directory, 'report.txt'))).to eq('report contents')
    end
  end

  it 'downloads files from the local download page', :smoke do
    WebMock.allow_net_connect!

    Dir.mktmpdir do |directory|
      begin
        crawl = described_class.crawl(
          start_url: "#{ENV.fetch('MEDUSA_SMOKE_BASE_URL')}/download",
          destination: directory,
          threads: 1
        )

        expect(crawl.pages.values.count { |page| page.code == 200 && !page.html? }).to be_positive
        expect(Dir.children(directory)).not_to be_empty
      ensure
        WebMock.disable_net_connect!
      end
    end
  end
end
