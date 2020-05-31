# frozen_string_literal: true

require 'medusa/cookie_store'

module Medusa
  RSpec.describe CookieStore do

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

  end
end
