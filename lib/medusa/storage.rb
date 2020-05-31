module Medusa
  module Storage

    def self.Hash(*args)
      hash = Hash.new(*args)
      # add close method for compatibility with Storage::Base
      class << hash; def close; end; end
      hash
    end

    def self.Moneta(*args)
      require 'medusa/storage/moneta'
      self::Moneta.new(*args)
    end
  end
end
