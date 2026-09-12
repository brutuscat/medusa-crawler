module Medusa
  class HTTP
    class Cache
      module PageMetadata
        def from_cache? = !!@http_cache_from_cache
      end
    end
  end
end
