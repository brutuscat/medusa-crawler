#!/usr/bin/env python3
"""Compare two checkouts using one bundle and the same local smoke container."""

import argparse
import itertools
import json
import os
from pathlib import Path
import statistics
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--base-url', required=True)
    parser.add_argument('--trials', type=int, default=5)
    parser.add_argument('--pages', type=int, default=240)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.trials < 1 or args.pages < 1:
        parser.error('trials and pages must be positive')

    root = Path(__file__).resolve().parent.parent
    sources = {'threads': args.baseline.resolve(), 'fibers': root}
    env = os.environ.copy()
    for name in ('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy'):
        env.pop(name, None)
    # The bundle comes from root for BOTH sources. Only Medusa's lib/ differs.
    env['BUNDLE_GEMFILE'] = str(root / 'Gemfile')
    commits = {
        label: subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()
        for label, path in sources.items()
    }
    references = {}
    args.output.parent.mkdir(parents=True, exist_ok=True)

    with args.output.open('w') as output:
        def trial(label, workload, workers, context, phase, number):
            trial_env = dict(env, MEDUSA_BENCH_SOURCE=str(sources[label]))
            command = ['bundle', 'exec', 'ruby', str(root / 'benchmark/runtime.rb'),
                       '--base-url', args.base_url, '--pages', str(args.pages),
                       '--workers', str(workers), '--context', context, '--workload', workload]
            result = subprocess.run(command, cwd=root, env=trial_env, text=True,
                                    capture_output=True, timeout=120)
            if result.returncode:
                raise RuntimeError(f'{label}/{workload}/{workers}/{context}: {result.stderr}')
            record = json.loads(result.stdout)
            key = workload
            reference = references.setdefault(key, record['result_digest'])
            if record['result_digest'] != reference:
                raise RuntimeError(f'Result mismatch: {label}/{workload}/{workers}/{context}')
            record.update(variant=label, commit=commits[label], phase=phase, trial=number)
            output.write(json.dumps(record) + '\n')
            output.flush()
            return record

        # Check discovery/depths and redirect/error status semantics separately
        # from throughput; these tiny crawls are not performance samples.
        for workload, context, label in itertools.product(
                ('graph', 'redirects'), ('plain', 'async'), sources):
            trial(label, workload, 4, context, 'correctness', 0)
        print('Discovery, redirects, and HTTP error checks: PASS', flush=True)

        for workload, workers, context in itertools.product(
                ('public', 'private'), (1, 4, 16), ('plain', 'async')):
            for label in sources:
                trial(label, workload, workers, context, 'warmup', 0)
            samples = {label: [] for label in sources}
            for number in range(args.trials):
                # Alternate order to reduce systematic warmup/drift bias.
                labels = list(sources) if number % 2 == 0 else list(reversed(sources))
                for label in labels:
                    samples[label].append(trial(label, workload, workers, context, 'measure', number + 1))
            medians = {label: statistics.median(row['seconds'] for row in rows)
                       for label, rows in samples.items()}
            ratio = medians['threads'] / medians['fibers']
            print(f'{workload:7} {context:5} workers={workers:2}: '
                  f'threads={medians["threads"]:.3f}s fibers={medians["fibers"]:.3f}s '
                  f'speedup={ratio:.2f}x; all checks PASS', flush=True)


if __name__ == '__main__':
    main()
