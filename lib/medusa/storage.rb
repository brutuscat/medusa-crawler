module Medusa
  module Storage

    def self.Hash(*args)
      hash = Hash.new(*args)
      # add close method for compatibility with Storage::Base
      class << hash; def close; end; end
      hash
    end

    def self.Redis(opts = {})
      require 'medusa/storage/redis'
      self::Redis.new(opts)
    end
  end
end
