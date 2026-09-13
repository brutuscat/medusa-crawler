require 'time'

module Medusa
  class HTTP
    class Cache
      Entry = Data.define(:status, :headers, :body, :vary, :vary_values, :stored_at) do
        CACHEABLE_STATUS = 200
        REVALIDATION_HEADERS = %w[date age cache-control expires etag last-modified vary content-location].freeze
        STORED_HEADER_EXCLUSIONS = %w[
          connection keep-alive proxy-authenticate proxy-authorization set-cookie
          te trailer transfer-encoding upgrade
        ].freeze

        class << self
          def from(result, request_headers)
            headers = stored_headers(result.headers)
            vary = vary_headers(headers)

            new(
              status: result.code.to_i,
              headers:,
              body: result.body.to_s.dup,
              vary:,
              vary_values: vary_values(vary, request_headers),
              stored_at: Time.now.to_f
            )
          end

          def load(value)
            return unless value.is_a?(Hash)
            return unless value['body'].is_a?(String) && value['headers'].is_a?(Hash) && value['status']

            new(
              status: value['status'].to_i,
              headers: value['headers'].dup,
              body: value['body'].dup,
              vary: Array(value['vary']).dup,
              vary_values: (value['vary_values'] || {}).dup,
              stored_at: value['stored_at'].to_f
            )
          end

          def normalize_headers(headers) = headers.to_h.transform_keys { |name| name.to_s.downcase }

          def stored_headers(headers) = normalize_headers(headers).except(*STORED_HEADER_EXCLUSIONS)

          def vary_headers(headers)
            headers.fetch('vary', '').split(',').filter_map do |name|
              normalized = name.strip.downcase
              normalized unless normalized.empty?
            end.uniq
          end

          def vary_values(vary, request_headers)
            return {} if vary.include?('*')

            vary.to_h { |name| [name, request_headers[name]] }
          end
        end

        def to_h
          {
            'status' => status,
            'headers' => headers.dup,
            'body' => body.dup,
            'vary' => vary.dup,
            'vary_values' => vary_values.dup,
            'stored_at' => stored_at
          }
        end

        def matches?(request_headers)
          !vary_star? && vary.all? { |name| vary_values[name] == request_headers[name] }
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
          incoming = self.class.normalize_headers(received_headers)
          merged_headers = headers.merge(incoming.slice(*REVALIDATION_HEADERS))
          stored_headers = merged_headers.except(*STORED_HEADER_EXCLUSIONS)
          new_vary = self.class.vary_headers(stored_headers)

          with(
            headers: stored_headers,
            vary: new_vary,
            vary_values: self.class.vary_values(new_vary, request_headers),
            stored_at: Time.now.to_f
          )
        end

        private

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

          date = http_time(headers['date']) || Time.at(stored_at)
          [expires - date, 0].max
        end

        def current_age
          date = http_time(headers['date'])&.to_f || stored_at
          apparent_age = [stored_at - date, 0].max
          age_value = integer_seconds(headers['age']) || 0
          [apparent_age, age_value].max + [Time.now.to_f - stored_at, 0].max
        end

        def integer_seconds(value) = value.to_i if value.to_s.match?(/\A\d+\z/)

        def http_time(value)
          Time.httpdate(value.to_s)
        rescue ArgumentError
          nil
        end

        def directives
          value = headers['cache-control']
          return {} if value.nil? || value.empty?

          value.scan(/(?:\A|,)\s*([!#$%&'*+\-.^_`|~0-9A-Za-z]+)(?:\s*=\s*(?:"((?:\\.|[^"])*)"|([^,\s]*)))?/)
            .to_h do |name, quoted, token|
              raw_value = quoted || token
              [name.downcase, raw_value.nil? ? true : raw_value.gsub(/\\(.)/, '\\1')]
            end
        end
      end
    end
  end
end
