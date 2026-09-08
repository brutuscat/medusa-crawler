# frozen_string_literal: true

require 'timeout'
require 'webrick'

module DocumentationCheck
  class Server
    def initialize(document_root)
      @document_root = document_root
    end

    def with_url
      server = WEBrick::HTTPServer.new(
        BindAddress: '127.0.0.1',
        Port: 0,
        DocumentRoot: @document_root,
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )
      thread = Thread.new { server.start }

      Timeout.timeout(5) { sleep 0.01 until server.status == :Running }
      yield "http://127.0.0.1:#{server.listeners.first.addr[1]}/"
    ensure
      server&.shutdown
      thread&.join
    end
  end
end
