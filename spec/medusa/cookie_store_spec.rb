# frozen_string_literal: true

require 'medusa/cookie_store'
require 'timeout'

module Medusa
  RSpec.describe CookieStore do
    let(:origin) { 'https://www.example.com/private/start' }

    it "should start out empty if no cookies are specified" do
      expect(CookieStore.new.empty?).to be true
    end

    it "should accept a Hash of cookies in the constructor" do
      expect(CookieStore.new({'test' => 'cookie'})['test'].value).to eq('cookie')
    end

    it "should be able to merge an HTTP cookie string" do
      cs = CookieStore.new({'a' => 'a', 'b' => 'b'})
      cs.merge! "a=A; path=/, c=C; path=/"
      expect(cs['a'].value).to eq('A')
      expect(cs['b'].value).to eq('b')
      expect(cs['c'].value).to eq('C')
    end

    it "should have a to_s method to turn the cookies into a string for the HTTP Cookie header" do
      expect(CookieStore.new({'a' => 'a', 'b' => 'b'}).to_s).to eq('a=a;b=b')
    end

    it 'keeps Hash access and enumeration as a compatibility facade' do
      store = CookieStore.new
      store.store('session=scoped; Path=/', origin:)

      expect(store.map { |name, cookie| [name, cookie.value] }).to eq([['session', 'scoped']])

      store['session'] = WEBrick::Cookie.new('session', 'legacy')
      expect(store.header_for('https://other.example/')).to eq('session=legacy')

      store.delete('session')
      expect(store.header_for(origin)).to be_empty
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

    it 'seeds parsed cookies without losing their attributes' do
      expires = Time.now + 3600
      cookie = ::HTTP::Cookie.parse(
        "session=abc123; Domain=example.com; Path=/private; Secure; Expires=#{expires.httpdate}",
        origin
      ).fetch(0)

      store = CookieStore.new([cookie])
      stored = store['session']

      expect(stored).not_to equal(cookie)
      expect(stored.domain).to eq(cookie.domain)
      expect(stored.path).to eq(cookie.path)
      expect(stored.secure?).to eq(cookie.secure?)
      expect(stored.expires.to_i).to eq(cookie.expires.to_i)
      expect(store.header_for('https://api.example.com/private/page')).to eq('session=abc123')
      expect(store.header_for('https://api.example.com/public')).to be_empty
      expect(store.header_for('http://api.example.com/private/page')).to be_empty
    end

    it 'applies each response atomically for concurrent writers and readers' do
      store = CookieStore.new
      store.store(['session=old; Path=/', 'csrf=old; Path=/'], origin:)
      storage = store.instance_variable_get(:@store)
      first_write = Queue.new
      release = Queue.new
      writes = 0

      allow(storage).to receive(:[]=).and_wrap_original do |write, key, value|
        write.call(key, value).tap do
          writes += 1
          if writes == 1
            first_write << true
            release.pop
          end
        end
      end

      writer_a = Thread.new { store.store(['session=A; Path=/', 'csrf=A; Path=/'], origin:) }
      Timeout.timeout(2) { first_write.pop }
      writer_b = Thread.new { store.store(['session=B; Path=/', 'csrf=B; Path=/'], origin:) }
      reader = Thread.new { store.header_for(origin) }

      blocked = begin
        Timeout.timeout(2) do
          Thread.pass until writer_b.status == 'sleep' && reader.status == 'sleep'
        end
        true
      rescue Timeout::Error
        false
      ensure
        release << true
      end

      writer_a.value
      writer_b.value
      observed = ::HTTP::Cookie.cookie_value_to_hash(reader.value)
      final = ::HTTP::Cookie.cookie_value_to_hash(store.header_for(origin))

      expect(blocked).to be(true)
      expect(observed).to satisfy { _1.values == %w[A A] || _1.values == %w[B B] }
      expect(final).to eq('session' => 'B', 'csrf' => 'B')
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
