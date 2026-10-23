#!/usr/bin/env python3
"""Bucket the differing pixels of each parity case by likely cause and rank the causes by leverage.

  tool/parity-ext/analyze-diffs.py [--out build/parity-ext] [--cases GLOB] [--viz DIR] [--json FILE]

Reads any parity output tree (`<out>/visual-testing-results/{react,flutter}/<key>.png`), so it works for
the core suite too (`--out build/parity`). Buckets are defined in tool/parity_lib/diffmetrics.py (fill,
hairline, corner, offset, text, other). For each case and bucket the report gives the exact % the case
would reach if that bucket's pixels matched: it ranks the systematic causes. Never iterate on the `text`
bucket (Chromium vs Skia glyph anti-aliasing); fix geometry, colour, spacing, borders and radii.
`--viz DIR` writes React | Flutter | bucket-map images.
"""
import argparse
import fnmatch
import json
import pathlib
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from parity_lib import diffmetrics as dm, env  # noqa: E402
from parity_lib.compose import side_by_side  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', default=str(env.ROOT / 'build' / 'parity-ext'))
    ap.add_argument('--cases', default='*')
    ap.add_argument('--viz')
    ap.add_argument('--json')
    args = ap.parse_args()
    results = pathlib.Path(args.out) / 'visual-testing-results'
    rows = []
    for react_png in sorted((results / 'react').glob('*.png')):
        key = react_png.stem
        flutter_png = results / 'flutter' / react_png.name
        if not flutter_png.is_file() or not any(fnmatch.fnmatchcase(key, p) for p in args.cases.split(',')):
            continue
        meta = json.loads((results / 'react' / ('%s.metadata.json' % key)).read_text())
        density = meta['viewport']['density']
        res, label, rp, fp = dm.compare_files(react_png, flutter_png, density)
        total = res['pixels']
        score_if = {b: round(100.0 * (1 - (res['mismatched'] - res['buckets'][b]) / total), 3) for b in dm.BUCKETS}
        rows.append({'key': key, 'exactPct': res['exactPct'], 'nonTextPct': res['nonTextPct'], 'buckets': res['buckets'],
                     'exactIfBucketMatched': score_if})
        if args.viz:
            viz = pathlib.Path(args.viz)
            viz.mkdir(parents=True, exist_ok=True)
            side_by_side(rp.astype('uint8'), fp.astype('uint8'), dm.diff_visual(rp, label), key).save(viz / ('%s.png' % key))
    print('%-58s %8s %8s  %s' % ('case', 'exact %', 'nontext %', '  '.join('%8s' % b for b in dm.BUCKETS)))
    for r in rows:
        print('%-58s %8.2f %8.2f  %s' % (r['key'][:58], r['exactPct'], r['nonTextPct'], '  '.join('%8d' % r['buckets'][b] for b in dm.BUCKETS)))
    if rows:
        totals = {b: sum(r['buckets'][b] for r in rows) for b in dm.BUCKETS}
        print('\nmismatching pixels by bucket over %d captures: %s' % (len(rows), ', '.join('%s %d' % kv for kv in totals.items())))
        print('highest leverage first: %s' % ', '.join(b for b, _ in sorted(totals.items(), key=lambda kv: -kv[1]) if b != 'text'))
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(rows, indent=1) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
