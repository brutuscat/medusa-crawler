require 'medusa/core'
require 'fakeweb_helper'

module Medusa
  RSpec.describe Core do

    before(:each) do
      WebMock.reset!
    end

    it 'constructs the default HTTP cache when enabled' do
      page = FakePage.new('cached')

      crawl = Medusa.crawl(page.url, http_cache: true)

      expect(crawl.pages[page.url].from_cache?).to be(false)
    end

    it 'keeps the pre-2.0 Tentacle constructor and shares one cache across workers' do
      page = FakePage.new('shared-cache')
      worker_caches = Queue.new

      expect(Tentacle.instance_method(:initialize).parameters).to eq(
        [[:req, :link_queue], [:req, :page_queue], [:opt, :opts]]
      )
      allow(Tentacle).to receive(:new).and_wrap_original do |constructor, *arguments|
        worker_caches << arguments.fetch(2).fetch(:http_cache)
        constructor.call(*arguments)
      end

      Medusa.crawl(page.url, http_cache: true, threads: 2)

      caches = 2.times.map { worker_caches.pop }
      expect(caches).to all(be_a(HTTP::Cache))
      expect(caches.uniq.size).to eq(1)
    end

    it 'does not reuse a response that establishes a cookie across crawls' do
      storage = {}
      login_url = URI(SPEC_DOMAIN).merge('/cached-login').to_s
      private_url = URI(SPEC_DOMAIN).merge('/private').to_s
      login = stub_request(:get, login_url)
        .to_return(
          body: '<a href="/private">Private</a>',
          headers: {
            'Content-Type' => 'text/html',
            'Cache-Control' => 'max-age=60',
            'Set-Cookie' => 'session=first; Path=/'
          }
        )
        .then
        .to_return(
          body: '<a href="/private">Private</a>',
          headers: {
            'Content-Type' => 'text/html',
            'Cache-Control' => 'max-age=60',
            'Set-Cookie' => 'session=second; Path=/'
          }
        )
      first_private = stub_request(:get, private_url)
        .with(headers: {'Cookie' => 'session=first'})
        .to_return(body: 'first session', headers: {'Cache-Control' => 'no-store'})
      second_private = stub_request(:get, private_url)
        .with(headers: {'Cookie' => 'session=second'})
        .to_return(body: 'second session', headers: {'Cache-Control' => 'no-store'})
      options = {
        accept_cookies: true,
        threads: 1,
        http_cache: {storage:, strategy: :freshness}
      }

      Medusa.crawl(login_url, options)
      Medusa.crawl(login_url, options)

      expect(login).to have_been_requested.twice
      expect(first_private).to have_been_requested.once
      expect(second_private).to have_been_requested.once
    end

    it 'rejects the same unsupported cache configuration as HTTP' do
      page = FakePage.new('invalid-cache')

      expect { Medusa.crawl(page.url, http_cache: Object.new) }.to raise_error(ArgumentError, /http_cache/)
    end

    RSpec.shared_examples_for "crawl" do
      it "should crawl all the html pages in a domain by following <a> href's" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'])
        pages << FakePage.new('1', :links => ['3'])
        pages << FakePage.new('2')
        pages << FakePage.new('3')

        expect(Medusa.crawl(pages[0].url, opts).pages.size).to eq(4)
      end

      it "should not follow links that leave the original domain" do
        pages = []
        pages << FakePage.new('0', :links => ['1'], :hrefs => 'http://www.other.com/')
        pages << FakePage.new('1')

        core = Medusa.crawl(pages[0].url, opts)

        expect(core.pages.size).to eq(2)
        expect(core.pages.keys).not_to include('http://www.other.com/')
      end

      it "should not follow redirects that leave the original domain" do
        pages = []
        pages << FakePage.new('0', :links => ['1'], :redirect => 'http://www.other.com/')
        pages << FakePage.new('1')

        core = Medusa.crawl(pages[0].url, opts)

        expect(core.pages.size).to eq(2)
        expect(core.pages.keys).not_to include('http://www.other.com/')
      end

      it "should follow http redirects" do
        pages = []
        pages << FakePage.new('0', :links => ['1'])
        pages << FakePage.new('1', :redirect => '2')
        pages << FakePage.new('2')

        expect(Medusa.crawl(pages[0].url, opts).pages.size).to eq(3)
      end

      it "should follow with HTTP basic authentication" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'], :auth => true)
        pages << FakePage.new('1', :links => ['3'], :auth => true)
        pages << FakePage.new('2', :auth => true)
        pages << FakePage.new('3', :auth => true)

        new_opts = opts.merge({:http_basic_authentication => AUTH})
        expect(Medusa.crawl(pages.first.url, new_opts).pages.size).to eq(4)
      end

      it "should accept multiple starting URLs" do
        pages = []
        pages << FakePage.new('0', :links => ['1'])
        pages << FakePage.new('1')
        pages << FakePage.new('2', :links => ['3'])
        pages << FakePage.new('3')

        expect(Medusa.crawl([pages[0].url, pages[2].url], opts).pages.size).to eq(4)
      end

      it "should include the query string when following links" do
        pages = []
        pages << FakePage.new('0', :links => ['1?foo=1'])
        pages << FakePage.new('1?foo=1')
        pages << FakePage.new('1')

        core = Medusa.crawl(pages[0].url, opts)

        expect(core.pages.size).to eq(2)
        expect(core.pages.keys).not_to include(pages[2].url)
      end

      it "should be able to skip links with query strings" do
        pages = []
        pages << FakePage.new('0', :links => ['1?foo=1', '2'])
        pages << FakePage.new('1?foo=1')
        pages << FakePage.new('2')

        core = Medusa.crawl(pages[0].url, opts) do |a|
          a.skip_query_strings = true
        end

        expect(core.pages.size).to eq(2)
      end

      it 'skips links based on a RegEx' do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'])
        pages << FakePage.new('1')
        pages << FakePage.new('2', :links => ['4?skip-me=no', '4?example=1&skip-me=yes'])
        pages << FakePage.new('3')
        pages << FakePage.new('4?skip-me=no')
        pages << FakePage.new('4?example=1&skip-me=yes')


        core = Medusa.crawl(pages[0].url, opts) do |a|
          a.skip_links_like(/1/, /3/, /skip-me=yes/)
        end

        expect(core.pages.size).to eq(3)
        expect(core.pages.keys).not_to include(pages[1].url)
        expect(core.pages.keys).not_to include(pages[3].url)
        expect(core.pages.keys).not_to include(pages[5].url)
      end

      it "should be able to call a block on every page" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'])
        pages << FakePage.new('1')
        pages << FakePage.new('2')

        count = 0
        Medusa.crawl(pages[0].url, opts) do |a|
          a.on_every_page { count += 1 }
        end

        expect(count).to eq(3)
      end

      it "should not discard page bodies by default" do
        Medusa.crawl(FakePage.new('0').url, opts).pages.values#.first.doc.should_not be_nil
      end

      it "should provide a focus_crawl method to select the links on each page to follow" do
        pages = []
        pages << FakePage.new('0', :links => ['1', '2'])
        pages << FakePage.new('1')
        pages << FakePage.new('2')

        core = Medusa.crawl(pages[0].url, opts) do |a|
          a.focus_crawl {|p| p.links.reject{|l| l.to_s =~ /1/}}
        end

        expect(core.pages.size).to eq(2)
        expect(core.pages.keys).not_to include(pages[1].url)
      end

      it "should optionally delay between page requests" do
        delay = 0.25
        expect_any_instance_of(Tentacle).to receive(:sleep).with(delay).twice

        pages = []
        pages << FakePage.new('0', :links => '1')
        pages << FakePage.new('1')

        core = Medusa.crawl(pages[0].url, opts.merge({:delay => delay}))
        expect(core.pages.size).to eq(2)
      end

      it "should optionally obey the robots exclusion protocol" do
        pages = []
        pages << FakePage.new('0', :links => '1')
        pages << FakePage.new('1')
        pages << FakePage.new('robots.txt', body: "User-agent: *\nDisallow: /1", content_type: 'text/plain')
        core = Medusa.crawl(pages[0].url, opts.merge(obey_robots_txt: true))

        expect(core.pages.keys).to include(pages[0].url)
        expect(core.pages.keys).not_to include(pages[1].url)
      end

      it "should be able to set cookies to send with HTTP requests" do
        cookies = {:a => '1', :b => '2'}
        core = Medusa.crawl(FakePage.new('0').url) do |medusa|
          medusa.cookies = cookies
        end
        expect(core.opts[:cookies]).to eq(cookies)
      end

      it "should freeze the options once the crawl begins" do
        core = Medusa.crawl(FakePage.new('0').url) do |medusa|
          medusa.threads = 4
          medusa.on_every_page do
            expect{ medusa.threads = 2 }.to raise_error(RuntimeError)
          end
        end
        expect(core.opts[:threads]).to eq(4)
      end

      describe "many pages" do
        before(:each) do
          @pages, size = [], 5

          size.times do |n|
            # register this page with a link to the next page
            link = (n + 1).to_s if n + 1 < size
            @pages << FakePage.new(n.to_s, :links => Array(link))
          end
        end

        it "should track the page depth and referer" do
          core = Medusa.crawl(@pages[0].url, opts)
          previous_page = nil

          @pages.each_with_index do |page, i|
            page = core.pages[page.url]
            expect(page.depth).to eq(i)

            if previous_page
              expect(page.referer).to eq(previous_page.url)
            else
              expect(page.referer).to be_nil
            end
            previous_page = page
          end
        end

        it "should optionally limit the depth of the crawl" do
          core = Medusa.crawl(@pages[0].url, opts.merge({:depth_limit => 3}))
          expect(core.pages.size).to eq(4)
        end
      end

    end

    context 'using the default storage' do
      let(:opts) { Hash.new }

      it_should_behave_like "crawl"
    end

    describe "options" do
      before(:each) do
        FakePage.new
        FakePage.new('robots.txt', body: "User-agent: *\nDisallow: /1", content_type: 'text/plain')
      end

      it "should accept options for the crawl" do
        core = Medusa.crawl(SPEC_DOMAIN, :threads => 2,
                                          :discard_page_bodies => true,
                                          :user_agent => 'test',
                                          :obey_robots_txt => true,
                                          :depth_limit => 3)

        expect(core.opts[:threads]).to eq(2)
        expect(core.opts[:discard_page_bodies]).to eq(true)
        expect(core.opts[:delay]).to eq(0)
        expect(core.opts[:user_agent]).to eq('test')
        expect(core.opts[:obey_robots_txt]).to eq(true)
        expect(core.opts[:depth_limit]).to eq(3)
      end

      it "should accept options via setter methods in the crawl block" do
        core = Medusa.crawl(SPEC_DOMAIN) do |a|
          a.threads = 2
          a.discard_page_bodies = true
          a.user_agent = 'test'
          a.obey_robots_txt = true
          a.depth_limit = 3
        end

        expect(core.opts[:threads]).to eq(2)
        expect(core.opts[:discard_page_bodies]).to eq(true)
        expect(core.opts[:delay]).to eq(0)
        expect(core.opts[:user_agent]).to eq('test')
        expect(core.opts[:obey_robots_txt]).to eq(true)
        expect(core.opts[:depth_limit]).to eq(3)
      end

      it "should use 1 thread if a delay is requested" do
        allow_any_instance_of(Tentacle).to receive(:sleep)
        expect(Medusa.crawl(SPEC_DOMAIN, :delay => 1, :threads => 2).opts[:threads]).to be(1)
      end
    end

  end
end
