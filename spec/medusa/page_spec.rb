require 'fakeweb_helper'
require 'medusa/page'

module Medusa
  RSpec.describe Page do

    before(:each) do
      WebMock.reset!
      @http = Medusa::HTTP.new
      @page = @http.fetch_page(FakePage.new('home', :links => '1').url)
    end

    it "should indicate whether it successfully fetched via HTTP" do
      expect(@page).to respond_to(:fetched?)
      expect(@page.fetched?).to eq(true)

      fail_page = @http.fetch_page(SPEC_DOMAIN + 'fail')
      expect(fail_page.fetched?).to eq(false)
    end

    it "should store and expose the response body of the HTTP request" do
      page = @http.fetch_page(FakePage.new('body_test', {:body => 'test'}).url)
      expect(page.body).to eq('test')
    end

    it "should record any error that occurs during fetch_page" do
      expect(@page).to respond_to(:error)
      expect(@page.error).to be_nil

      fail_page = @http.fetch_page(SPEC_DOMAIN + 'fail')
      expect(fail_page.error).to_not be_nil
    end

    it "should store the response headers when fetching a page" do
      expect(@page.headers).to_not be_nil
      expect(@page.headers).to have_key('content-type')
    end

    it "should have an OpenStruct attribute for the developer to store data in" do
      expect(@page.data).to_not be_nil
      expect(@page.data).to be_an_instance_of(OpenStruct)

      @page.data.test = 'test'
      expect(@page.data.test).to eq('test')
    end

    it "should have a Nokogori::HTML::Document attribute for the page body" do
      expect(@page.doc).to_not be_nil
      expect(@page.doc).to be_an_instance_of(Nokogiri::HTML::Document)
    end

    it "should indicate whether it was fetched after an HTTP redirect" do
      expect(@page).to respond_to(:redirect?)

      expect(@page.redirect?).to eq(false)

      expect(@http.fetch_pages(FakePage.new('redir', :redirect => 'home').url).first.redirect?).to eq(true)
    end

    it "should have a method to tell if a URI is in the same domain as the page" do
      expect(@page).to respond_to(:in_domain?)

      expect(@page.in_domain?(URI(FakePage.new('test').url))).to eq(true)
      expect(@page.in_domain?(URI('http://www.other.com/'))).to eq(false)
    end

    it "should include the response time for the HTTP request" do
      expect(@page).to respond_to(:response_time)
    end

    it "should have the cookies received with the page" do
      expect(@page).to respond_to(:cookies)
      expect(@page.cookies).to eq([])
    end

    describe "#to_hash" do
      it "converts the page to a hash" do
        hash = @page.to_hash
        expect(hash['url']).to eq(@page.url.to_s)
        expect(hash['referer']).to eq(@page.referer.to_s)
        expect(hash['links']).to eq(@page.links.map(&:to_s))
      end

      context "when redirect_to is nil" do
        it "sets 'redirect_to' to nil in the hash" do
          expect(@page.redirect_to).to be_nil
          expect(@page.to_hash[:redirect_to]).to be_nil
        end
      end

      context "when redirect_to is a non-nil URI" do
        it "sets 'redirect_to' to the URI string" do
          new_page = Page.new(URI(SPEC_DOMAIN), {:redirect_to => URI(SPEC_DOMAIN + '1')})
          expect(new_page.redirect_to.to_s).to eq(SPEC_DOMAIN + '1')
          expect(new_page.to_hash['redirect_to']).to eq(SPEC_DOMAIN + '1')
        end
      end
    end

    describe "#from_hash" do
      it "converts from a hash to a Page" do
        page = @page.dup
        page.depth = 1
        converted = Page.from_hash(page.to_hash)
        expect(converted.links).to eq(page.links)
        expect(converted.depth).to eq(page.depth)
      end

      it 'handles a from_hash with a nil redirect_to' do
        page_hash = @page.to_hash
        page_hash['redirect_to'] = nil
        expect{ Page.from_hash(page_hash) }.not_to raise_error
        expect(Page.from_hash(page_hash).redirect_to).to be_nil
      end
    end

    describe "#redirect_to" do
      context "when the page was a redirect" do
        it "returns a URI of the page it redirects to" do
          new_page = Page.new(URI(SPEC_DOMAIN), {:redirect_to => URI(SPEC_DOMAIN + '1')})
          redirect = new_page.redirect_to
          expect(redirect).to be_a(URI)
          expect(redirect.to_s).to eq(SPEC_DOMAIN + '1')
        end
      end
    end

    describe "#links" do
      it "should not convert anchors to %23" do
        page = @http.fetch_page(FakePage.new('', :body => '<a href="#top">Top</a>').url)
        expect(page.links.size).to eq(1)
        expect(page.links.first.to_s).to eq(SPEC_DOMAIN)
      end

      it 'removes anchors containing non-alphanumeric characters' do
        links = '<a href="#Top of the page!">Top</a><a href="#Bottom of the page!">Bottom</a>'
        page = @http.fetch_page(FakePage.new('', :body => links).url)
        page.links.should have(1).link
        page.links.first.to_s.should == SPEC_DOMAIN
      end

      it 'should not return rails ujs links with data-method attribute' do
        body = '<a data-method="delete" href="/delete_me">Something</a>' \
               '<a data-method="patch" href="/patch_me">Something</a>' \
               '<a href="/get_me">Something</a>'
        page = @http.fetch_page(FakePage.new('', body: body).url)
        expect(page.links.size).to eq(1)
        expect(page.links[0]).to be_a(URI)
        expect(page.links[0].to_s).to eq('http://www.example.com/get_me')
      end
    end

    it "should detect, store and expose the base url for the page head" do
      base = "#{SPEC_DOMAIN}path/to/base_url/"
      page = @http.fetch_page(FakePage.new('body_test', {:base => base}).url)
      expect(page.base).to eq(URI(base))
      expect(@page.base).to be_nil
    end

    it "should have a method to convert a relative url to an absolute one" do
      expect(@page).to respond_to(:to_absolute)

      # Identity
      expect(@page.to_absolute(@page.url)).to eq(@page.url)
      expect(@page.to_absolute("")).to eq(@page.url)

      # Root-ness
      expect(@page.to_absolute("/")).to eq(URI("#{SPEC_DOMAIN}"))

      # Relativeness
      relative_path = "a/relative/path"
      expect(@page.to_absolute(relative_path)).to eq(URI("#{SPEC_DOMAIN}#{relative_path}"))

      deep_page = @http.fetch_page(FakePage.new('home/deep', :links => '1').url)
      upward_relative_path = "../a/relative/path"
      expect(deep_page.to_absolute(upward_relative_path)).to eq(URI("#{SPEC_DOMAIN}#{relative_path}"))

      # The base URL case
      base_path = "path/to/base_url/"
      base = "#{SPEC_DOMAIN}#{base_path}"
      page = @http.fetch_page(FakePage.new('home', {:base => base}).url)

      # Identity
      expect(page.to_absolute(page.url)).to eq(page.url)
      # It should revert to the base url
      expect(page.to_absolute("")).to_not eq(page.url)

      # Root-ness
      expect(page.to_absolute("/")).to eq(URI("#{SPEC_DOMAIN}"))

      # Relativeness
      relative_path = "a/relative/path"
      expect(page.to_absolute(relative_path)).to eq(URI("#{base}#{relative_path}"))

      upward_relative_path = "../a/relative/path"
      upward_base = "#{SPEC_DOMAIN}path/to/"
      expect(page.to_absolute(upward_relative_path)).to eq(URI("#{upward_base}#{relative_path}"))
    end
  end
end
