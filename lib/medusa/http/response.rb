module Medusa
  class HTTP
    # One HTTP response hop transported between the network, cache, and Page.
    Response = Data.define(:url, :body, :headers, :response_time, :code, :redirect_to, :from_cache)
    private_constant :Response
  end
end
