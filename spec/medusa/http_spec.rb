# frozen_string_literal: true

require 'medusa/http'
require 'fakeweb_helper'

module Medusa
  RSpec.describe HTTP do

    describe "fetch_page" do
      before(:each) do
        WebMock.reset!
      end

      it "should still return a Page if an exception occurs during the HTTP connection" do
        allow_any_instance_of(Medusa::HTTP).to receive(:get_response).and_raise(StandardError, 'HARDCODED FAILURE!')
        http = Medusa::HTTP.new
        expect(http.fetch_page(SPEC_DOMAIN)).to be_an_instance_of(Page)
      end

      it 'keeps the Page API unchanged when HTTP caching is disabled' do
        page = Medusa::HTTP.new.fetch_page(FakePage.new('uncached').url)

        expect(page).not_to respond_to(:from_cache?)
      end

      it 'revalidates through OpenURI and returns the stored representation after 304' do
        url = URI(SPEC_DOMAIN).merge('/etag').to_s
        store = {}
        stub_request(:get, url)
          .to_return(body: 'version one', status: 200,
                     headers: {'Content-Type' => 'text/plain', 'ETag' => '"v1"'})
          .then
          .to_return(body: '', status: 304, headers: {'ETag' => '"v1"'})

        http = Medusa::HTTP.new(http_cache: {store: store, strategy: :revalidation})
        first = http.fetch_page(url)
        second = http.fetch_page(url)

        expect(first.from_cache?).to be(false)
        expect(second.from_cache?).to be(true)
        expect(second.code).to eq(200)
        expect(second.body).to eq('version one')
        expect(second.response_time).to be_a(Integer)
        expect(a_request(:get, url).with(headers: {'If-None-Match' => '"v1"'})).to have_been_made.once
      end

      it 'serves a fresh cached Page without another OpenURI request' do
        url = URI(SPEC_DOMAIN).merge('/fresh').to_s
        stub = stub_request(:get, url)
          .to_return(body: 'fresh', status: 200,
                     headers: {'Content-Type' => 'text/plain', 'Cache-Control' => 'private, max-age=60'})

        http = Medusa::HTTP.new(http_cache: {store: {}, strategy: :freshness})
        first = http.fetch_page(url)
        second = http.fetch_page(url)

        expect(first.from_cache?).to be(false)
        expect(second.from_cache?).to be(true)
        expect(second.body).to eq('fresh')
        expect(second.response_time).to be_nil
        expect(stub).to have_been_requested.once
      end
    end
  end
end
