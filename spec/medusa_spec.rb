$:.unshift(File.dirname(__FILE__))
require 'spec_helper'

describe Medusa do

  it "should have a version" do
    Medusa.const_defined?('VERSION').should == true
  end

  it "should return a Medusa::Core from the crawl, which has a PageStore" do
    result = Medusa.crawl(SPEC_DOMAIN)
    result.should be_an_instance_of(Medusa::Core)
    result.pages.should be_an_instance_of(Medusa::PageStore)
  end

end
