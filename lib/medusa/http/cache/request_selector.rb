require 'digest'

module Medusa
  class HTTP
    class Cache
      # Normalizes request selectors and fingerprints values that may contain secrets.
      module RequestSelector
        SENSITIVE_HEADERS = %w[authorization cookie].freeze

        class << self
          def normalize(headers) = headers.to_h.transform_keys { |name| name.to_s.downcase }

          def values(names, headers)
            return {}.freeze if names.include?('*')

            headers = normalize(headers)
            names.to_h { |name| [name, selector_value(name, headers[name])] }.freeze
          end

          def matches?(names, expected, headers)
            return false if names.include?('*')
            return true if names.empty?

            values(names, headers) == expected
          end

          def sensitive_fingerprint(headers)
            headers = normalize(headers)
            SENSITIVE_HEADERS.map { |name| selector_value(name, headers[name]).to_s }.join("\0")
          end

          private

          def selector_value(name, value)
            return if value.nil?

            value = value.to_s
            return value.dup.freeze unless SENSITIVE_HEADERS.include?(name)

            Digest::SHA256.hexdigest(value).freeze
          end
        end
      end
    end
  end
end
