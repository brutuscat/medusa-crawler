# frozen_string_literal: true

require 'medusa/http/cache/request_selector'

module Medusa
  RSpec.describe HTTP::Cache::RequestSelector do
    let(:headers) do
      {
        'Authorization' => 'Bearer private-token',
        'Cookie' => 'session=private-cookie',
        'Accept-Language' => 'en'
      }
    end

    it 'stores digests instead of sensitive Vary values' do
      values = described_class.values(%w[authorization cookie accept-language], headers)

      expect(values).to include('accept-language' => 'en')
      expect(values.values.join).not_to include('private-token', 'private-cookie')
    end

    it 'matches sensitive selectors through their digests' do
      names = %w[authorization cookie]
      values = described_class.values(names, headers)

      expect(described_class.matches?(names, values, headers)).to be(true)
      expect(described_class.matches?(names, values, headers.merge('Cookie' => 'session=other'))).to be(false)
    end

    it 'exposes no raw sensitive values in the request fingerprint' do
      fingerprint = described_class.sensitive_fingerprint(headers)

      expect(fingerprint).not_to include('private-token', 'private-cookie')
    end
  end
end
