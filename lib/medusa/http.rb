require 'rubygems'
require 'open-uri'
require 'medusa/page'
require 'medusa/cookie_store'
require 'medusa/http/cache'

module Medusa
  class HTTP
    # Maximum number of redirects to follow on each get_response
    REDIRECT_LIMIT = 5
    RETRY_LIMIT = 6

    # CookieStore for this HTTP client
    attr_reader :cookie_store

    def initialize(opts = {}, cache: nil)
      @opts = opts
      @cookie_store = CookieStore.new(@opts[:cookies])
      @cache = cache || Cache.build(@opts[:http_cache], logger: @opts[:logger])
    end

    #
    # Fetch a single Page from the response of an HTTP request to *url*.
    # Just gets the final destination page.
    #
    def fetch_page(url, referer = nil, depth = nil)
      fetch_pages(url, referer, depth).last
    end

    #
    # Create new Pages from the response of an HTTP request to *url*,
    # including redirects
    #
    def fetch_pages(url, referer = nil, depth = nil)
      pages = []
      begin
        url = URI(url) unless url.is_a?(URI)
        get(url, referer) do |response, headers, code, location, redirect_to, response_time, from_cache|
          page = Page.new(location, :body => response,
                                    :headers => headers,
                                    :code => code,
                                    :referer => referer,
                                    :depth => depth,
                                    :redirect_to => redirect_to,
                                    :response_time => response_time)
          @cache.decorate(page, from_cache: from_cache) if @cache
          pages << page
        end

        return pages
      rescue StandardError => e
        page = Page.new(url, error: e)
        @cache.decorate(page, from_cache: false) if @cache
        return pages << page
      end
    end

    #
    # The maximum number of redirects to follow
    #
    def redirect_limit
      @opts[:redirect_limit] || REDIRECT_LIMIT
    end

    #
    # The user-agent string which will be sent with each request,
    # or nil if no such option is set
    #
    def user_agent
      @opts[:user_agent]
    end

    #
    # Does this HTTP client accept cookies from the server?
    #
    def accept_cookies?
      @opts[:accept_cookies]
    end

    #
    # The http authentication options as in http://www.ruby-doc.org/stdlib/libdoc/open-uri/rdoc/OpenURI/OpenRead.html
    # userinfo is deprecated [RFC3986]
    #
    def http_basic_authentication
      @opts[:http_basic_authentication]
    end

    #
    # The proxy authentication options as in http://www.ruby-doc.org/stdlib/libdoc/open-uri/rdoc/OpenURI/OpenRead.html
    #
    def proxy_http_basic_authentication
      @opts[:proxy_http_basic_authentication]
    end

    #
    # The proxy options as in http://www.ruby-doc.org/stdlib/libdoc/open-uri/rdoc/OpenURI/OpenRead.html
    #
    def proxy
      @opts[:proxy]
    end

    #
    # The proxy address string
    #
    def proxy_host
      @opts[:proxy_host]
    end

    #
    # The proxy port number
    #
    def proxy_port
      @opts[:proxy_port]
    end

    #
    # HTTP read timeout in seconds
    #
    def read_timeout
      @opts[:read_timeout]
    end

    private

    #
    # Retrieve HTTP responses for *url*, including redirects.
    # Yields the response object, response code, and URI location
    # for each response.
    #
    def get(url, referer = nil)
      limit = redirect_limit
      loc = url
      begin
          # if redirected to a relative url, merge it with the host of the original
          # request url
          loc = url.merge(loc) if loc.relative?

          result = get_response(loc, referer)

          yield result.body, result.headers, result.code, loc, result.redirect_to, result.response_time, result.from_cache
          limit -= 1
      end while (loc = result.redirect_to) && allowed?(result.redirect_to, url) && limit > 0
    end

    #
    # Get an HTTP response for *url*, sending the appropriate User-Agent string.
    # HTTP cache policy wraps the existing OpenURI request when enabled.
    #
    def get_response(url, referer = nil)
      headers = request_headers(referer)
      return network_response(url, headers) unless @cache

      @cache.fetch(url, headers, partition: http_basic_authentication) do |cache_headers|
        network_response(url, cache_headers)
      end
    end

    def request_headers(referer)
      headers = {}
      headers['User-Agent'] = user_agent if user_agent
      headers['Referer'] = referer.to_s if referer
      headers['Cookie'] = @cookie_store.to_s unless @cookie_store.empty? || (!accept_cookies? && @opts[:cookies].nil?)
      headers
    end

    def open_uri_options(headers)
      opts = headers.dup
      opts[:http_basic_authentication] = http_basic_authentication if http_basic_authentication
      opts[:proxy] = proxy if proxy
      opts[:proxy_http_basic_authentication] = proxy_http_basic_authentication if proxy_http_basic_authentication
      opts[:read_timeout] = read_timeout if read_timeout
      opts[:redirect] = false
      opts
    end

    def network_response(url, headers)
      opts = open_uri_options(headers)
      redirect_to = nil
      retries = 0
      resource = nil

      begin
        start = Time.now()

        begin
          if Gem::Requirement.new('< 2.5').satisfied_by?(Gem::Version.new(RUBY_VERSION))
            resource = open(url, opts)
          else
            resource = URI.open(url, opts)
          end
        rescue OpenURI::HTTPRedirect => e_redirect
          resource = e_redirect.io
          redirect_to = e_redirect.uri
        rescue OpenURI::HTTPError => e_http
          resource = e_http.io
        end

        finish = Time.now()
        response_time = ((finish - start) * 1000).round
        @cookie_store.merge!(resource.meta['set-cookie']) if accept_cookies?

        Cache::Result.new(
          resource.read,
          resource.meta,
          response_time,
          resource.status.shift.to_i,
          redirect_to,
          false
        )
      rescue Timeout::Error, EOFError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::ECONNRESET
        retries += 1
        sleep(3 ^ retries)
        retry unless retries > RETRY_LIMIT
        raise
      ensure
        resource&.close unless resource&.closed?
      end
    end

    #
    # Allowed to connect to the requested url?
    #
    def allowed?(to_url, from_url)
      to_url.host.nil? || (to_url.host == from_url.host)
    end
  end
end
