# frozen_string_literal: true

require 'medusa/http'
require 'fakeweb_helper'

module Medusa
  RSpec.describe HTTP do

    describe "fetch_page" do
      before(:each) do
        WebMock.reset!
      end

      it "should still return a Page if an exception occurs during the HTTP connection" do
        allow_any_instance_of(Medusa::HTTP).to receive(:get_response).and_raise(StandardError, 'HARDCODED FAILURE!')
        http = Medusa::HTTP.new
        expect(http.fetch_page(SPEC_DOMAIN)).to be_an_instance_of(Page)
      end

    end
  end
end
