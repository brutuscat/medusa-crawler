
RSpec.describe Medusa do

  it "should have a version" do
    expect(Medusa.const_defined?('VERSION')).to be true
  end

  it "should return a Medusa::Core from the crawl, which has a PageStore" do
    result = Medusa.crawl(SPEC_DOMAIN)
    expect(result).to be_an_instance_of(Medusa::Core)
    expect(result.pages).to be_an_instance_of(Medusa::PageStore)
  end

end
