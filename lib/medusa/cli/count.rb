require 'medusa'

begin
  # make sure that the first option is a URL we can crawl
  url = URI(ARGV[0])
rescue
  puts <<-INFO
Usage:
  medusa count <url>

Synopsis:
  Crawls a site starting at the given URL and outputs the total number
  of unique pages on the site.
INFO
  exit(0)
end

Medusa.crawl(url) do |medusa|
  medusa.after_crawl do |pages|
    puts pages.uniq!.size
  end
end
