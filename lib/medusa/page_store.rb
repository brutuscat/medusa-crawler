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

    #
    # If given a single URL (as a String or URI), returns an Array of Pages which link to that URL
    # If given an Array of URLs, returns a Hash (URI => [Page, Page...]) of Pages linking to those URLs
    #
    def pages_linking_to(urls)
      unless urls.is_a?(Array)
        urls = [urls]
        single = true
      end

      urls.map! do |url|
        unless url.is_a?(URI)
          URI(url) rescue nil
        else
          url
        end
      end
      urls.compact

      links = {}
      urls.each { |url| links[url] = [] }
      values.each do |page|
        urls.each { |url| links[url] << page if page.links.include?(url) }
      end

      if single and !links.empty?
        return links[urls.first]
      else
        return links
      end
    end

    #
    # If given a single URL (as a String or URI), returns an Array of URLs which link to that URL
    # If given an Array of URLs, returns a Hash (URI => [URI, URI...]) of URLs linking to those URLs
    #
    def urls_linking_to(urls)
      unless urls.is_a?(Array)
        urls = [urls] unless urls.is_a?(Array)
        single = true
      end

      links = pages_linking_to(urls)
      links.each { |url, pages| links[url] = pages.map{|p| p.url} }

      if single and !links.empty?
        return links[urls.first]
      else
        return links
      end
    end

  end
end
