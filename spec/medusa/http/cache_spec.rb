# frozen_string_literal: true

require 'medusa/http/cache'

module Medusa
  RSpec.describe HTTP::Cache do
    let(:url) { URI('https://www.example.com/resource') }
    let(:store) { {} }
    let(:result_class) { HTTP::Cache::Result }

    def response(body: '', headers: {}, code: 200, response_time: 1)
      result_class.new(body, headers, response_time, code, nil, false)
    end

    it 'revalidates an ETag and reuses the stored representation after 304' do
      cache = described_class.new(store: store, strategy: :revalidation)

      first = cache.fetch(url) do |headers|
        expect(headers).not_to have_key('if-none-match')
        response(body: 'version one', headers: {'etag' => '"v1"'})
      end

      second = cache.fetch(url) do |headers|
        expect(headers['if-none-match']).to eq('"v1"')
        response(code: 304, headers: {'etag' => '"v1"'})
      end

      expect(first.from_cache).to be(false)
      expect(second.from_cache).to be(true)
      expect(second.code).to eq(200)
      expect(second.body).to eq('version one')
    end

    it 'sends Last-Modified when ETag is unavailable' do
      cache = described_class.new(store: store, strategy: :revalidation)
      modified = 'Wed, 09 Sep 2026 14:20:00 GMT'

      cache.fetch(url) { response(body: 'body', headers: {'last-modified' => modified}) }

      cache.fetch(url) do |headers|
        expect(headers['if-modified-since']).to eq(modified)
        response(code: 304, headers: {'last-modified' => modified})
      end
    end

    it 'sends both validators when both are available' do
      cache = described_class.new(store: store, strategy: :revalidation)
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
      cache = described_class.new(store: store, strategy: :freshness)
      requests = 0

      cache.fetch(url) do
        requests += 1
        response(body: 'fresh', headers: {'cache-control' => 'private, max-age=60'})
      end

      hit = cache.fetch(url) do
        raise 'fresh response should not reach the origin'
      end

      expect(requests).to eq(1)
      expect(hit.from_cache).to be(true)
      expect(hit.body).to eq('fresh')
      expect(hit.response_time).to be_nil
    end

    it 'revalidates a no-cache response even while max-age is positive' do
      cache = described_class.new(store: store, strategy: :freshness)

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
      cache = described_class.new(store: store, strategy: :freshness)
      requests = 0

      2.times do
        result = cache.fetch(url) do
          requests += 1
          response(body: 'secret', headers: {'cache-control' => 'no-store, max-age=60'})
        end
        expect(result.from_cache).to be(false)
      end

      expect(requests).to eq(2)
      expect(store).to be_empty
    end

    it 'keeps Vary variants distinct' do
      cache = described_class.new(store: store, strategy: :freshness)

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

    it 'never treats Vary: * as a freshness hit but can revalidate it' do
      cache = described_class.new(store: store, strategy: :freshness)

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

    it 'keeps the selected representation in memory while revalidation is in flight' do
      cache = described_class.new(store: store, strategy: :revalidation)
      cache.fetch(url) { response(body: 'snapshot', headers: {'etag' => '"v1"'}) }

      second = cache.fetch(url) do |headers|
        expect(headers['if-none-match']).to eq('"v1"')
        store.clear
        response(code: 304, headers: {'etag' => '"v1"'})
      end

      expect(second.from_cache).to be(true)
      expect(second.body).to eq('snapshot')
      expect(store).not_to be_empty
    end

    it 'retries an unexpected 304 once without conditional headers when no representation exists' do
      cache = described_class.new(store: store, strategy: :revalidation)
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
      cache = described_class.new(store: store, strategy: :freshness)

      cache.fetch(url, {}, partition: ['alice', 'secret']) do
        response(body: 'Alice', headers: {'cache-control' => 'max-age=60'})
      end

      bob = cache.fetch(url, {}, partition: ['bob', 'secret']) do
        response(body: 'Bob', headers: {'cache-control' => 'max-age=60'})
      end

      alice = cache.fetch(url, {}, partition: ['alice', 'secret']) { raise 'expected Alice cache hit' }

      expect(bob.from_cache).to be(false)
      expect(alice.body).to eq('Alice')
      expect(store.keys.join).not_to include('alice', 'secret', 'bob')
    end

    it 'fails open when the backing store cannot be read or written' do
      broken_store = Class.new do
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
      cache = described_class.new(store: broken_store, strategy: :revalidation)

      result = cache.fetch(url) { response(body: 'network', headers: {'etag' => '"v1"'}) }

      expect(result.body).to eq('network')
      expect(result.from_cache).to be(false)
    end

    it 'rejects unsupported cache strategies' do
      expect { described_class.new(store: store, strategy: :magic) }
        .to raise_error(ArgumentError, /strategy/)
    end
  end
end
