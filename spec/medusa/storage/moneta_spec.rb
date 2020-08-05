# frozen_string_literal: true

require 'medusa/storage/moneta.rb'
require 'support/storage_engine.rb'

module Medusa
  RSpec.describe Storage do
    describe '.Moneta' do
      let(:store) { Storage.Moneta(:Memory) }

      it_should_behave_like 'storage engine'

      it 'returns a Moneta adapter' do
        expect(store).to be_an_instance_of(Storage::Moneta)
      end
    end
  end
end
