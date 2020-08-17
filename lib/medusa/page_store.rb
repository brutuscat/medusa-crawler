require 'forwardable'

module Medusa
  class PageStore
    extend Forwardable

    def_delegators :@storage, :keys, :values, :size, :each

    def initialize(storage = {})
      @storage = storage
    end

    # We typically index the hash with a URI,
    # but convert it to a String for easier retrieval
    def [](index)
      @storage[index.to_s]
    end

    def []=(index, other)
      @storage[index.to_s] = other
    end

    def delete(key)
      @storage.delete key.to_s
    end

    def has_key?(key)
      @storage.has_key? key.to_s
    end

    def each_value
      each { |key, value| yield value }
    end

    def values
      result = []
      each { |key, value| result << value }
      result
    end

    def touch_key(key)
      self[key] = Page.new(key)
    end

    def touch_keys(keys)
      @storage.merge! keys.inject({}) { |h, k| h[k.to_s] = Page.new(k); h }
    end

    # Does this PageStore contain the specified URL?
    # HTTP and HTTPS versions of a URL are considered to be the same page.
    def has_page?(url)
      schemes = %w(http https)
      if schemes.include? url.scheme
        u = url.dup
        return schemes.any? { |s| u.scheme = s; has_key?(u) }
      end

      has_key? url
    end

    #
    # Removes all Pages from storage where redirect? is true
    #
    def uniq!
      each_value { |page| delete page.url if page.redirect? }
      self
    end
  end
end
