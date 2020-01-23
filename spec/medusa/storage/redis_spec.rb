require 'spec_helper'
require 'support/shared_storage_spec.rb'
require 'medusa/storage/redis.rb'

module Medusa
  describe Storage do
    describe ".Redis" do
      let(:store) { Storage.Redis }

      it_should_behave_like "storage engine"

      it "returns a Redis adapter" do
        expect(store).to be_an_instance_of(Storage::Redis)
      end
    end
  end
end
