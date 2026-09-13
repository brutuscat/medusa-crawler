# frozen_string_literal: true

require 'medusa/http/cache'

module Medusa
  RSpec.describe HTTP::Cache::Store do
    let(:url) { URI('https://www.example.com/resource') }
    let(:headers) { {'accept-language' => 'en'} }
    let(:result) { HTTP::Cache::Result.new('body', {'vary' => 'accept-language'}, 1, 200, nil, false) }

    it 'stores and retrieves response variants' do
      store = described_class.new({})
      match = store.lookup(url, headers)
      entry = HTTP::Cache::Entry.from(result, headers)

      store.write(match, entry)

      expect(store.lookup(url, headers).entry).to eq(entry)
      expect(store.lookup(url, 'accept-language' => 'es').entry).to be_nil
    end
  end
end
