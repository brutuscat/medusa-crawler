# frozen_string_literal: true

require 'webmock/rspec'

WebMock.disable_net_connect!

module Medusa
  AUTH = ['user', 'pass']
  SPEC_DOMAIN = "http://www.example.com/"
  AUTH_SPEC_DOMAIN = "http://#{AUTH.join(':')}@#{URI.parse(SPEC_DOMAIN).host}/"

  class FakePage
    attr_accessor :links
    attr_accessor :hrefs
    attr_accessor :body

    def initialize(name = '', options = {})
      @name = name
      @links = []
      @hrefs = []
      @redirect = nil
      @auth = false
      @base = ''

      @links = [options[:links]].flatten if options.has_key?(:links)
      @hrefs = [options[:hrefs]].flatten if options.has_key?(:hrefs)
      @redirect = options[:redirect] if options.has_key?(:redirect)
      @auth = options[:auth] if options.has_key?(:auth)
      @base = options[:base] if options.has_key?(:base)
      @content_type = options[:content_type] || "text/html"
      @body = options[:body]

      create_body unless @body
      add_to_fakeweb
    end

    def url
      SPEC_DOMAIN + @name
    end

    def auth_url
      AUTH_SPEC_DOMAIN + @name
    end

    private

    def create_body
      if @base
        @body = "<html><head><base href=\"#{@base}\"></head><body>"
      else
        @body = "<html><body>"
      end
      @links.each{|l| @body += "<a href=\"#{SPEC_DOMAIN}#{l}\"></a>"} if @links
      @hrefs.each{|h| @body += "<a href=\"#{h}\"></a>"} if @hrefs
      @body += "</body></html>"
    end

    def add_to_fakeweb
      options = {body: @body, status: [200, 'OK'], headers: {'Content-Type' => @content_type}}

      if @redirect
        options[:status] = [301, 'Moved Permanently']

        # only prepend SPEC_DOMAIN if a relative url (without an http scheme) was specified
        redirect_url = (@redirect =~ /http/) ? @redirect : SPEC_DOMAIN + @redirect
        options[:headers]['Location'] = redirect_url

        # register the page this one redirects to
        WebMock.stub_request(:get, redirect_url).to_return(body: '', status: [200, 'OK'], headers: {'Content-Type' => @content_type})
      end

      if @auth
        unautorized_options = {body: 'Unauthorized', status: [401, 'Unauthorized']}

        WebMock.stub_request(:get, url).to_return(unautorized_options)
        WebMock.stub_request(:get, url).with(basic_auth: AUTH).to_return(options)
      else
        WebMock.stub_request(:get, url).to_return(options)
      end
    end
  end
end

#default root
Medusa::FakePage.new
