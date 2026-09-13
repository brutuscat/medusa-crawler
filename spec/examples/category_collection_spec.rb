# frozen_string_literal: true

require 'fakeweb_helper'
require_relative '../../examples/category_collection'

RSpec.describe CategoryCollection do
  it 'collects every category page that links to a product' do
    start_url = 'https://www.example.com/catalog'
    shoes_url = 'https://www.example.com/categories/shoes'
    sale_url = 'https://www.example.com/categories/sale'
    product_url = 'https://www.example.com/products/42'

    stub_request(:get, start_url).to_return(
      body: '<a href="/categories/shoes">Shoes</a><a href="/categories/sale">Sale</a>',
      headers: {'Content-Type' => 'text/html'}
    )
    stub_request(:get, shoes_url).to_return(
      body: '<h1>Shoes</h1><a href="/products/42">Product</a>',
      headers: {'Content-Type' => 'text/html'}
    )
    stub_request(:get, sale_url).to_return(
      body: '<h1>Sale</h1><a href="/products/42">Product</a>',
      headers: {'Content-Type' => 'text/html'}
    )
    stub_request(:get, product_url).to_return(
      body: '<h1>Running shoe</h1>',
      headers: {'Content-Type' => 'text/html'}
    )

    crawl = described_class.crawl(start_url: start_url)

    expect(crawl.pages[shoes_url].data.category).to eq('Shoes')
    expect(crawl.pages[sale_url].data.category).to eq('Sale')
    expect(crawl.pages[product_url].data.categories).to contain_exactly('Shoes', 'Sale')
    expect(a_request(:get, product_url)).to have_been_made.once
  end
end
