require 'digest'
require 'medusa/http/cache/request_selector'

module Medusa
  class HTTP
    class Cache
      # Maps a request identity to its cached response variants. The injected
      # storage only needs to implement [], []=, and delete.
      class Index
        VERSION = 1
        Match = Data.define(:url, :key, :entry, :validation_entry)

        def initialize(storage:, &on_error)
          @storage = storage
          @on_error = on_error
          @mutex = Mutex.new
        end

        def lookup(url, request_headers, partition: nil)
          key = key_for(url, request_headers, partition)
          entries = read(key, url)
          return Match.new(url:, key:, entry: nil, validation_entry: nil) unless entries

          entry = entries.find { |candidate| candidate.matches?(request_headers) }
          validation_entry = if entry&.validator?
            entry
          elsif entry
            nil
          else
            entries.select(&:validator?).max_by(&:stored_at)
          end
          Match.new(url:, key:, entry:, validation_entry:)
        end

        def write(match, entry, replacing: match.entry)
          @mutex.synchronize do
            entries = read_unlocked(match.key, match.url) || []
            updated = replacing ? replace_snapshot(entries, replacing, entry) : store_variant(entries, entry)
            return false unless updated

            write_bucket(match.key, entries, match.url)
          end
        end

        def delete(match, entry = match.entry)
          return unless entry

          @mutex.synchronize do
            entries = read_unlocked(match.key, match.url)
            return unless entries

            index = entries.index(entry)
            return false unless index

            entries.delete_at(index)
            entries.empty? ? delete_bucket(match.key, match.url) : write_bucket(match.key, entries, match.url)
          end
        end

        private

        # Replace only the exact Entry value originally read. Another request may
        # have replaced or intentionally deleted it while revalidation was in flight.
        def replace_snapshot(entries, snapshot, replacement)
          index = entries.index(snapshot)
          return false unless index

          entries[index] = replacement
          true
        end

        def store_variant(entries, entry)
          entries.reject! { |candidate| candidate.same_variant?(entry) }
          entries << entry
          true
        end

        def key_for(url, request_headers, partition)
          sensitive = RequestSelector.sensitive_fingerprint(request_headers)
          digest = Digest::SHA256.hexdigest("#{url}\0#{sensitive}\0#{partition.inspect}")
          "medusa:http-cache:v#{VERSION}:#{digest}"
        end

        def read(key, url) = @mutex.synchronize { read_unlocked(key, url) }

        def read_unlocked(key, url)
          bucket = read_bucket(key, url)
          return if bucket.nil?

          unless valid_bucket?(bucket)
            error('corrupt_entry', url:)
            delete_bucket(key, url)
            return
          end

          entries = bucket['variants'].map { |value| Entry.load(value) }
          return entries if entries.all?

          error('corrupt_entry', url:)
          delete_bucket(key, url)
          nil
        end

        def read_bucket(key, url)
          @storage[key]
        rescue StandardError => exception
          error(
            'storage_error',
            url:,
            operation: :read,
            error: exception.class.name,
            message: exception.message
          )
          nil
        end

        def write_bucket(key, entries, url)
          @storage[key] = {'version' => VERSION, 'variants' => entries.map(&:to_h)}
        rescue StandardError => exception
          error(
            'storage_error',
            url:,
            operation: :write,
            error: exception.class.name,
            message: exception.message
          )
        end

        def delete_bucket(key, url)
          @storage.delete(key)
        rescue StandardError => exception
          error(
            'storage_error',
            url:,
            operation: :delete,
            error: exception.class.name,
            message: exception.message
          )
        end

        def valid_bucket?(bucket)
          bucket.is_a?(Hash) && bucket['version'] == VERSION && bucket['variants'].is_a?(Array)
        end

        def error(event, **fields) = @on_error&.call(event, fields)
      end
    end
  end
end
