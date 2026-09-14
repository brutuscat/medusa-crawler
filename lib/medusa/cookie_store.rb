# frozen_string_literal: true

require 'http/cookie'
require 'moneta'

module Medusa
  class CookieStore
    COOKIE_PREFIX = "cookie\0"
    SEEDED_PREFIX = "seeded\0"
    private_constant :COOKIE_PREFIX, :SEEDED_PREFIX

    def initialize(cookies = nil, origins: [])
      @store = ::Moneta.new(:Memory, threadsafe: true, serializer: nil)
      @initial_cookies = cookies&.to_h&.transform_keys(&:to_s)&.freeze || {}.freeze
      origins = Array(origins)
      @seed_on_access = origins.empty?
      origins.each { seed(_1) }
    end

    def empty?
      @initial_cookies.empty? && each_cookie.none? { !_1.expired? }
    end

    def header_for(uri)
      uri = URI(uri)
      return '' unless URI::HTTP === uri && uri.host

      seed(uri) if @seed_on_access

      cookies = each_cookie.filter_map do |cookie|
        cookie if !cookie.expired? && cookie.valid_for_uri?(uri)
      end

      ::HTTP::Cookie.cookie_value(cookies.sort)
    end

    def store(set_cookie_headers, origin:)
      Array(set_cookie_headers).compact.flat_map do |header|
        ::HTTP::Cookie.parse(header, origin)
      end.each do |cookie|
        key = cookie_key(cookie)
        cookie.expired? ? @store.delete(key) : @store[key] = cookie
      end

      self
    end

    private

    def seed(origin)
      return self if @initial_cookies.empty?

      uri = URI(origin)
      return self unless URI::HTTP === uri && uri.host

      marker = "#{SEEDED_PREFIX}#{uri.host.downcase}"
      return self if @store.key?(marker)

      @initial_cookies.each do |name, value|
        cookie = ::HTTP::Cookie.new(name, value.to_s, origin: uri, path: '/')
        @store.create(cookie_key(cookie), cookie)
      end
      @store.create(marker, true)
      self
    end

    def each_cookie
      return enum_for(__method__) unless block_given?

      @store.each_key do |key|
        yield @store.load(key) if key.start_with?(COOKIE_PREFIX)
      end
    end

    def cookie_key(cookie)
      [cookie.domain, cookie.path, cookie.name].join("\0").prepend(COOKIE_PREFIX)
    end
  end
end
