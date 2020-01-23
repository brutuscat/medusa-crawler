require 'moneta'
require 'forwardable'

module Medusa
  module Storage
    class Moneta
      extend Forwardable

      def_delegators :@moneta, :[], :[]=, :delete, :key?, :clear, :close

      alias has_key? key?

      def initialize(name, options = {threadsafe: true, prefix: 'moneta'})
        @moneta = ::Moneta.new(name, options)
      end

      def each
        @moneta.each_key do |k|
          yield k, @moneta.fetch(k)
        end
        self
      end

      def size
        @moneta.each_key.size
      end

      def keys
        @moneta.each_key.to_a.sort
      end

      def merge!(hash)
        @moneta.merge!(hash)
        self
      end
    end
  end
end
