## Unreleased

## Pre-release v2.0.0.pre.4 (2026-09-17)

Features:
 - Add optional private HTTP caching with conditional revalidation, freshness, `Vary`, persistent Moneta stores, and diagnostics
 - Add runnable examples for form login, HTTP Basic authentication, linked file downloads, nested frames, broken images, linked category collection, and persistent incremental crawling

Fixes:
 - Share one thread-safe, standards-aware cookie session across all crawl workers
 - Preserve the pre-2.0 Hash-like CookieStore API while retaining scoped cookie attributes
 - Fix documentation example links and validate rendered documentation with Medusa in CI

Changes:
 - Use private Ruby `Data` value objects for internal HTTP responses and crawl work items
 - Raise supported runtime dependency floors for Moneta, Nokogiri, OpenStruct, and WEBrick, and add `http-cookie` for scoped cookie handling
 - Harden dependency and release CI with minimum-runtime and bleeding-edge dependency coverage, Bundler cooldown, SHA-pinned actions, and publishing gated on the full CI workflow

## Pre-release v2.0.0.pre.2 (2026-08-26)

Fixes:
 - Fix tag-version validation in the RubyGems publishing workflow

## Pre-release v2.0.0.pre.1 (2026-08-26)

Changes:
 - Require Ruby 3.3 or newer and test against Ruby 3.3, 3.4, and 4.0
 - Add explicit `ostruct` and `webrick` runtime dependencies for modern Ruby releases
 - Add trusted publishing to RubyGems through GitHub Actions
 - Add project guidance, roadmap, and agent-readable documentation

## Release v1.0.0 (2020-08-17)
Features:
- Remove `PageStore#pages_linking_to`, `PageStore#urls_linking_to`
- Remove `verbose` setting

Changes:
 - Add an examples section to the [README](https://github.com/brutuscat/medusa-crawler/blob/main/README.md) file
 - Update the [CONTRIBUTORS](https://github.com/brutuscat/medusa-crawler/blob/main/CONTRIBUTORS.mdd) file
 - Update the [CHANGELOG](https://github.com/brutuscat/medusa-crawler/blob/main/CHANGELOG.md) file

## Pre-release v1.0.0.pre.2
Features:
 - Remove CLI bins
 - Remove `PageStore#shortest_paths!`

Fixes
 - Skip link regex filter to consider the full URI [#1](https://github.com/brutuscat/medusa-crawler/issues/1)

## Pre-release v1.0.0.pre.1
Features:
 - Switch to use `Moneta` instead of custom storage provider adapters

Fixes
 - Fix link skip regex to include the full URI [#1](https://github.com/brutuscat/medusa-crawler/issues/1)

Dev
 - Use webmock gem for testing

Changes:
 - Rename Medusa to medusa-crawler gem

## Anemone forked into Medusa (2014-12-13)
Features:
 - Switch to use `OpenURI` instead of `net/http`, gaining out of the box support for:
  - Http basic auth options
  - Proxy configuration options
  - Automatic string encoding detection based on charset
  - Connection read timeout option
  - Ability to control the RETRY_LIMIT upon connection errors

Changes:
 - Renamed Anemone to Medusa
 - Revamped the [README](https://github.com/brutuscat/medusa-crawler/blob/main/README.md) file
 - Revamped the [CHANGELOG](https://github.com/brutuscat/medusa-crawler/blob/main/CHANGELOG.md) file
 - Revamped the [CONTRIBUTORS](https://github.com/brutuscat/medusa-crawler/blob/main/CONTRIBUTORS.mdd) file

> Refer to the [Anemone changelog](https://github.com/chriskite/anemone/blob/next/CHANGELOG.rdoc) to go back to the past.
