# frozen_string_literal: true

require 'medusa/http/cache'

module Medusa
  RSpec.describe HTTP::Cache::Entry do
    let(:request_headers) { {'accept-language' => 'en'} }

    def response(body: 'body', headers: {}, code: 200)
      HTTP::Cache::Result.new(body, headers, 1, code, nil, false)
    end

    it 'recognizes a stored validator' do
      entry = described_class.from(response(headers: {'ETag' => '"v1"'}), {})

      expect(entry).to be_validator
    end

    it 'builds conditional request headers from stored validators' do
      modified = 'Wed, 09 Sep 2026 14:20:00 GMT'
      entry = described_class.from(
        response(headers: {'ETag' => '"v1"', 'Last-Modified' => modified}),
        {}
      )

      expect(entry.conditional_headers).to eq(
        'if-none-match' => '"v1"',
        'if-modified-since' => modified
      )
    end

    it 'matches the request headers selected by Vary' do
      entry = described_class.from(response(headers: {'Vary' => 'Accept-Language'}), request_headers)

      expect(entry.matches?('Accept-Language' => 'en')).to be(true)
    end

    it 'rejects different request headers selected by Vary' do
      entry = described_class.from(response(headers: {'Vary' => 'Accept-Language'}), request_headers)

      expect(entry.matches?('Accept-Language' => 'es')).to be(false)
    end

    it 'matches without additional selectors when Vary is absent' do
      entry = described_class.from(response, request_headers)

      expect(entry.matches?('Accept-Language' => 'es')).to be(true)
    end

    it 'owns a frozen snapshot of the response body' do
      body = +'body'
      entry = described_class.from(response(body:), {})

      body << ' changed'

      expect(entry.body).to eq('body')
      expect(entry.body).to be_frozen
    end

    it 'stores time as a Time and serializes it as an epoch number' do
      entry = described_class.from(response, {})

      expect(entry.stored_at).to be_a(Time)
      expect(entry.to_h['stored_at']).to be_a(Float)
    end

    it 'removes connection-specific and proxy-specific response headers' do
      entry = described_class.from(
        response(
          headers: {
            'Connection' => 'Keep-Alive, X-Connection-Secret',
            'Keep-Alive' => 'timeout=5',
            'X-Connection-Secret' => 'secret',
            'Proxy-Authentication-Info' => 'secret',
            'X-End-To-End' => 'kept'
          }
        ),
        {}
      )

      expect(entry.headers).to eq('x-end-to-end' => 'kept')
    end

    it 'removes fields named by a qualified no-cache directive' do
      entry = described_class.from(
        response(headers: {'Cache-Control' => 'no-cache="X-Secret"', 'X-Secret' => 'secret'}),
        {}
      )

      expect(entry.headers).not_to have_key('x-secret')
    end

    it 'parses flag, token, and escaped quoted Cache-Control directives' do
      directives = described_class.cache_directives('public, max-age=60, extension="a\"b"')

      expect(directives).to eq('public' => nil, 'max-age' => '60', 'extension' => 'a"b')
    end

    it 'updates extension headers after successful validation but not Content-Length' do
      entry = described_class.from(
        response(headers: {'ETag' => '"v1"', 'Content-Length' => '4', 'X-Revision' => 'one'}),
        {}
      )

      revalidated = entry.revalidate(
        {'ETag' => '"v2"', 'Content-Length' => '999', 'X-Revision' => 'two'},
        {}
      )

      expect(revalidated.headers).to include('etag' => '"v2"', 'x-revision' => 'two')
      expect(revalidated.headers['content-length']).to eq('4')
    end
  end
end
