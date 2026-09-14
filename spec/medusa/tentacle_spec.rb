# frozen_string_literal: true

require 'medusa/core'

module Medusa
  RSpec.describe Tentacle do
    let(:link_queue) { Queue.new }
    let(:page_queue) { Queue.new }
    let(:http) { instance_double(HTTP) }
    let(:tentacle) do
      described_class.new(link_queue, page_queue, delay: 0).tap do |worker|
        worker.instance_variable_set(:@http, http)
      end
    end

    def run_task(task)
      link_queue << task
      link_queue << :END
      tentacle.run
    end

    it 'preserves the exact three-argument call for a bare URI' do
      url = URI('https://www.example.com/root')
      expect(http).to receive(:fetch_pages).with(url, nil, nil).and_return([])

      run_task(url)
    end

    it 'preserves the exact three-argument call for a legacy tuple' do
      url = URI('https://www.example.com/child')
      referer = URI('https://www.example.com/root')
      expect(http).to receive(:fetch_pages).with(url, referer, 2).and_return([])

      run_task([url, referer, 2])
    end

    it 'consumes the new crawl task through the legacy tuple protocol' do
      task_class = Core.const_get(:FetchTask, false)
      url = URI('https://www.example.com/child')
      referer = URI('https://www.example.com/root')
      task = task_class.new(url:, referer:, depth: 2)
      expect(http).to receive(:fetch_pages).with(url, referer, 2).and_return([])

      expect(task.to_ary).to eq([url, referer, 2])
      run_task(task)
    end

    it 'keeps the crawl task private' do
      expect(Core.const_get(:FetchTask, false).superclass).to eq(Data)
      expect { Core::FetchTask }.to raise_error(NameError, /private constant/)
    end

    it 'keeps the END sentinel from reaching HTTP' do
      link_queue << :END
      expect(http).not_to receive(:fetch_pages)

      tentacle.run
    end
  end
end
