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
      result = HTTP::Cache::Result.new(
        body,
        {'vary' => 'accept-language', 'etag' => %("#{language}")},
        1,
        200,
        nil,
        false
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

      index.write(existing, entry(body: 'second'))

      expect(index.lookup(url, headers).entry.body).to eq('second')
    end

    it 'deletes an existing variant' do
      match = index.lookup(url, headers)
      index.write(match, entry)
      existing = index.lookup(url, headers)

      index.delete(existing)

      expect(index.lookup(url, headers).entry).to be_nil
    end
  end
end
