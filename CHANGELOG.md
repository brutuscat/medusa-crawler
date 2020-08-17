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
