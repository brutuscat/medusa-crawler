require 'medusa'
require 'optparse'
require 'ostruct'

options = OpenStruct.new
options.relative = false

begin
  # make sure that the last option is a URL we can crawl
  root = URI(ARGV.last)
rescue
  puts <<-INFO
Usage:
  medusa url-list [options] <url>

Synopsis:
  Crawls a site starting at the given URL, and outputs the URL of each page
  in the domain as they are encountered.

Options:
  -r, --relative      Output relative URLs (rather than absolute)
INFO
  exit(0)
end

# parse command-line options
opts = OptionParser.new
opts.on('-r', '--relative') { options.relative = true }
opts.parse!(ARGV)

Medusa.crawl(root, :discard_page_bodies => true) do |medusa|

  medusa.on_every_page do |page|
    if options.relative
      puts page.url.path
    else
      puts page.url
    end
  end

end
