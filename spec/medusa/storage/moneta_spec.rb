require 'spec_helper'
require 'medusa/storage/moneta.rb'

module Medusa
  describe Storage do
    describe ".Moneta" do
      let(:store) { Storage.Moneta(:Memory) }

      it_should_behave_like "storage engine"

      it "returns a Moneta adapter" do
        expect(store).to be_an_instance_of(Storage::Moneta)
      end
    end
  end
end
