#!/usr/bin/env python3
"""Where does a line of text put its baseline: Chromium against Flutter, for dsh's type ladder (numpy + Pillow).

  tool/parity-ext/text-baseline-sweep.py [--out DIR] [--dprs 1,1.5,2,2.625,3] [--quick]

Draws "HHHH" (flat-topped, flat-bottomed capitals: the bottom edge of the ink is the baseline) for every pair of
font size and line height in the sweep, with the pinned parity fonts (Noto Sans as the text font, Noto Sans Mono as the
code font; regular and bold), once in Chromium (Playwright, the flags of the parity capture) and twice in Flutter: as a
plain `Text` with dsh's text style, and as `DshChromeText`. Then it measures the bottom edge of the ink in every block
and prints, per density, how many baselines the two Flutter variants put where Chromium does (within 0.3 device px).

The sweep behind docs/parity.md ("The text baseline"): 24 size/line-height pairs x 2 weights x 2 families x 5
densities = 480 baselines. `--quick` runs the 14 pairs of the type ladder at 1x and 2x.
Working files go to --out (default $TMPDIR/dsh-text-baseline).
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from parity_lib import env  # noqa: E402

LADDER = [(16, 24), (20, 28), (16, 28), (12, 20), (14, 22), (24, 32), (13, 20), (12, 18), (11, 14)]
EXTRA = [(14, 24), (13, 24), (15, 24), (14, 20), (15, 22), (17, 26), (18, 26), (18, 28), (21, 30), (19, 28), (10, 14),
         (13, 18), (14, 18), (16, 22), (12, 16), (12, 15), (11, 15), (12, 14), (13, 15), (16, 19)]


def edges(image, row, pitch, dpr):
    """Bottom and top edge (device px from the block's top) of the ink of one block, with fractional coverage."""
    y0, y1 = int(round(row * pitch * dpr)), int(round((row + 1) * pitch * dpr))
    profile = (255 - image[y0:y1].astype(float)).sum(1)
    stem = np.median(profile[profile > 0])
    full = np.where(profile >= 0.8 * stem)[0]
    last, first = full.max(), full.min()
    bottom = last + 1 + (min(profile[last + 1] / stem, 1) if last + 1 < len(profile) else 0)
    top = first - (min(profile[first - 1] / stem, 1) if first > 0 else 0)
    return top, bottom


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', default=str(pathlib.Path(os.environ.get('TMPDIR', tempfile.gettempdir())) / 'dsh-text-baseline'))
    ap.add_argument('--dprs', default='1,1.5,2,2.625,3')
    ap.add_argument('--quick', action='store_true')
    args = ap.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    dprs = [float(d) if '.' in d else int(d) for d in args.dprs.split(',')]
    combos = LADDER + ([] if args.quick else EXTRA)
    if args.quick:
        dprs = [1, 2]
    (out / 'combos.json').write_text(json.dumps({
        'combos': combos, 'dprs': dprs, 'weights': [400] if args.quick else [400, 700],
        'families': ['Segoe UI'] if args.quick else ['Segoe UI', 'SF Mono']}))

    subprocess.run(['node', str(env.EXT / 'probes' / 'text-baseline.mjs'), str(out), str(env.FONTS)],
                   env={**env.node_env(), 'PARITY_WEB_DEPS': str(env.web_deps())}, check=True)
    fenv = env.flutter_env()
    fenv['TEXT_BASELINE_SWEEP_DIR'] = str(out)
    subprocess.run(['nice', '-n', '15', 'flutter', 'test', 'test/text_baseline_sweep_test.dart'],
                   cwd=env.FLUTTER_PKG, env=fenv, check=True, stdout=subprocess.DEVNULL)

    meta = json.loads((out / 'rows.json').read_text())
    rows, pitch = meta['rows'], meta['pitch']
    print('baseline of "HHHH", Flutter minus Chromium, device px; "ok" = within 0.3 (%d blocks per density)' % len(rows))
    print('%-8s %-14s %-14s' % ('density', 'plain Text', 'DshChromeText'))
    for dpr in dprs:
        chromium = np.array(Image.open(out / ('chromium-dpr%s.png' % dpr)).convert('L'))
        cells = []
        for variant in ('plain', 'dsh'):
            flutter = np.array(Image.open(out / ('flutter-%s-dpr%s.png' % (variant, dpr))).convert('L'))
            delta = np.array([edges(flutter, i, pitch, dpr)[1] - edges(chromium, i, pitch, dpr)[1] for i in range(len(rows))])
            cells.append('%d/%d ok' % ((abs(delta) < 0.3).sum(), len(rows)))
            if variant == 'plain':
                off = sorted({'%d/%d%+.0f' % (rows[i]['size'], rows[i]['line'], d / dpr) for i, d in enumerate(delta) if abs(d) >= 0.3})
        print('%-8s %-14s %-14s plain Text is off for (size/line, CSS px): %s' % (dpr, cells[0], cells[1], ' '.join(off)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
