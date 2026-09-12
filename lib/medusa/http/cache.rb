require 'digest'
require 'time'
require 'uri'
require 'medusa/storage'
require 'medusa/http/cache/page_metadata'

module Medusa
  class HTTP
    class Cache
      VERSION = 1
      STRATEGIES = %i[revalidation freshness].freeze
      CACHEABLE_STATUS = 200
      SENSITIVE_HEADERS = %w[authorization cookie].freeze
      REVALIDATION_HEADERS = %w[date age cache-control expires etag last-modified vary content-location].freeze
      STORED_HEADER_EXCLUSIONS = %w[
        connection keep-alive proxy-authenticate proxy-authorization set-cookie
        te trailer transfer-encoding upgrade
      ].freeze

      Result = Data.define(:body, :headers, :response_time, :code, :redirect_to, :from_cache)
      Context = Data.define(:url, :key, :entry, :validation_entry)

      class << self
        def build(option, logger: nil)
          return nil unless option
          return option if option.is_a?(self)

          config = option == true ? {} : option
          unless config.respond_to?(:to_hash)
            raise ArgumentError, 'http_cache must be true, false, or a Hash'
          end

          config = config.to_hash
          unknown = config.keys - %i[store strategy]
          raise ArgumentError, "unknown http_cache option(s): #{unknown.join(', ')}" unless unknown.empty?

          store = config[:store] || Storage.Moneta(:Memory, prefix: 'medusa-http-cache')
          new(store: store, strategy: config.fetch(:strategy, :revalidation), logger: logger)
        end
      end

      attr_reader :strategy

      def initialize(store:, strategy: :revalidation, logger: nil)
        strategy = strategy.to_sym
        unless STRATEGIES.include?(strategy)
          raise ArgumentError, "http_cache strategy must be one of: #{STRATEGIES.join(', ')}"
        end

        %i[[] []= delete].each do |method|
          raise ArgumentError, "http_cache store must respond to ##{method}" unless store.respond_to?(method)
        end

        @store = store
        @strategy = strategy
        @logger = logger
        @mutex = Mutex.new
      end

      # Wrap one HTTP GET. The block receives request headers and must return a Result.
      def fetch(url, request_headers = {}, partition: nil, &request)
        normalized_headers = normalize_headers(request_headers)
        context = lookup(url, normalized_headers, partition)

        if serve_fresh?(context)
          entry = context.entry
          debug('freshness', url: url, result: :fresh)
          return result_from_entry(entry, from_cache: true)
        end

        debug('freshness', url: url, result: :stale) if context.entry && strategy == :freshness
        headers = normalized_headers.merge(conditional_headers(context.validation_entry))
        network = request.call(headers)

        if network.code.to_i == 304
          return resolve_not_modified(context, network, normalized_headers, &request)
        end

        resolve_network_response(context, network, normalized_headers)
      end

      def decorate(page, from_cache:)
        page.extend(PageMetadata) unless page.is_a?(PageMetadata)
        page.instance_variable_set(:@http_cache_from_cache, !!from_cache)
        page
      end

      private

      def lookup(url, request_headers, partition)
        key = store_key(url, request_headers, partition)
        bucket = read_bucket(key, url)
        unless bucket
          debug('lookup', url: url, result: :absent)
          return Context.new(url: url, key: key, entry: nil, validation_entry: nil)
        end

        variants = bucket['variants']
        entry = variants.find { |candidate| entry_matches?(candidate, request_headers) }
        validation_entry = if entry && validator?(entry)
          entry
        elsif entry
          nil
        else
          validation_candidate(variants)
        end

        if entry
          debug('lookup', url: url, result: :matched)
        elsif validation_entry
          debug('lookup', url: url, result: :validation_candidate)
        else
          debug('lookup', url: url, result: :variant_mismatch)
        end

        Context.new(
          url: url,
          key: key,
          entry: snapshot(entry),
          validation_entry: snapshot(validation_entry)
        )
      end

      def validation_candidate(entries)
        entries
          .select { |entry| usable_entry?(entry) && validator?(entry) }
          .max_by { |entry| entry['stored_at'].to_f }
      end

      def validator?(entry)
        headers = entry['headers'] || {}
        headers.key?('etag') || headers.key?('last-modified')
      end

      def serve_fresh?(context)
        return false unless strategy == :freshness && context.entry
        return false if vary_star?(context.entry)
        return false if cache_control(context.entry['headers']).key?('no-cache')

        ttl(context.entry)&.positive?
      end

      def resolve_not_modified(context, network, request_headers)
        source = context.validation_entry
        unless usable_entry?(source)
          warn_log('invalid_revalidation', url: context.url, reason: :representation_missing)
          unconditional = yield strip_conditional_headers(request_headers)
          return resolve_network_response(context_without_entry(context), unconditional, request_headers)
        end

        headers = merge_revalidation_headers(source['headers'], network.headers)
        vary = vary_headers(headers)
        entry = source.merge(
          'headers' => headers,
          'vary' => vary,
          'vary_values' => vary_values(vary, request_headers),
          'stored_at' => Time.now.to_f
        )

        if cache_control(headers).key?('no-store')
          remove_entry(context, source)
          debug('bypass', url: context.url, reason: :no_store)
        else
          write_entry(context, entry, replacing: source)
        end
        debug('revalidate', url: context.url, result: :not_modified)

        Result.new(
          entry['body'],
          entry['headers'].dup,
          network.response_time,
          entry['status'].to_i,
          nil,
          true
        )
      end

      def resolve_network_response(context, network, request_headers)
        if cacheable?(network)
          entry = build_entry(network, request_headers)
          write_entry(context, entry)
          debug(context.entry ? 'revalidate' : 'store', url: context.url, result: (context.entry ? :modified : :stored))
        elsif network.code.to_i != 304
          remove_entry(context) if context.entry && invalidate_old_entry?(network)
          debug('bypass', url: context.url, reason: bypass_reason(network))
        end

        Result.new(
          network.body,
          network.headers,
          network.response_time,
          network.code.to_i,
          network.redirect_to,
          false
        )
      end

      def context_without_entry(context)
        Context.new(url: context.url, key: context.key, entry: nil, validation_entry: nil)
      end

      def cacheable?(result)
        return false unless result.code.to_i == CACHEABLE_STATUS

        headers = normalize_headers(result.headers)
        directives = cache_control(headers)
        return false if directives.key?('no-store')

        has_validator = headers.key?('etag') || headers.key?('last-modified')
        return has_validator if strategy == :revalidation

        has_validator || !freshness_lifetime(headers, Time.now.to_f).nil?
      end

      def bypass_reason(result)
        headers = normalize_headers(result.headers)
        return :no_store if cache_control(headers).key?('no-store')
        return :status unless result.code.to_i == CACHEABLE_STATUS
        return :no_validator if strategy == :revalidation

        :no_freshness_or_validator
      end

      def invalidate_old_entry?(network)
        code = network.code.to_i
        code < 500
      end

      def build_entry(result, request_headers)
        headers = stored_headers(result.headers)
        vary = vary_headers(headers)

        {
          'status' => result.code.to_i,
          'headers' => headers,
          'body' => result.body.to_s.dup,
          'vary' => vary,
          'vary_values' => vary_values(vary, request_headers),
          'stored_at' => Time.now.to_f
        }
      end

      def write_entry(context, entry, replacing: context.entry)
        @mutex.synchronize do
          bucket = read_bucket_unlocked(context.key, context.url) || empty_bucket
          variants = bucket['variants'].map { |variant| snapshot(variant) }

          previous_index = replacing && variants.index { |variant| same_variant?(variant, replacing) }
          if previous_index
            variants[previous_index] = entry
          else
            variants.reject! { |variant| same_variant?(variant, entry) }
            variants << entry
          end

          write_store(context.key, {'version' => VERSION, 'variants' => variants}, context.url)
        end
      end

      def remove_entry(context, entry = context.entry)
        return unless entry

        @mutex.synchronize do
          bucket = read_bucket_unlocked(context.key, context.url)
          return unless bucket

          variants = bucket['variants'].map { |variant| snapshot(variant) }
          variants.reject! { |variant| same_variant?(variant, entry) }

          if variants.empty?
            delete_store(context.key, context.url)
          else
            write_store(context.key, {'version' => VERSION, 'variants' => variants}, context.url)
          end
        end
      end

      def read_bucket(key, url)
        @mutex.synchronize { read_bucket_unlocked(key, url) }
      end

      def read_bucket_unlocked(key, url)
        value = @store[key]
        return nil if value.nil?
        return value if valid_bucket?(value)

        warn_log('corrupt_entry', url: url)
        delete_store(key, url)
        nil
      rescue StandardError => error
        warn_log('storage_error', url: url, operation: :read, error: error.class.name)
        nil
      end

      def write_store(key, value, url)
        @store[key] = value
      rescue StandardError => error
        warn_log('storage_error', url: url, operation: :write, error: error.class.name)
      end

      def delete_store(key, url)
        @store.delete(key)
      rescue StandardError => error
        warn_log('storage_error', url: url, operation: :delete, error: error.class.name)
      end

      def valid_bucket?(value)
        value.is_a?(Hash) && value['version'] == VERSION && value['variants'].is_a?(Array)
      end

      def empty_bucket
        {'version' => VERSION, 'variants' => []}
      end

      def usable_entry?(entry)
        entry.is_a?(Hash) && entry['body'].is_a?(String) && entry['headers'].is_a?(Hash) && entry['status']
      end

      def snapshot(entry)
        return nil unless entry

        {
          'status' => entry['status'],
          'headers' => (entry['headers'] || {}).dup,
          'body' => entry['body']&.dup,
          'vary' => Array(entry['vary']).dup,
          'vary_values' => (entry['vary_values'] || {}).dup,
          'stored_at' => entry['stored_at']
        }
      end

      def entry_matches?(entry, request_headers)
        return false unless usable_entry?(entry)
        return false if vary_star?(entry)

        vary = Array(entry['vary'])
        expected = entry['vary_values'] || {}
        vary.all? { |name| expected[name] == request_headers[name] }
      end

      def same_variant?(left, right)
        return false unless left && right

        Array(left['vary']) == Array(right['vary']) &&
          (left['vary_values'] || {}) == (right['vary_values'] || {})
      end

      def vary_star?(entry)
        Array(entry['vary']).include?('*')
      end

      def vary_headers(headers)
        value = headers['vary']
        return [] if value.nil? || value.empty?

        value.split(',').map { |name| name.strip.downcase }.reject(&:empty?).uniq
      end

      def vary_values(vary, request_headers)
        return {} if vary.include?('*')

        vary.to_h { |name| [name, request_headers[name]] }
      end

      def conditional_headers(entry)
        return {} unless usable_entry?(entry)

        headers = entry['headers']
        result = {}
        result['if-none-match'] = headers['etag'] if headers['etag']
        result['if-modified-since'] = headers['last-modified'] if headers['last-modified']
        result
      end

      def strip_conditional_headers(headers)
        headers.reject { |name, _| %w[if-none-match if-modified-since].include?(name) }
      end

      def merge_revalidation_headers(stored, received)
        result = normalize_headers(stored)
        incoming = normalize_headers(received)
        REVALIDATION_HEADERS.each do |name|
          result[name] = incoming[name] if incoming.key?(name)
        end
        stored_headers(result)
      end

      def stored_headers(headers)
        normalize_headers(headers).reject { |name, _| STORED_HEADER_EXCLUSIONS.include?(name) }
      end

      def normalize_headers(headers)
        headers.each_with_object({}) do |(name, value), normalized|
          normalized[name.to_s.downcase] = value
        end
      end

      def store_key(url, request_headers, partition)
        sensitive = SENSITIVE_HEADERS.map { |name| request_headers[name].to_s }.join("\0")
        raw = "#{url}\0#{sensitive}\0#{partition.inspect}"
        "medusa:http-cache:v#{VERSION}:#{Digest::SHA256.hexdigest(raw)}"
      end

      def ttl(entry)
        lifetime = freshness_lifetime(entry['headers'], entry['stored_at'])
        return nil unless lifetime

        lifetime - current_age(entry)
      end

      def freshness_lifetime(headers, stored_at)
        headers = normalize_headers(headers)
        directives = cache_control(headers)
        max_age = directives['max-age']
        return integer_seconds(max_age) unless max_age.nil?

        expires = http_time(headers['expires'])
        return nil unless expires

        date = http_time(headers['date']) || Time.at(stored_at)
        [expires - date, 0].max
      end

      def current_age(entry)
        headers = normalize_headers(entry['headers'])
        stored_at = entry['stored_at'].to_f
        date = http_time(headers['date'])&.to_f || stored_at
        apparent_age = [stored_at - date, 0].max
        age_value = integer_seconds(headers['age']) || 0
        initial_age = [apparent_age, age_value].max
        initial_age + [Time.now.to_f - stored_at, 0].max
      end

      def integer_seconds(value)
        return nil unless value.to_s.match?(/\A\d+\z/)

        value.to_i
      end

      def http_time(value)
        Time.httpdate(value.to_s)
      rescue ArgumentError
        nil
      end

      def cache_control(headers)
        parse_directives(normalize_headers(headers)['cache-control'])
      end

      def parse_directives(value)
        return {} if value.nil? || value.empty?

        value.scan(/(?:\A|,)\s*([!#$%&'*+\-.^_`|~0-9A-Za-z]+)(?:\s*=\s*(?:"((?:\\.|[^"])*)"|([^,\s]*)))?/).each_with_object({}) do |match, result|
          name, quoted, token = match
          has_value = !quoted.nil? || !token.nil?
          raw_value = quoted || token
          result[name.downcase] = has_value ? raw_value.to_s.gsub(/\\(.)/, '\\1') : true
        end
      end

      def result_from_entry(entry, from_cache:)
        Result.new(entry['body'].dup, entry['headers'].dup, nil, entry['status'].to_i, nil, from_cache)
      end

      def debug(event, fields = {})
        log(:debug, event, fields)
      end

      def warn_log(event, fields = {})
        log(:warn, event, fields)
      end

      def log(level, event, fields)
        return unless @logger&.respond_to?(level)

        message = ['medusa.http_cache', event]
        fields.each { |key, value| message << "#{key}=#{log_value(value)}" }
        @logger.public_send(level) { message.join(' ') }
      rescue StandardError
        nil
      end

      def log_value(value)
        value = safe_url(value) if value.is_a?(URI::Generic)
        value.inspect
      end

      def safe_url(uri)
        copy = uri.dup
        copy.user = nil
        copy.password = nil
        copy
      rescue StandardError
        uri
      end
    end
  end
end
