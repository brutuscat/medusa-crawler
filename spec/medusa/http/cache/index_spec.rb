# frozen_string_literal: true

require 'medusa/http/cache'

module Medusa
  RSpec.describe HTTP::Cache::Index do
    let(:url) { URI('https://www.example.com/resource') }
    let(:headers) { {'accept-language' => 'en'} }
    let(:storage) do
      Class.new do
        def initialize
          @values = {}
        end

        def [](key) = @values[key]

        def []=(key, value)
          @values[key] = value
        end

        def delete(key) = @values.delete(key)
      end.new
    end
    let(:index) { described_class.new(storage:) }

    def entry(body: 'body', language: 'en')
      result = HTTP.const_get(:Response, false).new(
        url:,
        body:,
        headers: {'vary' => 'accept-language', 'etag' => %("#{language}")},
        response_time: 1,
        code: 200,
        redirect_to: nil,
        from_cache: false
      )
      HTTP::Cache::Entry.from(result, {'accept-language' => language})
    end

    it 'writes and retrieves a response variant through generic key-value storage' do
      match = index.lookup(url, headers)
      stored = entry

      index.write(match, stored)

      retrieved = index.lookup(url, headers).entry
      expect(retrieved).to have_attributes(
        status: stored.status,
        headers: stored.headers,
        body: stored.body,
        vary: stored.vary,
        vary_values: stored.vary_values
      )
      expect(retrieved.stored_at).to be_within(0.001).of(stored.stored_at)
    end

    it 'does not return a variant selected by different request headers' do
      match = index.lookup(url, headers)
      index.write(match, entry)

      expect(index.lookup(url, {'accept-language' => 'es'}).entry).to be_nil
    end

    it 'replaces an existing variant' do
      match = index.lookup(url, headers)
      index.write(match, entry(body: 'first'))
      existing = index.lookup(url, headers)
      same_snapshot = index.lookup(url, headers)

      expect(existing.entry).to eq(same_snapshot.entry)
      expect(existing.entry).not_to equal(same_snapshot.entry)

      index.write(existing, entry(body: 'second'))

      expect(index.lookup(url, headers).entry.body).to eq('second')
    end

    it 'does not let a stale revalidation replace a newer snapshot' do
      initial = index.lookup(url, headers)
      index.write(initial, entry(body: 'first'))
      stale_match = index.lookup(url, headers)
      current_match = index.lookup(url, headers)

      index.write(current_match, entry(body: 'second'))
      index.write(stale_match, entry(body: 'stale'), replacing: stale_match.entry)

      expect(index.lookup(url, headers).entry.body).to eq('second')
    end

    it 'deletes an existing variant' do
      match = index.lookup(url, headers)
      index.write(match, entry)
      existing = index.lookup(url, headers)

      index.delete(existing)

      expect(index.lookup(url, headers).entry).to be_nil
    end

    it 'does not let a stale revalidation delete a newer snapshot' do
      initial = index.lookup(url, headers)
      index.write(initial, entry(body: 'first'))
      stale_match = index.lookup(url, headers)
      current_match = index.lookup(url, headers)

      index.write(current_match, entry(body: 'second'))
      index.delete(stale_match, stale_match.entry)

      expect(index.lookup(url, headers).entry.body).to eq('second')
    end
  end
end
