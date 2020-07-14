require 'moneta'
require 'forwardable'

module Medusa
  module Storage
    class Moneta
      extend Forwardable

      def_delegators :@moneta, :[], :[]=, :delete, :key?, :clear, :close

      alias has_key? key?

      def initialize(name, options = {})
        default_options = { threadsafe: true, prefix: 'medusa' }
        @moneta = ::Moneta.new(name, default_options.merge(options))
      end

      def each
        @moneta.each_key do |k|
          yield k, @moneta.fetch(k)
        end
        self
      end

      def size
        current_size = @moneta.each_key.size

        return @moneta.each_key.reduce(0) { |size, k|  size + 1 } if current_size.nil?
        return current_size
      end

      def keys
        @moneta.each_key.to_a.sort
      end

      def merge!(hash)
        @moneta.merge!(hash) unless hash.empty?
        self
      end
    end
  end
end
