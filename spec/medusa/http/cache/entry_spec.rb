# frozen_string_literal: true

require 'medusa/http/cache'

module Medusa
  RSpec.describe HTTP::Cache::Entry do
    let(:result) do
      HTTP::Cache::Result.new(
        body: 'body',
        headers: {'ETag' => '"v1"', 'Vary' => 'Accept-Language'},
        response_time: 1,
        code: 200,
        redirect_to: nil,
        from_cache: false
      )
    end

    it 'owns matching and validation rules for a stored response' do
      entry = described_class.from(result, {'accept-language' => 'en'})

      expect(entry).to be_validator
      expect(entry.matches?('accept-language' => 'en')).to be(true)
      expect(entry.matches?('accept-language' => 'es')).to be(false)
      expect(entry.conditional_headers).to eq('if-none-match' => '"v1"')
    end
  end
end
