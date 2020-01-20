$:.unshift(File.dirname(__FILE__))
require 'spec_helper'

require 'medusa/storage/redis.rb'

module Medusa
  describe Storage do
    module Storage
      shared_examples_for "storage engine" do

        before(:each) do
          @url = SPEC_DOMAIN
          @page = Page.new(URI(@url))
        end

        it "should implement [] and []=" do
          expect(@store).to respond_to(:[])
          expect(@store).to respond_to(:[]=)

          @store[@url] = @page
          expect(@store[@url].url).to eq(URI(@url))
        end

        it "should implement has_key?" do
          expect(@store).to respond_to(:has_key?)

          @store[@url] = @page
          expect(@store.has_key?(@url)).to eq(true)

          expect(@store.has_key?('missing')).to eq(false)
        end

        it "should implement delete" do
          expect(@store).to respond_to(:delete)

          @store[@url] = @page
          expect(@store.delete(@url).url).to eq(@page.url)
          expect(@store.has_key?(@url)).to be false
        end

        it "should implement keys" do
          expect(@store).to respond_to(:keys)

          urls = [SPEC_DOMAIN, SPEC_DOMAIN + 'test', SPEC_DOMAIN + 'another']
          pages = urls.map { |url| Page.new(URI(url)) }
          urls.zip(pages).each { |arr| @store[arr[0]] = arr[1] }

          expect((@store.keys - urls)).to eq([])
        end

        it "should implement each" do
          expect(@store).to respond_to(:each)

          urls = [SPEC_DOMAIN, SPEC_DOMAIN + 'test', SPEC_DOMAIN + 'another']
          pages = urls.map { |url| Page.new(URI(url)) }
          urls.zip(pages).each { |arr| @store[arr[0]] = arr[1] }

          result = {}
          @store.each { |k, v| result[k] = v }
          expect((result.keys - urls)).to eq([])
          expect((result.values.map { |page| page.url.to_s } - urls)).to eq([])
        end

        it "should implement merge!, and return self" do
          expect(@store).to respond_to(:merge!)

          hash = {SPEC_DOMAIN => Page.new(URI(SPEC_DOMAIN)),
                  SPEC_DOMAIN + 'test' => Page.new(URI(SPEC_DOMAIN + 'test'))}
          merged = @store.merge! hash
          hash.each { |key, value| expect(@store[key].url.to_s).to eq(key) }

          expect(merged).to be @store
        end

        it "should correctly deserialize nil redirect_to when loading" do
          expect(@page.redirect_to).to be_nil
          @store[@url] = @page
          expect(@store[@url].redirect_to).to be_nil
        end
      end

      # describe Storage::Redis do
      #   it_should_behave_like "storage engine"

      #   before(:each) do
      #     @store = Storage.Redis
      #   end

      #   after(:each) do
      #     @store.close
      #   end
      # end

    end


    describe ".Hash" do
      it "returns a Hash adapter" do
        expect(Medusa::Storage.Hash).to be_an_instance_of(Hash)
      end
    end

    describe ".Redis" do
      it "returns a Redis adapter" do
        store = Medusa::Storage.Redis
        expect(store).to be_an_instance_of(Medusa::Storage::Redis)
        store.close
      end

      it_should_behave_like "storage engine"

      before(:each) do
        @store = Storage.Redis
      end

      after(:each) do
        @store.close
      end
    end
  end
end
