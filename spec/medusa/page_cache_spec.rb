# frozen_string_literal: true

require 'medusa/page'
require 'yaml'

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

    it 'loads the legacy Marshal schema without cache metadata' do
      fixture = legacy_fixture.fetch('marshal')
      legacy_record = [
        URI(fixture['url']),
        fixture['headers'],
        OpenStruct.new(fixture['data']),
        fixture['body'],
        fixture['links'].map { |link| URI(link) },
        fixture['code'],
        fixture['visited'],
        fixture['depth'],
        fixture['referer'],
        fixture['redirect_to'],
        fixture['response_time'],
        fixture['fetched']
      ]
      restored = described_class.allocate

      restored.marshal_load(legacy_record)

      expect_legacy_page(restored)
    end

    it 'loads the legacy hash schema without cache metadata' do
      fixture = legacy_fixture.fetch('hash')
      legacy_record = fixture.merge(
        'headers' => Marshal.dump(fixture['headers']),
        'data' => Marshal.dump(OpenStruct.new(fixture['data']))
      )

      restored = described_class.from_hash(legacy_record)

      expect_legacy_page(restored)
    end

    def legacy_fixture
      @legacy_fixture ||= YAML.safe_load_file(
        File.expand_path('../fixtures/page/legacy.yml', __dir__)
      )
    end

    def expect_legacy_page(page)
      expect(page).to have_attributes(
        url: URI('https://www.example.com/legacy'),
        body: 'legacy body',
        code: 200,
        depth: 2,
        response_time: 15
      )
      expect(page.data.category).to eq('archive')
      expect(page.headers).to eq('content-type' => 'text/plain')
      expect(page.links).to eq([URI('https://www.example.com/next')])
      expect(page.referer).to eq('https://www.example.com/')
      expect(page.redirect_to).to be_nil
      expect(page.instance_variable_get(:@visited)).to be(true)
      expect(page).to be_fetched
      expect(page.from_cache?).to be(false)
    end
  end
end
