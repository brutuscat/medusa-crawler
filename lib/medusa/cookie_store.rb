# frozen_string_literal: true

require 'delegate'
require 'http/cookie'
require 'moneta'
require 'monitor'
require 'webrick/cookie'

module Medusa
  # Stores RFC-scoped cookies while preserving the pre-2.0 Hash-like API.
  #
  # The delegated Hash is a flat compatibility view because the old API could
  # represent only one cookie per name. Moneta retains every domain/path variant
  # used by #header_for. Both views are updated together under one Monitor.
  class CookieStore < DelegateClass(Hash)
    COOKIE_PREFIX = "cookie\0"
    private_constant :COOKIE_PREFIX

    # +cookies+ may be the legacy name/value Hash or an Enumerable of parsed
    # HTTP::Cookie objects whose scope and expiry attributes must be retained.
    def initialize(cookies = nil)
      @cookies = {}
      @store = ::Moneta.new(:Memory, threadsafe: true, serializer: nil)
      @monitor = Monitor.new
      @projections = {}
      super(@cookies)

      cookies.is_a?(Hash) ? seed_legacy(cookies) : seed_scoped(cookies)
    end

    # Preserve the legacy Set-Cookie string API. Cookies added this way remain
    # unscoped, matching the behavior of CookieStore before 2.0.
    def merge!(set_cookie_string)
      parsed = WEBrick::Cookie.parse_set_cookies(set_cookie_string).compact.to_h do |cookie|
        [cookie.name, cookie]
      end

      @monitor.synchronize do
        parsed.each_key { remove_scoped(_1) }
        @cookies.merge!(parsed)
      end
    rescue StandardError
      nil
    end

    # Return the legacy flat Cookie header representation.
    def to_s
      @monitor.synchronize do
        reconcile_compatibility!
        @cookies.values.reject { expired?(_1) }.map { "#{_1.name}=#{_1.value}" }.join(';')
      end
    end

    # Return the cookies applicable to one request URI.
    def header_for(uri)
      uri = URI(uri)
      return '' unless URI::HTTP === uri && uri.host

      @monitor.synchronize do
        reconcile_compatibility!
        purge_expired!

        scoped = each_scoped_cookie.select { _1.valid_for_uri?(uri) }.sort
        [::HTTP::Cookie.cookie_value(scoped), legacy_header].reject(&:empty?).join('; ')
      end
    end

    # Parse and atomically apply every Set-Cookie field from one response.
    def store(set_cookie_headers, origin:)
      cookies = Array(set_cookie_headers).compact.flat_map do |header|
        ::HTTP::Cookie.parse(header, origin)
      end

      @monitor.synchronize { cookies.each { apply_scoped(_1) } }
      self
    end

    private

    def seed_legacy(cookies)
      cookies.each { |name, value| @cookies[name] = WEBrick::Cookie.new(name, value) }
    end

    def seed_scoped(cookies)
      return unless cookies

      parsed = cookies.to_a
      unless parsed.all? { ::HTTP::Cookie === _1 }
        raise ArgumentError, 'cookies must be a Hash or an Enumerable of HTTP::Cookie objects'
      end

      @monitor.synchronize { parsed.each { apply_scoped(_1.dup) } }
    end

    def apply_scoped(cookie)
      if cookie.expired?
        @store.delete(cookie_key(cookie))
        refresh_projection(cookie.name)
      else
        @store[cookie_key(cookie)] = cookie
        @cookies[cookie.name] = cookie
        @projections[cookie.name] = cookie
      end
    end

    # Hash mutations are detected lazily so all delegated Hash operations keep
    # their historical behavior without duplicating Hash's mutation surface.
    def reconcile_compatibility!
      @projections.to_a.each do |name, projected|
        next if @cookies[name].equal?(projected)

        remove_scoped(name)
      end
    end

    def remove_scoped(name)
      each_scoped_pair.select { |_key, cookie| cookie.name == name }.each do |key, _cookie|
        @store.delete(key)
      end
      @projections.delete(name)
    end

    def purge_expired!
      expired = each_scoped_pair.select { |_key, cookie| cookie.expired? }
      expired.each { |key, _cookie| @store.delete(key) }
      expired.map { |_key, cookie| cookie.name }.uniq.each { refresh_projection(_1) }
    end

    def refresh_projection(name)
      projected = @projections[name]
      return unless projected && @cookies[name].equal?(projected)

      replacement = each_scoped_cookie.select { _1.name == name }.max_by(&:created_at)
      if replacement
        @cookies[name] = replacement
        @projections[name] = replacement
      else
        @cookies.delete(name)
        @projections.delete(name)
      end
    end

    def legacy_header
      cookies = @cookies.reject { |name, cookie| @projections[name].equal?(cookie) }.values
      cookies.reject { expired?(_1) }.map { "#{_1.name}=#{_1.value}" }.join('; ')
    end

    def expired?(cookie)
      return cookie.expired? if cookie.respond_to?(:expired?)

      cookie.expires && cookie.expires < Time.now
    end

    def each_scoped_cookie = each_scoped_pair.map(&:last)

    def each_scoped_pair
      return enum_for(__method__) unless block_given?

      @store.each_key do |key|
        yield key, @store.load(key) if key.start_with?(COOKIE_PREFIX)
      end
    end

    def cookie_key(cookie)
      [cookie.domain, cookie.path, cookie.name].join("\0").prepend(COOKIE_PREFIX)
    end
  end
end
