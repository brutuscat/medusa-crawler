# Medusa Roadmap

## 2.0 - Project revival

- Support the current maintained Ruby releases.
- Restore a green CI matrix and update build tooling.
- Update dependencies and gem packaging where required.
- Refresh the README, examples, changelog, and gem metadata.
- Add contributor and agent guidance.
- Launch a proper Medusa project website with getting started, API documentation, examples, RubyGems/source links, Markdown-friendly documentation, and `llms.txt`.
- Preserve the Medusa 1 crawl model and public API where practical.

## 2.1 - Concurrency

- Replace thread-based fetch concurrency with Fiber-scheduler-compatible concurrency.
- Replace thread-specific queue and completion bookkeeping with scheduler-aware primitives and explicit outstanding-work tracking.
- Keep `Medusa.crawl` synchronous from the caller's perspective.
- Keep page processing and user callbacks serialized initially.
- Introduce `concurrency:` and retain `threads:` as a deprecated compatibility alias.
- Add deterministic delayed-I/O tests for concurrent fetching and crawl completion.

## 2.2 - Crawl controls and examples

- Add missing reusable crawl bounds and controls where justified.
- Expand examples for modern programmatic crawling and downstream document processing.
- Improve agent-readable documentation without adding agent or AI dependencies to the core gem.

## 2.3 - Incremental crawling

- Add conditional HTTP requests using ETag and Last-Modified metadata.
- Handle `304 Not Modified` efficiently.
- Expose freshness metadata needed by revisit workflows.
- Add examples for comparing successive crawl results.

## Later 2.x

- Refine the 2.x APIs based on real use.
- Ship replacement APIs before removing deprecated ones.
- Publish a concise migration guide for planned 3.0 removals.
- Keep 3.0-ready application code working on the final 2.x release.

## 3.0 - Compatibility cleanup

- Remove deprecated APIs with established replacements.
- Make intentional breaking changes that could not be delivered compatibly in 2.x.
