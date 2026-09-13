# frozen_string_literal: true

require 'medusa/http'
require 'fakeweb_helper'

module Medusa
  RSpec.describe HTTP do

    describe '.new' do
      it 'keeps the pre-2.0 positional options API' do
        expect(described_class.instance_method(:initialize).parameters).to eq([[:opt, :opts]])

        options = {user_agent: 'legacy crawler', redirect_limit: 2}
        http = described_class.new(options)

        expect(http.user_agent).to eq('legacy crawler')
        expect(http.redirect_limit).to eq(2)
      end

      it 'accepts the traditional keyword-looking options Hash' do
        http = described_class.new(user_agent: 'legacy crawler', redirect_limit: 2)

        expect(http.user_agent).to eq('legacy crawler')
        expect(http.redirect_limit).to eq(2)
      end

      it 'accepts cache configuration through the options Hash' do
        http = described_class.new(http_cache: {storage: {}, strategy: :freshness})

        expect(http.instance_variable_get(:@cache)).to be_a(HTTP::Cache)
        expect(http.instance_variable_get(:@cache).strategy).to eq(:freshness)
      end

      it 'uses an existing cache instance from the options Hash' do
        cache = HTTP::Cache.new(storage: {})
        http = described_class.new(http_cache: cache)

        expect(http.instance_variable_get(:@cache)).to equal(cache)
      end
    end

    describe "fetch_page" do
      before(:each) do
        WebMock.reset!
      end

      it "should still return a Page if an exception occurs during the HTTP connection" do
        allow_any_instance_of(Medusa::HTTP).to receive(:get_response).and_raise(StandardError, 'HARDCODED FAILURE!')
        http = Medusa::HTTP.new
        expect(http.fetch_page(SPEC_DOMAIN)).to be_an_instance_of(Page)
      end

      it 'records a transient network error after retries are exhausted' do
        url = URI(SPEC_DOMAIN).merge('/timeout')
        http = Medusa::HTTP.new
        allow(URI).to receive(:open).and_raise(Timeout::Error)
        allow(http).to receive(:sleep)

        page = http.fetch_page(url)

        expect(page.error).to be_a(Timeout::Error)
        expect(URI).to have_received(:open).exactly(HTTP::RETRY_LIMIT + 1).times
      end

      it 'marks an ordinary network Page as not cached' do
        page = Medusa::HTTP.new.fetch_page(FakePage.new('uncached').url)

        expect(page.from_cache?).to be(false)
      end

      it 'revalidates through OpenURI and returns the stored representation after 304' do
        url = URI(SPEC_DOMAIN).merge('/etag').to_s
        storage = {}
        stub_request(:get, url)
          .to_return(body: 'version one', status: 200,
                     headers: {'Content-Type' => 'text/plain', 'ETag' => '"v1"'})
          .then
          .to_return(body: '', status: 304, headers: {'ETag' => '"v1"'})

        cache = HTTP::Cache.new(storage:, strategy: :revalidation)
        http = Medusa::HTTP.new(http_cache: cache)
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

        cache = HTTP::Cache.new(storage: {}, strategy: :freshness)
        http = Medusa::HTTP.new(http_cache: cache)
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
