# frozen_string_literal: true

require 'medusa'

module NestedFrames
  module_function

  def crawl(start_url:, **options)
    Medusa.crawl(start_url, options) do |crawler|
      crawler.focus_crawl do |page|
        page.links + frame_sources(page)
      end
    end
  end

  def frame_sources(page)
    return [] unless page.doc

    page.doc.css('frame[src], iframe[src]').filter_map do |frame|
      page.to_absolute(frame['src']) if frame['src'] && !frame['src'].empty?
    rescue URI::InvalidURIError
      nil
    end.select { |url| page.in_domain?(url) }
  end
  private_class_method :frame_sources
end

if $PROGRAM_NAME == __FILE__
  crawl = NestedFrames.crawl(start_url: ENV.fetch('MEDUSA_SITE_URL'))
  crawl.pages.each_value { |page| puts "#{page.code} #{page.url}" }
end
