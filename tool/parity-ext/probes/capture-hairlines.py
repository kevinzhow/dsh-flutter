#!/usr/bin/env python3
"""How thick is the outline button's hairline in the React captures: native density against emulated density.

  tool/parity-ext/probes/capture-hairlines.py <native-out> <emulated-out> [case-id ...]

Reads `visual-testing-results/react/<case>.png` of two runs of `tool/parity run` (`--reference native` and
`--reference emulated`) and measures, on the outline button's top edge (`0.5px solid` `--dsw-alias-border-l3`, light:
`#e0e0e0` over white), how many device pixel rows the line is thick. Blink at a native density snaps a `0.5px` border to
one device pixel; with an emulated density it lays out in CSS pixels and the line is one CSS pixel (2 device px at 2x, 3
at 2.625x and 3x). The default cases are the button variants at 2x, 2.625x and 3x. The `densityMode` of each capture's
metadata (the page's own `devicePixelRatio` and computed border widths) is printed next to the measurement.
"""
import json
import pathlib
import sys

import numpy as np
from PIL import Image

CASES = ['components.button.variants.md-2x.light', 'components.button.variants.md-2p625x.light',
         'components.button.variants.md-3x.light']


def thickness(png):
    a = np.array(Image.open(png).convert('L')).astype(int)
    line = (a >= 215) & (a <= 235)
    rows = np.where(line.sum(1) >= a.shape[1] // 12)[0]     # a long run of the border grey: the button's top/bottom edge
    if not len(rows):
        return None
    groups, run = [], [rows[0]]
    for y in rows[1:]:
        if y == run[-1] + 1:
            run.append(y)
        else:
            groups.append(run)
            run = [y]
    groups.append(run)
    return len(groups[0])


def main(argv):
    native, emulated = (pathlib.Path(p) / 'visual-testing-results' / 'react' for p in argv[:2])
    cases = argv[2:] or CASES
    print('%-46s %-9s %-24s %s' % ('case', 'mode', 'outline top edge', 'page proof (dpr, 0.5px, 1px computed border)'))
    for case in cases:
        for mode, d in (('emulated', emulated), ('native', native)):
            meta = json.loads((d / ('%s.metadata.json' % case)).read_text())
            proof = meta['react']['densityMode']
            n = thickness(d / ('%s.png' % case))
            dpr = proof['devicePixelRatio']
            print('%-46s %-9s %d device px = %.2f CSS px   %s, %s, %s' % (
                case, mode, n, n / dpr, dpr, proof['border0.5px'], proof['border1px']))


if __name__ == '__main__':
    main(sys.argv[1:])
