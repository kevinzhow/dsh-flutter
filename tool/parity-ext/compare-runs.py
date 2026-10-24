#!/usr/bin/env python3
"""Compare two parity runs (summary.json files) per group: mean scores, pass counts and the cases that got worse.

  tool/parity-ext/compare-runs.py --before core:<dir>,ext:<dir> --after core:<dir>,ext:<dir> [--worse 1.0]

A group is `<suite>: <area>` (the second id segment, `components.button.*` -> `button`). Cases are matched by capture key;
captures present on one side only are listed apart (new cases). `exact` is the vendored CLI's pixel-perfect %, `non-text`
dsh's geometry score; `pass` counts the CLI's statuses same / pass / basic pass (> 96% exact). Prints Markdown.
"""
import argparse
import collections
import json
import pathlib


def load(spec):
    out = {}
    for item in spec.split(','):
        suite, path = item.split(':', 1)
        data = json.loads((pathlib.Path(path) / 'summary.json').read_text())
        for row in data['cases']:
            if 'pixelPerfectPct' in row:
                out[(suite, row['key'])] = row
    return out


def passing(row):
    return row['status'] in ('same', 'pass', 'basic-pass')


def group(key):
    suite, k = key
    return '%s: %s' % (suite, k.split('.')[1])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--before', required=True)
    ap.add_argument('--after', required=True)
    ap.add_argument('--worse', type=float, default=1.0, help='list cases whose exact %% dropped by more than this (default 1.0)')
    args = ap.parse_args()
    before, after = load(args.before), load(args.after)
    both = sorted(set(before) & set(after))
    groups = collections.defaultdict(list)
    for k in both:
        groups[group(k)].append(k)
    mean = lambda rows, f: sum(r[f] for r in rows) / len(rows)
    print('| group | n | exact % before | after | non-text % before | after | pass before | after |')
    print('|---|---:|---:|---:|---:|---:|---:|---:|')
    tot_b, tot_a = [], []
    for g in sorted(groups):
        b = [before[k] for k in groups[g]]
        a = [after[k] for k in groups[g]]
        tot_b += b
        tot_a += a
        print('| %s | %d | %.2f | %.2f | %.2f | %.2f | %d | %d |' % (
            g, len(b), mean(b, 'pixelPerfectPct'), mean(a, 'pixelPerfectPct'), mean(b, 'nonTextPct'), mean(a, 'nonTextPct'),
            sum(map(passing, b)), sum(map(passing, a))))
    print('| **all** | %d | **%.2f** | **%.2f** | **%.2f** | **%.2f** | **%d** | **%d** |' % (
        len(tot_b), mean(tot_b, 'pixelPerfectPct'), mean(tot_a, 'pixelPerfectPct'), mean(tot_b, 'nonTextPct'),
        mean(tot_a, 'nonTextPct'), sum(map(passing, tot_b)), sum(map(passing, tot_a))))
    worse = sorted(((after[k]['pixelPerfectPct'] - before[k]['pixelPerfectPct'], k) for k in both
                    if before[k]['pixelPerfectPct'] - after[k]['pixelPerfectPct'] > args.worse))
    print('\nCases whose exact %% dropped by more than %.1f points (%d of %d):' % (args.worse, len(worse), len(both)))
    for d, k in worse:
        print('- `%s` %.2f -> %.2f (%+.2f)' % (k[1], before[k]['pixelPerfectPct'], after[k]['pixelPerfectPct'], d))
    new = sorted(set(after) - set(before))
    if new:
        print('\nCaptures only in the after run (%d):' % len(new))
        for k in new:
            print('- `%s` %.2f exact, %.2f non-text, %s' % (k[1], after[k]['pixelPerfectPct'], after[k]['nonTextPct'], after[k]['status']))
    gone = sorted(set(before) - set(after))
    if gone:
        print('\nCaptures only in the before run: %d' % len(gone))


if __name__ == '__main__':
    main()
