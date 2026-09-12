require 'cgi'
require 'nokogiri'
require 'ostruct'
require 'webrick/cookie'
require 'medusa/http/cache/page_metadata'

module Medusa
  class Page

    # The URL of the page
    attr_reader :url
    # The raw HTTP response body of the page
    attr_reader :body
    # Headers of the HTTP response
    attr_reader :headers
    # URL of the page this one redirected to, if any
    attr_reader :redirect_to
    # Exception object, if one was raised during HTTP#fetch_page
    attr_reader :error

    # OpenStruct for user-stored data
    attr_accessor :data
    # Integer response code of the page
    attr_accessor :code
    # Depth of this page from the root of the crawl. This is not necessarily the
    # shortest path; use PageStore#shortest_paths! to find that value.
    attr_accessor :depth
    # URL of the page that brought us to this page
    attr_accessor :referer
    # Response time of the request for this page in milliseconds
    attr_accessor :response_time

    #
    # Create a new page
    #
    def initialize(url, params = {})
      @url = url
      @data = OpenStruct.new

      @links = nil
      @body = nil
      @doc = nil
      @base = nil

      @code = params[:code]
      @headers = params[:headers] || {}
      @headers['content-type'] ||= ''
      @aliases = Array(params[:aka]).compact
      @referer = params[:referer]
      @depth = params[:depth] || 0
      @redirect_to = to_absolute(params[:redirect_to])
      @response_time = params[:response_time]
      @body = params[:body]
      @error = params[:error]

      @fetched = !params[:code].nil?
    end

    #
    # Array of distinct A tag HREFs from the page
    #
    def links
      return @links unless @links.nil?
      @links = []
      return @links unless doc

      doc.search("//a[@href]").each do |a|
        next if a['data-method'] && a['data-method'] != 'get'
        u = a['href']
        next if u.nil? || u.empty?
        abs = to_absolute(u) rescue next
        @links << abs if in_domain?(abs)
      end
      @links.uniq!
      @links
    end

    #
    # Nokogiri document for the HTML body
    #
    def doc
      return @doc if @doc
      @doc = Nokogiri::HTML(@body) if @body && html? rescue nil
    end

    #
    # Delete the Nokogiri document and response body to conserve memory
    #
    def discard_doc!
      links # force parsing of page links before we trash the document
      @doc = @body = nil
    end

    #
    # Was the page successfully fetched?
    # +true+ if the page was fetched with no error, +false+ otherwise.
    #
    def fetched? = @fetched

    #
    # Array of cookies received with this page as WEBrick::Cookie objects.
    #
    def cookies
      WEBrick::Cookie.parse_set_cookies(@headers['set-cookie']) rescue []
    end

    #
    # The content-type returned by the HTTP request for this page
    #
    def content_type = headers['content-type']

    #
    # Returns +true+ if the page is a HTML document, returns +false+
    # otherwise.
    #
    def html? = !!(content_type =~ %r{^(text/html|application/xhtml+xml)\b})

    #
    # Returns +true+ if the page is a HTTP redirect, returns +false+
    # otherwise.
    #
    def redirect? = (300..307).include?(@code)

    #
    # Returns +true+ if the page was not found (returned 404 code),
    # returns +false+ otherwise.
    #
    def not_found? = @code == 404

    #
    # Base URI from the HTML doc head element
    # http://www.w3.org/TR/html4/struct/links.html#edef-BASE
    #
    def base
      @base = if doc
        href = doc.search('//head/base/@href')
        URI(href.to_s) unless href.nil? rescue nil
      end unless @base

      return nil if @base && @base.to_s.empty?
      @base
    end


    #
    # Converts relative URL *link* into an absolute URL based on the
    # location of the page
    #
    def to_absolute(link)
      return nil if link.nil?

      relative = URI(link.to_s.gsub(/#.*$/, ''))
      absolute = base ? base.merge(relative) : @url.merge(relative)
      absolute.path = '/' if absolute.path.empty?
      absolute
    end

    #
    # Returns +true+ if *uri* is in the same domain as the page, returns
    # +false+ otherwise
    #
    def in_domain?(uri) = uri.host == @url.host

    def marshal_dump
      [@url, @headers, @data, @body, @links, @code, @visited, @depth, @referer,
       @redirect_to, @response_time, @fetched, cache_metadata_value]
    end

    def marshal_load(ary)
      @url, @headers, @data, @body, @links, @code, @visited, @depth, @referer,
        @redirect_to, @response_time, @fetched, from_cache = ary
      restore_cache_metadata(from_cache) unless from_cache.nil?
    end

    def to_hash
      hash = {'url' => @url.to_s,
              'headers' => Marshal.dump(@headers),
              'data' => Marshal.dump(@data),
              'body' => @body,
              'links' => links.map(&:to_s),
              'code' => @code,
              'visited' => @visited,
              'depth' => @depth,
              'referer' => @referer.to_s,
              'redirect_to' => @redirect_to.to_s,
              'response_time' => @response_time,
              'fetched' => @fetched}
      hash['http_cache_from_cache'] = @http_cache_from_cache if instance_variable_defined?(:@http_cache_from_cache)
      hash
    end

    def self.from_hash(hash)
      page = self.new(URI(hash['url']))
      {'@headers' => Marshal.load(hash['headers']),
       '@data' => Marshal.load(hash['data']),
       '@body' => hash['body'],
       '@links' => hash['links'].map { |link| URI(link) },
       '@code' => hash['code'].to_i,
       '@visited' => hash['visited'],
       '@depth' => hash['depth'].to_i,
       '@referer' => hash['referer'],
       '@redirect_to' => (!!hash['redirect_to'] && !hash['redirect_to'].empty?) ? URI(hash['redirect_to']) : nil,
       '@response_time' => hash['response_time'].to_i,
       '@fetched' => hash['fetched']
      }.each do |var, value|
        page.instance_variable_set(var, value)
      end
      page.send(:restore_cache_metadata, hash['http_cache_from_cache']) if hash.key?('http_cache_from_cache')
      page
    end

    private

    def cache_metadata_value
      @http_cache_from_cache if instance_variable_defined?(:@http_cache_from_cache)
    end

    def restore_cache_metadata(from_cache)
      @http_cache_from_cache = !!from_cache
      extend(Medusa::HTTP::Cache::PageMetadata)
    end
  end
end
