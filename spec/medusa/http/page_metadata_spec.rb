# frozen_string_literal: true

require 'medusa/http/cache'
require 'medusa/page'

module Medusa
  RSpec.describe HTTP::Cache::PageMetadata do
    let(:page) do
      Page.new(
        URI('https://www.example.com/resource'),
        body: 'cached body',
        headers: {'content-type' => 'text/plain'},
        code: 200
      )
    end

    it 'adds from_cache? only when the cache decorates a Page' do
      expect(page).not_to respond_to(:from_cache?)

      HTTP::Cache.new(store: {}).decorate(page, from_cache: true)

      expect(page.from_cache?).to be(true)
    end

    it 'preserves from_cache? through Marshal-backed page storage' do
      HTTP::Cache.new(store: {}).decorate(page, from_cache: true)

      restored = Marshal.load(Marshal.dump(page))

      expect(restored).to respond_to(:from_cache?)
      expect(restored.from_cache?).to be(true)
      expect(restored.body).to eq('cached body')
    end

    it 'preserves from_cache? through Page hash serialization' do
      HTTP::Cache.new(store: {}).decorate(page, from_cache: false)

      restored = Page.from_hash(page.to_hash)

      expect(restored).to respond_to(:from_cache?)
      expect(restored.from_cache?).to be(false)
    end
  end
end
