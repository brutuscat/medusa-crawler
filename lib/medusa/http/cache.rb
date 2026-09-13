require 'uri'
require 'medusa/storage'
require 'medusa/http/cache/request_selector'
require 'medusa/http/cache/entry'
require 'medusa/http/cache/index'

module Medusa
  class HTTP
    class Cache
      STRATEGIES = %i[revalidation freshness].freeze
      CONDITIONAL_HEADERS = %w[if-none-match if-modified-since].freeze

      Result = Data.define(:body, :headers, :response_time, :code, :redirect_to, :from_cache)

      attr_reader :strategy

      def self.from(value, logger: nil)
        case value
        when nil, false
          nil
        when true
          new(logger:)
        when Hash
          new(**value, logger:)
        when self
          value
        else
          raise ArgumentError, 'http_cache must be true, false, nil, a Hash, or an HTTP::Cache'
        end
      end

      def initialize(storage: nil, strategy: :revalidation, logger: nil)
        strategy = strategy.to_sym
        unless STRATEGIES.include?(strategy)
          raise ArgumentError, "http_cache strategy must be one of: #{STRATEGIES.join(', ')}"
        end

        storage ||= Storage.Moneta(:Memory, prefix: 'medusa-http-cache')
        @index = Index.new(storage:) { |event, fields| warn_log(event, fields) }
        @strategy = strategy
        @logger = logger
      end

      # Wrap one HTTP GET. The block receives request headers and must return a Result.
      def fetch(url, request_headers = {}, partition: nil, &request)
        request_headers = RequestSelector.normalize(request_headers)
        match = @index.lookup(url, request_headers, partition:)

        if strategy == :freshness && match.entry&.fresh?
          debug('freshness', url:, result: :fresh)
          return cached_result(match.entry)
        end

        debug('freshness', url:, result: :stale) if match.entry && strategy == :freshness
        headers = request_headers.merge(match.validation_entry&.conditional_headers || {})
        response = request.call(headers)

        return resolve_not_modified(url, match, response, request_headers, &request) if response.code.to_i == 304

        resolve_response(url, match, response, request_headers)
      end

      private

      def resolve_not_modified(url, match, response, request_headers)
        source = match.validation_entry
        unless source
          warn_log('invalid_revalidation', url:, reason: :representation_missing)
          response = yield request_headers.except(*CONDITIONAL_HEADERS)
          empty_match = match.with(entry: nil, validation_entry: nil)
          return resolve_response(url, empty_match, response, request_headers)
        end

        entry = source.revalidate(response.headers, request_headers)
        if sets_cookie?(response)
          @index.delete(match, source)
          debug('bypass', url:, reason: :set_cookie)
        elsif entry.no_store?
          @index.delete(match, source)
          debug('bypass', url:, reason: :no_store)
        else
          @index.write(match, entry, replacing: source)
        end
        debug('revalidate', url:, result: :not_modified)

        cached_result(entry, response_time: response.response_time)
      end

      def resolve_response(url, match, response, request_headers)
        entry = Entry.from(response, request_headers)
        if sets_cookie?(response)
          @index.delete(match) if match.entry && response.code.to_i < 500
          debug('bypass', url:, reason: :set_cookie)
        elsif entry.cacheable?(strategy)
          @index.write(match, entry)
          event = match.entry ? 'revalidate' : 'store'
          debug(event, url:, result: (match.entry ? :modified : :stored))
        elsif response.code.to_i != 304
          @index.delete(match) if match.entry && response.code.to_i < 500
          debug('bypass', url:, reason: bypass_reason(entry))
        end

        response.with(code: response.code.to_i, from_cache: false)
      end

      def bypass_reason(entry)
        return :no_store if entry.no_store?
        return :status unless entry.status == Entry::CACHEABLE_STATUS
        return :no_validator if strategy == :revalidation

        :no_freshness_or_validator
      end

      def sets_cookie?(response)
        response.headers.to_h.any? { |name, _value| name.to_s.casecmp?('set-cookie') }
      end

      def cached_result(entry, response_time: nil)
        Result.new(
          body: entry.body.dup,
          headers: entry.response_headers,
          response_time:,
          code: entry.status,
          redirect_to: nil,
          from_cache: true
        )
      end

      def debug(event, fields = {}) = log(:debug, event, fields)

      def warn_log(event, fields = {}) = log(:warn, event, fields)

      def log(level, event, fields)
        return unless @logger&.respond_to?(level)

        message = ['medusa.http_cache', event]
        fields.each { |key, value| message << "#{key}=#{log_value(value)}" }
        @logger.public_send(level) { message.join(' ') }
      end

      def log_value(value)
        value = safe_url(value) if value.is_a?(URI::Generic)
        value.inspect
      end

      def safe_url(uri)
        uri.dup.tap do |copy|
          copy.user = nil
          copy.password = nil
        end
      rescue URI::InvalidURIError, URI::InvalidComponentError
        uri
      end
    end
  end
end
