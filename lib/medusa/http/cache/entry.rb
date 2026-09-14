require 'time'
require 'medusa/http/cache/request_selector'

module Medusa
  class HTTP
    class Cache
      # Stores an immutable response together with its freshness and validation policy.
      Entry = Data.define(:status, :headers, :body, :vary, :vary_values, :stored_at) do
        CACHEABLE_STATUS = 200
        CONNECTION_HEADERS = %w[
          connection keep-alive proxy-connection te trailer transfer-encoding upgrade
        ].freeze
        PROXY_HEADERS = %w[
          proxy-authenticate proxy-authentication-info proxy-authorization
        ].freeze
        # Medusa does not replay cookies from cached responses. Keeping Set-Cookie
        # out of persistent stores also avoids retaining credentials unnecessarily.
        POLICY_HEADER_EXCLUSIONS = %w[set-cookie].freeze
        STORED_HEADER_EXCLUSIONS = (CONNECTION_HEADERS + PROXY_HEADERS + POLICY_HEADER_EXCLUSIONS).freeze

        # RFC 9111: cache-directive = token [ "=" ( token / quoted-string ) ]
        CACHE_DIRECTIVE = /
          (?:\A|,)\s*
          (?<name>[!#$%&'*+\-.^_`|~0-9A-Za-z]+)
          (?:\s*=\s*(?:
            "(?<quoted>(?:\\.|[^"])*)"
            |
            (?<token>[!#$%&'*+\-.^_`|~0-9A-Za-z]+)
          ))?
        /x

        class << self
          def from(result, request_headers)
            headers = stored_headers(result.headers)
            vary = vary_headers(headers)

            new(
              status: result.code.to_i,
              headers:,
              body: immutable_string(result.body),
              vary:,
              vary_values: vary_values(vary, request_headers),
              stored_at: Time.now
            )
          end

          def load(value)
            return unless value.is_a?(Hash)
            return unless value['body'].is_a?(String) && value['headers'].is_a?(Hash) && value['status']

            timestamp = Float(value['stored_at'], exception: false)
            return unless timestamp

            headers = stored_headers(value['headers'])
            vary = vary_headers(headers)

            new(
              status: value['status'].to_i,
              headers:,
              body: immutable_string(value['body']),
              vary:,
              vary_values: persisted_vary_values(vary, value['vary_values']),
              stored_at: Time.at(timestamp)
            )
          end

          def normalize_headers(headers) = headers.to_h.transform_keys { |name| name.to_s.downcase }

          def stored_headers(headers)
            normalized = normalize_headers(headers)
            exclusions = STORED_HEADER_EXCLUSIONS + connection_options(normalized) + no_cache_fields(normalized)
            immutable_headers(normalized.except(*exclusions))
          end

          def vary_headers(headers)
            headers.fetch('vary', '').split(',').filter_map do |name|
              normalized = name.strip.downcase
              immutable_string(normalized) unless normalized.empty?
            end.uniq.freeze
          end

          def vary_values(vary, request_headers)
            RequestSelector.values(vary, request_headers)
          end

          def cache_directives(value)
            return {} if value.nil? || value.empty?

            value.scan(CACHE_DIRECTIVE).to_h do |name, quoted, token|
              raw_value = quoted || token
              [name.downcase, quoted ? unescape_quoted(raw_value) : raw_value]
            end
          end

          private

          def connection_options(headers)
            headers.fetch('connection', '').split(',').filter_map do |name|
              normalized = name.strip.downcase
              normalized unless normalized.empty?
            end
          end

          def no_cache_fields(headers)
            value = cache_directives(headers['cache-control'])['no-cache']
            return [] unless value.is_a?(String)

            value.split(',').filter_map do |name|
              normalized = name.strip.downcase
              normalized unless normalized.empty?
            end
          end

          def persisted_vary_values(vary, values)
            values = normalize_headers(values || {})
            vary.to_h { |name| [name, immutable_optional_string(values[name])] }.freeze
          end

          def immutable_headers(headers)
            headers.to_h do |name, value|
              [immutable_string(name), immutable_string(value)]
            end.freeze
          end

          # String#to_s returns itself for a String, so copy before freezing.
          def immutable_string(value) = value.to_s.dup.freeze

          def immutable_optional_string(value)
            immutable_string(value) unless value.nil?
          end

          def unescape_quoted(value) = value.gsub(/\\(.)/, '\\1')
        end # class << self

        def to_h
          {
            'status' => status,
            'headers' => mutable_headers,
            'body' => body.dup,
            'vary' => vary.map(&:dup),
            'vary_values' => vary_values.transform_values { |value| value&.dup },
            'stored_at' => stored_at.to_f
          }
        end

        def response_headers = mutable_headers

        def matches?(request_headers)
          RequestSelector.matches?(vary, vary_values, request_headers)
        end

        def same_variant?(other) = other && vary == other.vary && vary_values == other.vary_values

        def validator? = headers.key?('etag') || headers.key?('last-modified')

        def conditional_headers
          {}.tap do |result|
            result['if-none-match'] = headers['etag'] if headers['etag']
            result['if-modified-since'] = headers['last-modified'] if headers['last-modified']
          end
        end

        def fresh?
          return false if vary_star? || directives.key?('no-cache')

          ttl&.positive?
        end

        def cacheable?(strategy)
          return false unless status == CACHEABLE_STATUS
          return false if no_store?
          return validator? if strategy == :revalidation

          validator? || !freshness_lifetime.nil?
        end

        def no_store? = directives.key?('no-store')

        def revalidate(received_headers, request_headers)
          incoming = self.class.normalize_headers(received_headers).except('content-length')
          stored_headers = self.class.stored_headers(headers.merge(incoming))
          new_vary = self.class.vary_headers(stored_headers)

          with(
            headers: stored_headers,
            vary: new_vary,
            vary_values: self.class.vary_values(new_vary, request_headers),
            stored_at: Time.now
          )
        end

        private

        def mutable_headers = headers.transform_values(&:dup)

        def vary_star? = vary.include?('*')

        def ttl
          lifetime = freshness_lifetime
          lifetime - current_age if lifetime
        end

        def freshness_lifetime
          max_age = directives['max-age']
          return integer_seconds(max_age) unless max_age.nil?

          expires = http_time(headers['expires'])
          return unless expires

          date = http_time(headers['date']) || stored_at
          [expires - date, 0].max
        end

        def current_age
          date = http_time(headers['date']) || stored_at
          apparent_age = [stored_at - date, 0].max
          age_value = integer_seconds(headers['age']) || 0
          [apparent_age, age_value].max + [Time.now - stored_at, 0].max
        end

        def integer_seconds(value)
          value.to_i if value.to_s.match?(/\A\d+\z/)
        end

        def http_time(value)
          Time.httpdate(value.to_s)
        rescue ArgumentError
          nil
        end

        def directives = self.class.cache_directives(headers['cache-control'])
      end
    end
  end
end
