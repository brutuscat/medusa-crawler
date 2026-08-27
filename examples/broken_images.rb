# frozen_string_literal: true

require 'medusa'
require 'set'

module BrokenImages
  module_function

  def crawl(start_url:, **options)
    image_urls = Set.new

    crawl = Medusa.crawl(start_url, options) do |crawler|
      crawler.focus_crawl do |page|
        images = image_sources(page)
        image_urls.merge(images.map(&:to_s))
        page.links + images
      end
    end

    broken = []
    crawl.pages.each_value do |page|
      broken << page if image_urls.include?(page.url.to_s) && page.code >= 400
    end

    [crawl, broken]
  end

  def image_sources(page)
    return [] unless page.doc

    page.doc.css('img[src]').filter_map do |image|
      page.to_absolute(image['src']) if image['src'] && !image['src'].empty?
    rescue URI::InvalidURIError
      nil
    end.select { |url| page.in_domain?(url) }
  end
  private_class_method :image_sources
end

if $PROGRAM_NAME == __FILE__
  _, broken = BrokenImages.crawl(start_url: ENV.fetch('MEDUSA_SITE_URL'))
  broken.each { |page| warn "#{page.code} #{page.url}" }
  exit 1 unless broken.empty?
end
