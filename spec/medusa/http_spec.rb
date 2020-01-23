require 'spec_helper'

module Medusa
  describe HTTP do

    describe "fetch_page" do
      before(:each) do
        FakeWeb.clean_registry
      end

      it "should still return a Page if an exception occurs during the HTTP connection" do
        allow_any_instance_of(Medusa::HTTP).to receive(:get_response).and_raise(StandardError, 'HARDCODED FAILURE!')
        http = Medusa::HTTP.new
        expect(http.fetch_page(SPEC_DOMAIN)).to be_an_instance_of(Page)
      end

    end
  end
end
