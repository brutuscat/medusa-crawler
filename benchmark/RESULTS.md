# PR29 threads versus PR30 fibers

Measured on 2026-10-10 against the unmodified, pinned CI smoke container.
The fiber runtime preserves the tested crawl results and concurrency limits.
Throughput is close: four-worker crawls are roughly 5–8% faster in this run,
while the complete set ranges from about 3% slower to 10% faster. The sample
ranges overlap in many configurations; these are local measurements, not a
general speedup guarantee. Fibers avoid creating Ruby worker threads.

## Method

- Thread source: `fa2d3a7d48f37392a9f585d8c8e29365d2b94881` (PR29).
- Fiber source: `dc0f37fe386cce1c2907cb8153b079923153e8c6` (PR30).
- Ruby 3.3.9, Async 2.46.0, identical bundle for both sources.
- Image: `gprestes/the-internet@sha256:205b8fc712747ea5fa1a0d54b01fa02d65e3f67a448c7a5c2aba65b211def171`.
- 240 pages per timed crawl, default Moneta memory storage, HTTP cache disabled.
- Five fresh-process samples per configuration, after one excluded warmup;
  version order alternates. Timings exclude process startup and initial login.
- 120 measured crawls, 24 warmups, and eight separate correctness crawls:
  **152 crawls and 34,596 `URI.open` invocations**, all checks passed.

The delivery containing this report adds only the benchmark and its records;
the measured runtime source is unchanged. See [README](README.md) to rerun and
[results.json](results.json) for individual timing samples and counters.

## Timings

Seconds are median elapsed time, followed by the observed minimum–maximum
across five samples. Speedup is thread median / fiber median; above 1 favors
fibers. Public and private workload definitions are in the README.

| Workload | Caller | Workers | Threads, seconds (range) | Fibers, seconds (range) | Speedup |
|---|---|---:|---:|---:|---:|
| public | plain | 1 | 1.138 (1.112–1.268) | 1.088 (1.081–1.200) | 1.05× |
| public | async | 1 | 1.298 (1.223–1.353) | 1.185 (1.135–1.333) | 1.10× |
| public | plain | 4 | 1.000 (0.959–1.063) | 0.956 (0.946–1.082) | 1.05× |
| public | async | 4 | 1.043 (0.971–1.119) | 0.982 (0.979–1.010) | 1.06× |
| public | plain | 16 | 1.022 (0.998–1.042) | 0.983 (0.966–1.006) | 1.04× |
| public | async | 16 | 1.071 (1.034–1.142) | 1.107 (1.037–1.174) | 0.97× |
| private | plain | 1 | 0.730 (0.726–0.844) | 0.719 (0.686–0.769) | 1.02× |
| private | async | 1 | 0.781 (0.729–0.811) | 0.788 (0.728–0.841) | 0.99× |
| private | plain | 4 | 0.629 (0.605–0.674) | 0.584 (0.566–0.606) | 1.08× |
| private | async | 4 | 0.645 (0.644–0.716) | 0.610 (0.595–0.640) | 1.06× |
| private | plain | 16 | 0.647 (0.602–0.674) | 0.597 (0.586–0.617) | 1.08× |
| private | async | 16 | 0.633 (0.609–0.696) | 0.605 (0.566–0.718) | 1.05× |

## Correctness and concurrency

**PASS:** Both sources produce identical result digests in every configuration.
Public digests include full response bodies; private digests compare the stable
authenticated welcome text, excluding variable session flash banners. Exact
URL/status sets, duplicate suppression, stored pages, traversal depths, redirect
hops, HTTP 404/500 responses, caller-thread callbacks, and `after_crawl` counts
all pass. Every configured pool contains the requested number of workers;
every crawl returns with zero active calls and all owned workers finished.

**PASS:** Both sources reach peaks of exactly 1, 4, and 16 active `URI.open`
calls in the corresponding timed configurations, never exceeding those limits.
The fiber version works from synchronous code and within Async, where a sibling
task progresses during the crawl. These client-side overlaps do not imply
parallel execution inside the container application.

| Configured workers | Public: thread version peak Ruby threads | Public: fiber version peak Ruby threads |
|---:|---:|---:|
| 1 | 3 | 1 |
| 4 | 6 | 1 |
| 16 | 18 | 1 |

Totals include the caller thread and, for the thread version, Net::HTTP's
timeout helper. The private workload's initial synchronous login creates that
helper in both versions; its fiber total is therefore two. Owned crawler
workers are checked independently from this helper.

**PASS:** `MEDUSA_LIVE_SMOKE=1 MEDUSA_SMOKE_BASE_URL=http://127.0.0.1:32768
bundle exec rspec spec/examples --tag smoke`: five examples, zero failures on
each source. This covers login, Basic Auth, downloads, images, and nested frames.
The baseline invocation explicitly loads its own `lib/medusa/core.rb` while
using the shared bundle.

**PASS:** `bundle exec rspec spec` on the fiber source: 168 examples, zero
failures (seed 3663), including delayed local HTTP, timeout/retry scheduling,
cancellation, callback/worker failures, and cleanup coverage.

Reviewed under agent-dev-workflow, with a separate read-only benchmark review.
No blocking findings remain. The `requests` JSON counter counts OpenURI calls;
Net::HTTP can retry internally within one call. Remote network performance,
memory use, and statistical significance were not measured. Use the documented
240-page batch for the timing/progress probe; very short crawls can finish
before its 1 ms sibling-task timer fires.
