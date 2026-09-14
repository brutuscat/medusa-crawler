# frozen_string_literal: true

require 'medusa/http'
require 'fakeweb_helper'

module Medusa
  RSpec.describe HTTP do
    it 'keeps the response transport private' do
      expect(described_class.const_get(:Response, false).superclass).to eq(Data)
      expect { described_class::Response }.to raise_error(NameError, /private constant/)
    end

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

      it 'rejects unsupported cache configuration' do
        expect { described_class.new(http_cache: Object.new) }.to raise_error(ArgumentError, /http_cache/)
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

      it 'preserves exact network response semantics' do
        source = FakePage.new('uncached', body: 'network body', content_type: 'text/plain')
        page = Medusa::HTTP.new.fetch_page(source.url)

        expect(page.url).to eq(URI(source.url))
        expect(page.body).to eq('network body')
        expect(page.code).to eq(200)
        expect(page.response_time).to be_a(Integer)
        expect(page.from_cache?).to be(false)
      end

      it 'uses the URI actually requested for every redirect Page hop' do
        source = FakePage.new('redirect-source', redirect: 'redirect-target')
        target = URI(SPEC_DOMAIN).merge('/redirect-target')

        pages = Medusa::HTTP.new.fetch_pages(source.url)

        expect(pages.map(&:url)).to eq([URI(source.url), target])
        expect(pages.map(&:redirect_to)).to eq([target, nil])
      end

      it 'shares accepted cookies between HTTP clients' do
        first_url = URI(SPEC_DOMAIN).merge('/login').to_s
        second_url = URI(SPEC_DOMAIN).merge('/private').to_s
        stub_request(:get, first_url)
          .to_return(status: 200, headers: {'Set-Cookie' => 'session=abc123; Path=/'})
        second_request = stub_request(:get, second_url)
          .with(headers: {'Cookie' => 'session=abc123'})
          .to_return(status: 200, body: 'Private page')

        cookie_store = CookieStore.new
        options = {accept_cookies: true, cookie_store:}
        Medusa::HTTP.new(options).fetch_page(first_url)
        page = Medusa::HTTP.new(options).fetch_page(second_url)

        expect(page.body).to eq('Private page')
        expect(second_request).to have_been_requested.once
      end

      it 'preserves exact revalidated response semantics after 304' do
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

        expect(first.url).to eq(URI(url))
        expect(first.body).to eq('version one')
        expect(first.code).to eq(200)
        expect(first.response_time).to be_a(Integer)
        expect(first.from_cache?).to be(false)

        expect(second.url).to eq(URI(url))
        expect(second.body).to eq('version one')
        expect(second.code).to eq(200)
        expect(second.response_time).to be_a(Integer)
        expect(second.from_cache?).to be(true)
        expect(a_request(:get, url).with(headers: {'If-None-Match' => '"v1"'})).to have_been_made.once
      end

      it 'preserves exact fresh-cache response semantics without another OpenURI request' do
        url = URI(SPEC_DOMAIN).merge('/fresh').to_s
        stub = stub_request(:get, url)
          .to_return(body: 'fresh', status: 200,
                     headers: {'Content-Type' => 'text/plain', 'Cache-Control' => 'private, max-age=60'})

        cache = HTTP::Cache.new(storage: {}, strategy: :freshness)
        http = Medusa::HTTP.new(http_cache: cache)
        first = http.fetch_page(url)
        second = http.fetch_page(url)

        expect(first.url).to eq(URI(url))
        expect(first.body).to eq('fresh')
        expect(first.code).to eq(200)
        expect(first.response_time).to be_a(Integer)
        expect(first.from_cache?).to be(false)

        expect(second.url).to eq(URI(url))
        expect(second.body).to eq('fresh')
        expect(second.code).to eq(200)
        expect(second.response_time).to be_nil
        expect(second.from_cache?).to be(true)
        expect(stub).to have_been_requested.once
      end
    end
  end
end
