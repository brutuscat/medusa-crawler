# Medusa

Medusa is a web spider framework that can spider a domain and collect useful
information about the pages it visits. It is versatile, allowing you to
write your own specialized spider tasks quickly and easily.


## Features
 - Multi-threaded design for high performance
 - Tracks 301 HTTP redirects
 - Built-in BFS algorithm for determining page depth
 - Allows exclusion of URLs based on regular expressions
 - Choose the links to follow on each page with focus_crawl()
 - HTTPS support
 - Records response time for each page
 - CLI program can list all pages in a domain, calculate page depths, and more
 - Obey robots.txt
 - In-memory or persistent storage of pages during crawl, using TokyoCabinet, SQLite3, MongoDB, or Redis
 - Inherits OpenURI behavior (redirects, automatic charset and encoding detection, proxy configuration options).

## Examples

See the scripts under the <tt>lib/Medusa/cli</tt> directory for examples of several useful Medusa tasks.

## Requirements

 - nokogiri
 - robots

## Development

To test and develop this gem, additional requirements are:
 - rspec
 - fakeweb
 - tokyocabinet
 - kyotocabinet-ruby
 - mongo
 - redis
 - sqlite3

You will need to have KyotoCabinet, [Tokyo Cabinet](http://fallabs.com/tokyocabinet/), [MongoDB](http://www.mongodb.org/), and [Redis](http://redis.io/) installed on your system and running.
