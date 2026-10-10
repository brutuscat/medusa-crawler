# frozen_string_literal: true

require 'socket'
require 'thread'

# A deliberately small HTTP/1.1 server for deterministic crawler integration
# specs. Each request gets a server thread, so a test can hold responses at a
# barrier while the crawler's own runtime remains under observation.
class LocalHTTPServer
  Request = Data.define(:method, :path, :headers)
  Response = Data.define(:body, :status, :headers) do
    def initialize(body: '', status: 200, headers: {})
      super
    end
  end

  # Closing the gate wakes every blocked handler, including cleanup paths
  # where the crawler has cancelled its client socket.
  class Gate
    attr_reader :arrivals

    def initialize
      @arrivals = Queue.new
      @releases = Queue.new
    end

    def wait(value = true)
      @arrivals << value
      @releases.pop
    rescue ClosedQueueError
      nil
    end

    def release(count = 1)
      count.times { @releases << true }
    end

    def close
      @arrivals.close
      @releases.close
    end
  end

  STATUS_TEXT = {200 => 'OK', 301 => 'Moved Permanently', 302 => 'Found'}.freeze

  def initialize(&handler)
    @handler = handler
    @listener = TCPServer.new('127.0.0.1', 0)
    @port = @listener.addr[1]
    @mutex = Mutex.new
    @clients = []
    @handlers = []
    @active_requests = 0
    @peak_active_requests = 0
    @request_count = 0
    @acceptor = Thread.new { accept_requests }
  end

  def url(path = '/')
    "http://127.0.0.1:#{@port}#{path.start_with?('/') ? path : "/#{path}"}"
  end

  def active_requests
    @mutex.synchronize { @active_requests }
  end

  def peak_active_requests
    @mutex.synchronize { @peak_active_requests }
  end

  def request_count
    @mutex.synchronize { @request_count }
  end

  def close
    @listener.close unless @listener.closed?
    @acceptor.join
    clients = @mutex.synchronize { @clients.dup }
    clients.each { |client| client.close unless client.closed? }
    @mutex.synchronize { @handlers.dup }.each(&:join)
  end

  private

  def accept_requests
    loop do
      client = @listener.accept
      @mutex.synchronize do
        @clients << client
        @handlers << Thread.new { serve(client) }
      end
    end
  rescue IOError, Errno::EBADF
    nil
  end

  def serve(client)
    request = read_request(client)
    return unless request

    @mutex.synchronize do
      @active_requests += 1
      @peak_active_requests = [@peak_active_requests, @active_requests].max
      @request_count += 1
    end
    active = true

    response = @handler.call(request)
    finish_request
    active = false
    response = Response.new(body: response.to_s) unless response.is_a?(Response)
    body = response.body.to_s
    headers = {'Content-Type' => 'text/html', 'Content-Length' => body.bytesize.to_s,
               'Connection' => 'close'}.merge(response.headers)
    status_text = STATUS_TEXT.fetch(response.status, 'OK')
    client.write("HTTP/1.1 #{response.status} #{status_text}\r\n")
    headers.each { |name, value| client.write("#{name}: #{value}\r\n") }
    client.write("\r\n#{body}")
  rescue IOError, Errno::EPIPE, Errno::ECONNRESET
    nil
  ensure
    finish_request if active
    client.close unless client.closed?
    @mutex.synchronize do
      @clients.delete(client)
    end
  end

  def finish_request
    @mutex.synchronize do
      @active_requests -= 1
    end
  end

  def read_request(client)
    line = client.gets("\r\n")
    return unless line

    method, path, = line.split(' ', 3)
    headers = {}
    while (header = client.gets("\r\n")) && header != "\r\n"
      name, value = header.split(':', 2)
      headers[name.downcase] = value.to_s.strip if name
    end
    Request.new(method:, path:, headers:)
  end
end
