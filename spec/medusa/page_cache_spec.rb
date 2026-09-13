# frozen_string_literal: true

require 'medusa/page'

module Medusa
  RSpec.describe Page do
    let(:url) { URI('https://www.example.com/resource') }

    it 'is not from cache by default' do
      expect(described_class.new(url).from_cache?).to be(false)
    end

    it 'preserves cache origin through Marshal-backed storage' do
      page = described_class.new(url, body: 'cached body', from_cache: true)

      restored = Marshal.load(Marshal.dump(page))

      expect(restored.from_cache?).to be(true)
      expect(restored.body).to eq('cached body')
    end

    it 'preserves cache origin through hash serialization' do
      page = described_class.new(url, body: 'cached body', from_cache: true)

      restored = described_class.from_hash(page.to_hash)

      expect(restored.from_cache?).to be(true)
    end
  end
end
