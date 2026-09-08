# frozen_string_literal: true

require 'medusa'

module DocumentationCheck
  module MedusaDocsScanner
    module_function

    def scan(start_url)
      crawl = Medusa.crawl(start_url, threads: 2, read_timeout: 5)
      broken = crawl.pages.values.select do |page|
        page.error || !page.fetched? || page.code.to_i >= 400
      end

      [crawl, broken]
    end
  end
end
