# Agent Notes

Medusa is a small programmable web crawler for Ruby. It is not a browser automation framework, scraping platform, distributed crawler, or AI framework.

## Goals

- Keep the implementation small, readable, and Ruby-like.
- Preserve the simple `Medusa.crawl` entry point and block-based crawl control.
- Keep URL discovery, fetching, page representation, and storage easy to reason about.
- Keep storage replaceable and in-memory use lightweight.
- Preserve correct crawl semantics before optimizing throughput. A faster crawler must not silently duplicate visits, skip eligible URLs, terminate early, or change callback behavior.
- Keep network behavior explicit and configurable: redirects, cookies, authentication, proxies, robots.txt, retries, timeouts, and crawl delay.

## Quality Rules

- Prefer the smallest clear design that solves the problem.
- Do not introduce fragile special cases, dead code, speculative abstractions, or dependencies without a concrete need.
- Comment crawler mechanics when URL identity, redirect behavior, completion, storage lifetime, or ordering is not obvious from the local code.
- Keep public APIs narrow. Application-specific extraction, indexing, browser automation, and AI integrations belong outside the crawler core.
- Preserve one clear release path. Diagnostic switches are fine; permanent semantic variants behind flags are not.

## Safety

- Treat the public crawl DSL and callback behavior as compatibility-sensitive.
- Do not infer crawl completion from timing or a momentarily empty queue.
- Do not assume user-provided blocks are thread-safe, non-blocking, or side-effect free.
- Keep tests deterministic. Do not depend on external websites when a local server or WebMock can exercise the behavior.

## Layout

- `lib/medusa/core.rb`: crawl orchestration, link selection, callbacks, and completion.
- `lib/medusa/tentacle.rb`: fetch worker.
- `lib/medusa/http.rb`: HTTP requests, redirects, cookies, retries, and response timing.
- `lib/medusa/page.rb`: page representation and link extraction.
- `lib/medusa/page_store.rb`: page lookup and stored crawl state.
- `lib/medusa/storage/`: storage abstraction and adapters.
- `spec/`: unit and integration tests.

This list is not complete; check the code for details.

## Testing

Use `bundle exec rspec spec` for the full test suite.

When a change affects crawl control or HTTP behavior, add focused regression coverage for the behavior being changed. When a change affects concurrency, include a deterministic delayed-I/O test that proves requests overlap and that crawl completion and callback behavior remain correct.
