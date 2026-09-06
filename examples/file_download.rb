# frozen_string_literal: true

require 'medusa'
require 'pathname'

module FileDownload
  module_function

  def crawl(start_url:, destination:, **options)
    destination = Pathname(destination)
    destination.mkpath

    Medusa.crawl(start_url, options) do |crawler|
      crawler.on_every_page do |page|
        next unless page.referer && page.code == 200 && !page.html?

        destination.join(filename(page.url)).binwrite(page.body)
      end
    end
  end

  def filename(url)
    Pathname(URI(url).path).basename.to_s
  end
  private_class_method :filename
end

if $PROGRAM_NAME == __FILE__
  crawl = FileDownload.crawl(
    start_url: ENV.fetch('MEDUSA_SITE_URL'),
    destination: ENV.fetch('MEDUSA_DOWNLOAD_DIRECTORY', 'downloads')
  )

  crawl.pages.each_value { |page| puts "#{page.code} #{page.url}" }
end
