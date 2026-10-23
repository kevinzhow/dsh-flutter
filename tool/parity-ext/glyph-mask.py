#!/usr/bin/env python3
"""Layout agreement of a parity case with the glyphs masked out (numpy + Pillow).

  tool/parity-ext/glyph-mask.py [--out build/parity-ext] [--cases GLOB] [--max-height 40] [--viz DIR]

Chromium and Skia rasterise glyphs differently, and the `non-text` score only forgives dense ink: the stems of glyphs
are long thin edges, so the geometry buckets (`hairline`, `offset`) still count them (docs/parity.md, "Reading a
text-heavy case"). This tool answers a narrower question for such cases: do the two captures agree everywhere that is
not a glyph? A glyph is an ink component (5x5 luminance range >= 60 in either capture, merged across 2px) no taller
than --max-height device pixels, plus a 3px margin; icons, pictures, cards and badges are taller and stay in the score.
`--viz DIR` writes the mismatches as red outside the glyph mask (black where a channel differs by more than 8) and
green inside it.

Reads `<out>/visual-testing-results/{react,flutter}/<key>.png` like analyze-diffs.py; both rasters are flattened on
white and the smaller is padded with white, as the scoring does.
"""
import argparse
import fnmatch
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from parity_lib import diffmetrics as dm  # noqa: E402


def components(mask):
    """Label the 8-connected components of `mask` (labels start at 1)."""
    h, w = mask.shape
    labels = np.zeros((h, w), np.int32)
    count = 0
    for y0, x0 in zip(*np.nonzero(mask)):
        if labels[y0, x0]:
            continue
        count += 1
        labels[y0, x0] = count
        stack = [(y0, x0)]
        while stack:
            y, x = stack.pop()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not labels[yy, xx]:
                        labels[yy, xx] = count
                        stack.append((yy, xx))
    return labels, count


def analyse(react_png, flutter_png, max_height):
    r, f = dm.load_rgb(react_png), dm.load_rgb(flutter_png)
    h, w = max(r.shape[0], f.shape[0]), max(r.shape[1], f.shape[1])
    r, f = dm.pad_to(r, h, w), dm.pad_to(f, h, w)
    mismatch = (r != f).any(-1)
    ink = (dm._range5(dm.luminance(r)) >= 60) | (dm._range5(dm.luminance(f)) >= 60)
    labels, count = components(dm.dilate(ink, 2))
    glyphs = np.zeros((h, w), bool)
    for i in range(1, count + 1):
        ys, _ = np.nonzero(labels == i)
        if ys.max() - ys.min() + 1 <= max_height:
            glyphs |= labels == i
    glyphs = dm.dilate(glyphs, 3)
    outside = mismatch & ~glyphs
    big = np.abs(r - f).max(-1) > 8
    return {
        'exact': 100 * (1 - mismatch.sum() / mismatch.size),
        'outside': 100 * (1 - outside.sum() / mismatch.size),
        'mismatch': int(mismatch.sum()), 'outsideMismatch': int(outside.sum()), 'outsideBig': int((outside & big).sum()),
    }, (r, mismatch, glyphs, big)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', default='build/parity-ext')
    ap.add_argument('--cases', default='*')
    ap.add_argument('--max-height', type=int, default=40)
    ap.add_argument('--viz')
    args = ap.parse_args()
    root = pathlib.Path(args.out) / 'visual-testing-results'
    print('%-62s %8s %13s %10s %9s' % ('case', 'exact %', 'outside-glyph %', 'mismatch', 'outside'))
    for flutter in sorted((root / 'flutter').glob('*.png')):
        key = flutter.stem
        if not fnmatch.fnmatch(key, args.cases) or not (root / 'react' / (key + '.png')).exists():
            continue
        result, (react, mismatch, glyphs, big) = analyse(root / 'react' / (key + '.png'), flutter, args.max_height)
        print('%-62s %8.2f %13.2f %10d %9d' % (key, result['exact'], result['outside'], result['mismatch'],
                                               result['outsideMismatch']))
        if args.viz:
            vis = (react // 2 + 127).astype(np.uint8)
            vis[mismatch & glyphs] = (0, 160, 0)
            vis[mismatch & ~glyphs] = (255, 0, 0)
            vis[mismatch & ~glyphs & big] = (0, 0, 0)
            out = pathlib.Path(args.viz)
            out.mkdir(parents=True, exist_ok=True)
            Image.fromarray(vis).save(out / (key + '.png'))


if __name__ == '__main__':
    main()
