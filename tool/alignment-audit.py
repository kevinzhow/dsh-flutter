#!/usr/bin/env python3
"""Alignment audit: where do strong vertical edges and text starts sit in the React and Flutter captures?

  tool/alignment-audit.py run --root build/parity [--root build/parity-ext] [--cases GLOB] [--out DIR]
  tool/alignment-audit.py show --root build/parity --case <key> --out overlay.png
  tool/alignment-audit.py selftest

For each case with both captures it reports offsets in CSS px (device px / density):
  * vertical edges: columns where many rows change colour horizontally (button sides, borders, dividers)
    are matched React -> Flutter by nearest position;
  * text starts: for each band of rows that holds glyph ink, the first ink column.
An offset within 0.75 CSS px counts as aligned; up to 12 px it is reported as an offset; beyond that the layout
differs (the edges are not the same edges). `--root` is a parity output directory; results go to `--out`
(default build/alignment) and never into the root. A near-miss that exceeds the tolerance but is not a layout
difference is exactly what to fix: it moves whole pixels, unlike glyph anti-aliasing.
"""
import argparse
import fnmatch
import json
import pathlib
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import numpy as np  # noqa: E402
from parity_lib import diffmetrics as dm, env  # noqa: E402

ALIGNED = 0.75
LAYOUT = 12.0


def vertical_edges(img, density):
    """Columns (device px) with a straight run of colour changes to the next column: >= 8 CSS px and >= 25% of the rows."""
    changed = (img[:, 1:] != img[:, :-1]).any(-1)
    longest = dm.run_length(changed, 0).max(0)
    need = max(8 * density, 0.25 * img.shape[0])
    cols = np.flatnonzero(longest >= need)
    groups, last = [], None
    for c in cols:                      # merge adjacent columns into one edge (anti-aliased or thick borders)
        if last is not None and c - last <= 1:
            groups[-1].append(c)
        else:
            groups.append([c])
        last = c
    return [float(np.mean(g)) + 0.5 for g in groups]


def text_starts(img, density):
    """First ink column of each band of rows with glyph-like ink (device px)."""
    lum = dm.luminance(img)
    ink = dm._range5(lum) >= dm.INK_RANGE  # noqa: SLF001
    rows = ink.any(1)
    bands, start = [], None
    for y, on in enumerate(list(rows) + [False]):
        if on and start is None:
            start = y
        elif not on and start is not None:
            if y - start >= 3 * density:
                bands.append((start, y))
            start = None
    out = []
    for y0, y1 in bands:
        cols = np.flatnonzero(ink[y0:y1].any(0))
        if cols.size:
            out.append(float(cols[0]))
    return out


def audit_pair(react_rgb, flutter_rgb, density):
    findings = []
    re_, fe = vertical_edges(react_rgb, density), vertical_edges(flutter_rgb, density)
    for x in re_:
        if not fe:
            findings.append({'what': 'edge', 'react': round(x / density, 2), 'flutter': None, 'offset': None, 'verdict': 'missing'})
            continue
        nearest = min(fe, key=lambda f: abs(f - x))
        off = (nearest - x) / density
        findings.append({'what': 'edge', 'react': round(x / density, 2), 'flutter': round(nearest / density, 2),
                         'offset': round(off, 2), 'verdict': classify(off)})
    rt, ft = text_starts(react_rgb, density), text_starts(flutter_rgb, density)
    if len(rt) == len(ft):
        for i, (a, b) in enumerate(zip(rt, ft)):
            off = (b - a) / density
            findings.append({'what': 'text-start[%d]' % i, 'react': round(a / density, 2), 'flutter': round(b / density, 2),
                             'offset': round(off, 2), 'verdict': classify(off)})
    else:
        findings.append({'what': 'text-bands', 'react': len(rt), 'flutter': len(ft), 'offset': None, 'verdict': 'layout'})
    return findings


def classify(offset):
    if abs(offset) <= ALIGNED:
        return 'aligned'
    return 'offset' if abs(offset) <= LAYOUT else 'layout'


def cases(roots, pattern):
    for root in roots:
        results = pathlib.Path(root) / 'visual-testing-results'
        for react_png in sorted((results / 'react').glob('*.png')):
            flutter_png = results / 'flutter' / react_png.name
            if flutter_png.is_file() and any(fnmatch.fnmatchcase(react_png.stem, p) for p in pattern.split(',')):
                meta = json.loads((results / 'react' / ('%s.metadata.json' % react_png.stem)).read_text())
                yield react_png.stem, react_png, flutter_png, meta['viewport']['density']


def cmd_run(args):
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    report, flagged = {}, 0
    for key, rp, fp, density in cases(args.root, args.cases):
        findings = audit_pair(dm.load_rgb(rp), dm.load_rgb(fp), density)
        report[key] = findings
        bad = [f for f in findings if f['verdict'] != 'aligned']
        flagged += bool(bad)
        print('%-56s %s' % (key, 'aligned' if not bad else '; '.join('%s %s%s' % (f['what'], f['verdict'], '' if f['offset'] is None else ' %+.2f' % f['offset']) for f in bad[:4])))
    (out / 'alignment.json').write_text(json.dumps(report, indent=1) + '\n')
    print('%d cases, %d with edges or text starts off by more than %.2f CSS px -> %s' % (len(report), flagged, ALIGNED, out / 'alignment.json'))
    return 0


def cmd_show(args):
    for key, rp, fp, density in cases(args.root, args.case):
        r, f = dm.load_rgb(rp), dm.load_rgb(fp)
        h, w = max(r.shape[0], f.shape[0]), max(r.shape[1], f.shape[1])
        r, f = dm.pad_to(r, h, w), dm.pad_to(f, h, w)
        overlay = (r // 2 + f // 2).astype('uint8')
        for x in vertical_edges(r, density):
            overlay[:, int(x), :] = (255, 0, 0)
        for x in vertical_edges(f, density):
            overlay[:, int(x), :] = (0, 0, 255)
        from PIL import Image
        Image.fromarray(overlay).resize((w * 3, h * 3), Image.NEAREST).save(args.out)
        print('overlay of %s -> %s (red: React edges, blue: Flutter edges)' % (key, args.out))
        return 0
    sys.exit('case %s not found with both captures' % args.case)


def cmd_selftest(_args):
    base = np.full((40, 100, 3), 255, np.int16)
    base[8:32, 20:70] = (20, 20, 20)
    shifted = np.roll(base, 3, axis=1)
    same = audit_pair(base, base.copy(), 1.0)
    assert all(f['verdict'] == 'aligned' for f in same), same
    moved = audit_pair(base, shifted, 1.0)
    assert any(f['verdict'] == 'offset' and abs(f['offset'] - 3) < 0.01 for f in moved), moved
    assert classify(0.5) == 'aligned' and classify(5) == 'offset' and classify(40) == 'layout'
    print('alignment-audit selftest: ok')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    run = sub.add_parser('run')
    run.add_argument('--root', action='append', default=[])
    run.add_argument('--cases', default='*')
    run.add_argument('--out', default=str(env.ROOT / 'build' / 'alignment'))
    show = sub.add_parser('show')
    show.add_argument('--root', action='append', default=[])
    show.add_argument('--case', required=True)
    show.add_argument('--out', required=True)
    sub.add_parser('selftest')
    args = ap.parse_args()
    if args.cmd != 'selftest' and not args.root:
        args.root = [str(env.ROOT / 'build' / 'parity'), str(env.ROOT / 'build' / 'parity-ext')]
    return {'run': cmd_run, 'show': cmd_show, 'selftest': cmd_selftest}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
