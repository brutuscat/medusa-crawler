# frozen_string_literal: true

require 'medusa/http/cache'

module Medusa
  RSpec.describe HTTP::Cache do
    let(:url) { URI('https://www.example.com/resource') }
    let(:storage) { {} }
    let(:response_class) { HTTP.const_get(:Response, false) }

    def response(body: '', headers: {}, code: 200, response_time: 1, response_url: url)
      response_class.new(
        url: response_url,
        body:,
        headers:,
        response_time:,
        code:,
        redirect_to: nil,
        from_cache: false
      )
    end

    describe '.from' do
      it 'disables caching for nil or false' do
        expect(described_class.from(nil)).to be_nil
        expect(described_class.from(false)).to be_nil
      end

      it 'creates the default cache for true' do
        expect(described_class.from(true)).to be_a(described_class)
      end

      it 'creates a configured cache from a Hash' do
        cache = described_class.from({storage: {}, strategy: :freshness})

        expect(cache.strategy).to eq(:freshness)
      end

      it 'returns an existing cache unchanged' do
        cache = described_class.new(storage: {})

        expect(described_class.from(cache)).to equal(cache)
      end

      it 'rejects unsupported configuration' do
        expect { described_class.from(Object.new) }.to raise_error(ArgumentError, /http_cache/)
      end
    end

    it 'revalidates an ETag and reuses the stored representation after 304' do
      cache = described_class.new(storage:, strategy: :revalidation)

      first = cache.fetch(url) do |headers|
        expect(headers).not_to have_key('if-none-match')
        response(body: 'version one', headers: {'etag' => '"v1"'})
      end

      second = cache.fetch(url) do |headers|
        expect(headers['if-none-match']).to eq('"v1"')
        response(code: 304, headers: {'etag' => '"v1"'})
      end

      expect(first.url).to eq(url)
      expect(first.from_cache).to be(false)
      expect(second.url).to eq(url)
      expect(second.from_cache).to be(true)
      expect(second.code).to eq(200)
      expect(second.body).to eq('version one')
    end

    it 'sends Last-Modified when ETag is unavailable' do
      cache = described_class.new(storage:, strategy: :revalidation)
      modified = 'Wed, 09 Sep 2026 14:20:00 GMT'

      cache.fetch(url) { response(body: 'body', headers: {'last-modified' => modified}) }

      cache.fetch(url) do |headers|
        expect(headers['if-modified-since']).to eq(modified)
        response(code: 304, headers: {'last-modified' => modified})
      end
    end

    it 'sends both validators when both are available' do
      cache = described_class.new(storage:, strategy: :revalidation)
      modified = 'Wed, 09 Sep 2026 14:20:00 GMT'

      cache.fetch(url) do
        response(body: 'body', headers: {'etag' => '"v1"', 'last-modified' => modified})
      end

      cache.fetch(url) do |headers|
        expect(headers['if-none-match']).to eq('"v1"')
        expect(headers['if-modified-since']).to eq(modified)
        response(code: 304, headers: {'etag' => '"v1"'})
      end
    end

    it 'serves a fresh private response without contacting the origin' do
      cache = described_class.new(storage:, strategy: :freshness)
      requests = 0

      cache.fetch(url) do
        requests += 1
        response(body: 'fresh', headers: {'cache-control' => 'private, max-age=60'})
      end

      hit = cache.fetch(url) do
        raise 'fresh response should not reach the origin'
      end

      expect(requests).to eq(1)
      expect(hit.url).to eq(url)
      expect(hit.from_cache).to be(true)
      expect(hit.body).to eq('fresh')
      expect(hit.response_time).to be_nil
    end

    it 'revalidates a no-cache response even while max-age is positive' do
      cache = described_class.new(storage:, strategy: :freshness)

      cache.fetch(url) do
        response(body: 'body', headers: {'cache-control' => 'no-cache, max-age=60', 'etag' => '"v1"'})
      end

      second = cache.fetch(url) do |headers|
        expect(headers['if-none-match']).to eq('"v1"')
        response(code: 304, headers: {'etag' => '"v1"'})
      end

      expect(second.from_cache).to be(true)
    end

    it 'does not retain a no-store response' do
      cache = described_class.new(storage:, strategy: :freshness)
      requests = 0

      2.times do
        result = cache.fetch(url) do
          requests += 1
          response(body: 'secret', headers: {'cache-control' => 'no-store, max-age=60'})
        end
        expect(result.from_cache).to be(false)
      end

      expect(requests).to eq(2)
      expect(storage).to be_empty
    end

    it 'keeps Vary variants distinct' do
      cache = described_class.new(storage:, strategy: :freshness)

      cache.fetch(url, {'Accept-Language' => 'en'}) do
        response(body: 'English', headers: {'cache-control' => 'max-age=60', 'vary' => 'Accept-Language'})
      end

      cache.fetch(url, {'Accept-Language' => 'es'}) do
        response(body: 'Español', headers: {'cache-control' => 'max-age=60', 'vary' => 'Accept-Language'})
      end

      english = cache.fetch(url, {'Accept-Language' => 'en'}) { raise 'expected English cache hit' }
      spanish = cache.fetch(url, {'Accept-Language' => 'es'}) { raise 'expected Spanish cache hit' }

      expect(english.body).to eq('English')
      expect(spanish.body).to eq('Español')
    end

    it 'matches sensitive Vary selectors without persisting their values' do
      cache = described_class.new(storage:, strategy: :freshness)
      request_headers = {
        'Authorization' => 'Bearer private-token',
        'Cookie' => 'session=private-cookie'
      }

      cache.fetch(url, request_headers) do
        response(
          body: 'private',
          headers: {'cache-control' => 'max-age=60', 'vary' => 'Authorization, Cookie'}
        )
      end

      hit = cache.fetch(url, request_headers) { raise 'expected cache hit' }
      persisted = storage.inspect

      expect(hit.body).to eq('private')
      expect(persisted).not_to include('private-token', 'private-cookie')
    end

    it 'stores Vary: * but never uses it as a freshness match' do
      cache = described_class.new(storage:, strategy: :freshness)

      cache.fetch(url) do
        response(body: 'first', headers: {'cache-control' => 'max-age=60', 'vary' => '*'})
      end

      expect(storage).not_to be_empty

      second = cache.fetch(url) do |headers|
        expect(headers).not_to have_key('if-none-match')
        expect(headers).not_to have_key('if-modified-since')
        response(body: 'second', headers: {'cache-control' => 'max-age=60', 'vary' => '*'})
      end

      expect(second.from_cache).to be(false)
      expect(second.body).to eq('second')
    end

    it 'uses a stored Vary: * response as a validation candidate' do
      cache = described_class.new(storage:, strategy: :freshness)

      cache.fetch(url) do
        response(body: 'body', headers: {'cache-control' => 'max-age=60', 'vary' => '*', 'etag' => '"v1"'})
      end

      second = cache.fetch(url) do |headers|
        expect(headers['if-none-match']).to eq('"v1"')
        response(code: 304, headers: {'etag' => '"v1"', 'vary' => '*'})
      end

      expect(second.from_cache).to be(true)
      expect(second.body).to eq('body')
    end

    it 'deletes the validation source when a 304 response sets a cookie' do
      cache = described_class.new(storage:, strategy: :freshness)

      cache.fetch(url, {'Accept-Language' => 'en'}) do
        response(
          body: 'English',
          headers: {'cache-control' => 'max-age=60', 'vary' => 'Accept-Language', 'etag' => '"en"'}
        )
      end

      spanish = cache.fetch(url, {'Accept-Language' => 'es'}) do |headers|
        expect(headers['if-none-match']).to eq('"en"')
        response(code: 304, headers: {'etag' => '"en"', 'set-cookie' => 'session=secret'})
      end

      expect(spanish.body).to eq('English')
      expect(storage).to be_empty

      cache.fetch(url, {'Accept-Language' => 'en'}) do |headers|
        expect(headers).not_to have_key('if-none-match')
        response(body: 'new response', headers: {'cache-control' => 'max-age=60'})
      end
    end

    it 'can validate a stored response that does not match the current Vary selectors' do
      cache = described_class.new(storage:, strategy: :freshness)

      cache.fetch(url, {'Accept-Language' => 'en'}) do
        response(
          body: 'English',
          headers: {'cache-control' => 'max-age=60', 'vary' => 'Accept-Language', 'etag' => '"en"'}
        )
      end

      spanish = cache.fetch(url, {'Accept-Language' => 'es'}) do |headers|
        expect(headers['if-none-match']).to eq('"en"')
        response(
          body: 'Español',
          headers: {'cache-control' => 'max-age=60', 'vary' => 'Accept-Language', 'etag' => '"es"'}
        )
      end

      expect(spanish.from_cache).to be(false)
      expect(spanish.body).to eq('Español')

      english = cache.fetch(url, {'Accept-Language' => 'en'}) { raise 'expected English cache hit' }
      spanish = cache.fetch(url, {'Accept-Language' => 'es'}) { raise 'expected Spanish cache hit' }

      expect(english.body).to eq('English')
      expect(spanish.body).to eq('Español')
    end

    it 'keeps the selected representation in memory while revalidation is in flight' do
      cache = described_class.new(storage:, strategy: :revalidation)
      cache.fetch(url) { response(body: 'snapshot', headers: {'etag' => '"v1"'}) }

      second = cache.fetch(url) do |headers|
        expect(headers['if-none-match']).to eq('"v1"')
        storage.clear
        response(code: 304, headers: {'etag' => '"v1"'})
      end

      expect(second.from_cache).to be(true)
      expect(second.body).to eq('snapshot')
      expect(storage).to be_empty
    end

    it 'does not let a delayed revalidation overwrite a newer response' do
      cache = described_class.new(storage:, strategy: :revalidation)
      cache.fetch(url) { response(body: 'version one', headers: {'etag' => '"v1"'}) }
      requests = Queue.new
      release_newer = Queue.new
      release_stale = Queue.new

      newer = Thread.new do
        cache.fetch(url) do |headers|
          requests << headers
          release_newer.pop
          response(body: 'version two', headers: {'etag' => '"v2"'})
        end
      end
      stale = Thread.new do
        cache.fetch(url) do |headers|
          requests << headers
          release_stale.pop
          response(code: 304, headers: {'etag' => '"v1"'})
        end
      end

      2.times { expect(requests.pop['if-none-match']).to eq('"v1"') }
      release_newer << true
      newer.value
      release_stale << true
      stale.value

      current = cache.fetch(url) do |headers|
        expect(headers['if-none-match']).to eq('"v2"')
        response(code: 304, headers: {'etag' => '"v2"'})
      end
      expect(current.body).to eq('version two')
    end

    it 'does not let a delayed 304 restore a response deleted by no-store' do
      cache = described_class.new(storage:, strategy: :revalidation)
      cache.fetch(url) { response(body: 'version one', headers: {'etag' => '"v1"'}) }
      requests = Queue.new
      release_no_store = Queue.new
      release_stale = Queue.new

      no_store = Thread.new do
        cache.fetch(url) do |headers|
          requests << headers
          release_no_store.pop
          response(body: 'uncacheable', headers: {'cache-control' => 'no-store'})
        end
      end
      stale = Thread.new do
        cache.fetch(url) do |headers|
          requests << headers
          release_stale.pop
          response(code: 304, headers: {'etag' => '"v1"'})
        end
      end

      2.times { expect(requests.pop['if-none-match']).to eq('"v1"') }
      release_no_store << true
      no_store.value
      release_stale << true
      stale.value

      expect(storage).to be_empty
      cache.fetch(url) do |headers|
        expect(headers).not_to have_key('if-none-match')
        response(body: 'version three', headers: {'etag' => '"v3"'})
      end
    end

    it 'retries an unexpected 304 once without conditional headers when no representation exists' do
      cache = described_class.new(storage:, strategy: :revalidation)
      requests = 0

      result = cache.fetch(url) do |headers|
        requests += 1
        if requests == 1
          response(code: 304)
        else
          expect(headers).not_to have_key('if-none-match')
          expect(headers).not_to have_key('if-modified-since')
          response(body: 'recovered', headers: {'etag' => '"v1"'})
        end
      end

      expect(requests).to eq(2)
      expect(result.body).to eq('recovered')
      expect(result.from_cache).to be(false)
    end

    it 'partitions stored responses by caller identity without storing the identity in the key' do
      cache = described_class.new(storage:, strategy: :freshness)

      cache.fetch(url, {}, partition: ['alice', 'secret']) do
        response(body: 'Alice', headers: {'cache-control' => 'max-age=60'})
      end

      bob = cache.fetch(url, {}, partition: ['bob', 'secret']) do
        response(body: 'Bob', headers: {'cache-control' => 'max-age=60'})
      end

      alice = cache.fetch(url, {}, partition: ['alice', 'secret']) { raise 'expected Alice cache hit' }

      expect(bob.from_cache).to be(false)
      expect(alice.body).to eq('Alice')
      expect(storage.keys.join).not_to include('alice', 'secret', 'bob')
    end

    it 'fails open when the backing store cannot be read or written' do
      broken_storage = Class.new do
        def [](_key)
          raise 'read failed'
        end

        def []=(_key, _value)
          raise 'write failed'
        end

        def delete(_key)
          raise 'delete failed'
        end
      end.new
      cache = described_class.new(storage: broken_storage, strategy: :revalidation)

      result = cache.fetch(url) { response(body: 'network', headers: {'etag' => '"v1"'}) }

      expect(result.body).to eq('network')
      expect(result.from_cache).to be(false)
    end

    it 'does not hide exceptions raised by the configured logger' do
      logger = Class.new do
        def debug
          raise 'logger failed'
        end
      end.new
      cache = described_class.new(storage:, strategy: :revalidation, logger:)

      expect { cache.fetch(url) { response(body: 'network', headers: {'etag' => '"v1"'}) } }
        .to raise_error('logger failed')
    end

    it 'rejects unsupported cache strategies' do
      expect { described_class.new(storage:, strategy: :magic) }
        .to raise_error(ArgumentError, /strategy/)
    end
  end
end