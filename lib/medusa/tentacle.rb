require 'medusa/http'

module Medusa
  class Tentacle

    #
    # Create a new Tentacle
    #
    def initialize(link_queue, page_queue, opts = {})
      @link_queue = link_queue
      @page_queue = page_queue
      @http = Medusa::HTTP.new(opts)
      @opts = opts
    end

    #
    # Gets links from @link_queue, and returns the fetched
    # Page objects into @page_queue
    #
    def run
      loop do
        link, referer, depth = @link_queue.deq

        break if link == :END

        @http.fetch_pages(link, referer, depth).each { |page| @page_queue << page }

        delay
        # Core uses this optional hook to retire one fetch only after its pages
        # have entered the page queue; standalone Tentacle users keep the old
        # page-only queue behavior.
        @opts[:fetch_task_complete]&.call
      end
    end

    private

    def delay
      sleep @opts[:delay] if @opts[:delay] > 0
    end

  end
end
