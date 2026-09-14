# frozen_string_literal: true

require 'medusa'

module CategoryCollection
  CATEGORY_PATH = %r{/categories/}
  PRODUCT_PATH = %r{/products/}

  module_function

  def crawl(start_url:, **options)
    Medusa.crawl(start_url, options) do |crawler|
      crawler.on_pages_like(CATEGORY_PATH) do |page|
        category = page.doc&.at_css('h1')&.text&.strip
        page.data.category = category unless category.nil? || category.empty?
      end

      crawler.after_crawl do |pages|
        collect_categories(pages)
      end
    end
  end

  def collect_categories(pages)
    category_pages = pages.values.select { |page| page.data.category }

    category_pages.each do |category_page|
      category_page.links.each do |product_url|
        next unless product_url.path.match?(PRODUCT_PATH)

        product = pages[product_url]
        next unless product

        product.data.categories = Array(product.data.categories) | [category_page.data.category]
        pages[product_url] = product
      end
    end
  end
  private_class_method :collect_categories
end

if $PROGRAM_NAME == __FILE__
  crawl = CategoryCollection.crawl(start_url: ENV.fetch('MEDUSA_SITE_URL'))

  crawl.pages.each_value do |page|
    categories = Array(page.data.categories)
    puts "#{page.url}: #{categories.join(', ')}" unless categories.empty?
  end
end
