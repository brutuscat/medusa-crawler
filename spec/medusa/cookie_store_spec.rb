# frozen_string_literal: true

require 'medusa/cookie_store'

module Medusa
  RSpec.describe CookieStore do
    let(:origin) { 'https://www.example.com/private/start' }

    it 'starts empty without configured cookies' do
      expect(CookieStore.new.empty?).to be true
    end

    it 'seeds configured cookies for each crawl host' do
      store = CookieStore.new({test: 'cookie'}, origins: [origin])

      expect(store.header_for(origin)).to eq('test=cookie')
      expect(store.header_for('https://other.example/private')).to be_empty
    end

    it 'stores every Set-Cookie header without flattening cookie scope' do
      store = CookieStore.new
      store.store(
        ['session=root; Path=/', 'session=private; Path=/private'],
        origin:
      )

      expect(store.header_for(origin)).to eq('session=private; session=root')
      expect(store.header_for('https://www.example.com/public')).to eq('session=root')
    end

    it 'honors domain and secure attributes' do
      store = CookieStore.new
      store.store(
        ['domain=wide; Domain=example.com; Path=/', 'secure=secret; Secure; Path=/'],
        origin:
      )

      expect(store.header_for('https://api.example.com/')).to eq('domain=wide')
      expect(store.header_for('http://www.example.com/')).to eq('domain=wide')
      expect(store.header_for('https://unrelated.test/')).to be_empty
    end

    it 'removes a cookie when the server expires it' do
      store = CookieStore.new
      store.store('session=active; Path=/', origin:)
      store.store('session=; Max-Age=0; Path=/', origin:)

      expect(store.header_for(origin)).to be_empty
      expect(store).to be_empty
    end

    it 'keeps concurrent reads and writes in one shared store' do
      store = CookieStore.new
      threads = 20.times.map do |index|
        Thread.new do
          store.store("cookie_#{index}=#{index}; Path=/", origin:)
          store.header_for(origin)
        end
      end

      threads.each(&:join)
      cookies = ::HTTP::Cookie.cookie_value_to_hash(store.header_for(origin))

      expect(cookies).to eq(20.times.to_h { |index| ["cookie_#{index}", index.to_s] })
    end
  end
end
