# Runtime comparison against the live smoke container

See [the recorded PR29/PR30 comparison](RESULTS.md) for measurements and checks.

This benchmark compares an earlier checkout with the current checkout using
the same Ruby, bundle, container, URLs, and worker limits. It runs actual
OpenURI requests; WebMock is not loaded.

Start the same pinned image used by `.github/workflows/ruby.yml`:

```sh
docker run --detach --name medusa-runtime-bench --publish 127.0.0.1::5000 \
  gprestes/the-internet@sha256:205b8fc712747ea5fa1a0d54b01fa02d65e3f67a448c7a5c2aba65b211def171
docker port medusa-runtime-bench 5000/tcp
```

Use the reported port below. Wait until `/login` responds, install the current
checkout's bundle, and create an isolated baseline checkout. For the PR29/PR30
comparison the thread baseline is `fa2d3a7d48f37392a9f585d8c8e29365d2b94881`:

```sh
git worktree add --detach ../medusa-thread-baseline fa2d3a7d48f37392a9f585d8c8e29365d2b94881
python3 benchmark/compare.py --baseline ../medusa-thread-baseline \
  --base-url http://127.0.0.1:PORT --trials 5 --pages 240 \
  --output /tmp/medusa-runtime-trials.jsonl
docker stop medusa-runtime-bench
docker rm medusa-runtime-bench
```

The runner inherits the Ruby PATH and Bundler settings (including an external
`BUNDLE_LOCKFILE`, if used). Both versions resolve through the current
checkout's bundle; `MEDUSA_BENCH_SOURCE` changes only the loaded Medusa source.
It clears HTTP proxy variables for these loopback requests. It requires
Python 3 and the development bundle, without additional gems.

Each configuration gets one excluded warmup and five measured crawls in fresh
Ruby processes. Baseline/current order alternates between trials. Elapsed and
process CPU time cover crawl execution, callbacks, and storage, excluding Ruby
startup and the initial login. Output contains every trial, source commit,
result digest, timing, request count, peak active requests, and Ruby thread
counts. The console reports median elapsed times and their ratios. There is
no fixed timing threshold: local host load and the server can dominate results.

The two timed workloads use 240 distinct query URLs:

- Public: `/login`, `/checkboxes`, `/tables`, and `/large`.
- Private: `/secure`, using cookies from a real form login. The authenticated
  welcome text is compared because session flash banners can vary.

Both run at 1, 4, and 16 workers, from plain synchronous code and inside Async.
Separate small checks cover link discovery with traversal depths and redirect
hops with HTTP 404/500 responses. Every crawl checks:

- Exact URL/status results and matching result digests across both versions.
- Duplicate seed suppression, one callback per page on the caller thread,
  matching stored pages, and one `after_crawl` callback.
- Exact `URI.open` call count, peak active calls within the configured limit,
  zero active requests afterward, and all owned workers finished.
- Fiber requests overlap when more than one worker is available, and another
  Async task progresses when called from an Async context.

Ruby's synchronous Net::HTTP can create a persistent timeout helper thread,
including during login. Thread totals are reported separately from checking
owned worker cleanup. The JSON `requests` field counts `URI.open` invocations,
including Medusa's explicit retries. Net::HTTP can retry internally within one
invocation; this is not a wire-level GET counter. Peak active requests measure
simultaneous `URI.open` calls across response buffering, excluding Medusa retry
backoff; they do not imply simultaneous server application execution.

This is an HTTP crawler benchmark against a fast local server. It does not
measure browser rendering, remote network latency, or memory use. Run the live
smoke examples and the complete RSpec suite separately for broader correctness
coverage. To run one configuration directly:

```sh
bundle exec ruby benchmark/runtime.rb --base-url http://127.0.0.1:PORT \
  --workload private --pages 240 --workers 4 --context async
```
