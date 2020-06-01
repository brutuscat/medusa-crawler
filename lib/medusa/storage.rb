module Medusa
  module Storage
    def self.Moneta(*args)
      require 'medusa/storage/moneta'
      self::Moneta.new(*args)
    end
  end
end
