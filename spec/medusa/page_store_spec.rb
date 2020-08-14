# frozen_string_literal: true

require 'fakeweb_helper'
require 'medusa/page_store'

module Medusa
  RSpec.describe PageStore do

    before(:all) do
      WebMock.reset!
    end

    RSpec.shared_examples_for "page storage" do
      it "should be able to remove all redirects in-place" do
        pages = []
        pages << FakePage.new('0', :links => ['1'])
        pages << FakePage.new('1', :redirect => '2')
        pages << FakePage.new('2')

        page_store = Medusa.crawl(pages[0].url, opts).pages

        expect(page_store).to respond_to(:uniq!)

        page_store.uniq!
        expect(page_store.has_key?(pages[1].url)).to eq(false)
        expect(page_store.has_key?(pages[0].url)).to eq(true)
        expect(page_store.has_key?(pages[2].url)).to eq(true)
      end

      it "should be able to find pages linking to a url" do
        pages = []
        pages << FakePage.new('0', :links => ['1'])
        pages << FakePage.new('1', :redirect => '2')
        pages << FakePage.new('2')

        page_store = Medusa.crawl(pages[0].url, opts).pages

        expect(page_store).to respond_to(:pages_linking_to)

        expect(page_store.pages_linking_to(pages[2].url).size).to eq(0)
        links_to_1 = page_store.pages_linking_to(pages[1].url)
        expect(links_to_1.size).to eq(1)
        expect(links_to_1.first).to be_an_instance_of(Page)
        expect(links_to_1.first.url.to_s).to eq(pages[0].url)
      end

      it "should be able to find urls linking to a url" do
        pages = []
        pages << FakePage.new('0', :links => ['1'])
        pages << FakePage.new('1', :redirect => '2')
        pages << FakePage.new('2')

        page_store = Medusa.crawl(pages[0].url, opts).pages

        expect(page_store).to respond_to(:pages_linking_to)

        expect(page_store.urls_linking_to(pages[2].url).size).to eq(0)
        links_to_1 = page_store.urls_linking_to(pages[1].url)
        expect(links_to_1.size).to eq(1)
        expect(links_to_1.first.to_s).to eq(pages[0].url)
      end
    end

    describe Hash do
      let(:opts) { Hash.new }
      it_should_behave_like "page storage"
    end
  end
end
