# frozen_string_literal: true

require 'support/storage_engine.rb'
require 'medusa/storage/redis.rb'

module Medusa
  RSpec.describe Storage do
    describe ".Hash" do
      let(:store) { Medusa::Storage.Hash }

      it_should_behave_like "storage engine"

      it "returns a Hash adapter" do
        expect(Medusa::Storage.Hash).to be_an_instance_of(Hash)
      end
    end
  end
end
