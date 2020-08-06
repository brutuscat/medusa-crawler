# Medusa: a ruby crawler framework ![Ruby](https://github.com/brutuscat/medusa-crawler/workflows/Ruby/badge.svg?event=push)

Medusa is a framework to crawl and collect useful information about the pages it visits. It is versatile, allowing you to write your own specialized tasks quickly and easily.


## Features

- Choose the links to follow on each page with `focus_crawl()`
- Multi-threaded design for high performance
- Tracks 301 HTTP redirects
- Allows exclusion of URLs based on regular expressions
- HTTPS support
- Records response time for each page
- Obey robots.txt
- In-memory or persistent storage of pages during crawl using [Moneta](https://github.com/moneta-rb/moneta) adapters
- Inherits OpenURI behavior (redirects, automatic charset and encoding detection, proxy configuration options).

## Examples

See the scripts under the <tt>lib/Medusa/cli</tt> directory for examples of several useful Medusa tasks.

## TODO

- [x] Simplify storage module using [Moneta](https://github.com/minad/moneta)
- [x] Add multiverse of ruby versions and runtimes in test suite
- [ ] Solve memory issues with a persistent Queue
- [ ] Improve docs & examples
- [ ] Allow to control the crawler, eg: "stop", "resume"
- [ ] Improve logging facilities to collect stats, catch errors & failures
- [ ] Add the concept of "bots" or drivers to interact with pages (eg: capybara)

**Do you have an idea? [Open an issue so we can discuss it](https://github.com/brutuscat/medusa-crawler/issues/new)**

## Requirements

 - moneta
 - nokogiri
 - robotex

## Development

To test and develop this gem, additional requirements are:
 - rspec
 - webmock

## Disclaimer

Medusa is a revamped version of the defunk anemone gem.
