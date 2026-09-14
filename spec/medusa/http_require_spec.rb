# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe 'HTTP direct requires' do
  let(:lib_dir) { File.expand_path('../../lib', __dir__) }

  def require_in_fresh_ruby(path)
    Open3.capture3(RbConfig.ruby, '-I', lib_dir, '-e', "require '#{path}'")
  end

  it "loads require 'medusa/http' directly" do
    _stdout, stderr, status = require_in_fresh_ruby('medusa/http')

    expect(stderr).to eq('')
    expect(status).to be_success
  end

  it "loads require 'medusa/http/cache' directly" do
    _stdout, stderr, status = require_in_fresh_ruby('medusa/http/cache')

    expect(stderr).to eq('')
    expect(status).to be_success
  end
end
