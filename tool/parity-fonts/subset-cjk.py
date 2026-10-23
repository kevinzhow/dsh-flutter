#!/usr/bin/env python3
"""Rebuild the pinned Noto Sans CJK SC subset (files/NotoSansCJKsc-{Regular,Bold}.subset.otf) from the installed
Debian/Ubuntu package fonts-noto-cjk (1:20240730+repack1-1build1, upstream Noto Sans CJK 2.004).

  python3 subset-cjk.py [--ttc-dir /usr/share/fonts/opentype/noto] [--out files]

Needs fontTools (`pip install fonttools`, used only by this script, never at run time). The glyph set is the charset
file cjk-charset.txt: the 3000 most frequent GB 2312 hanzi (frequency order of the hz6763 table), the CJK symbols and
punctuation (U+3000-303F), the fullwidth forms (U+FF01-FF5E), a few general punctuation marks and every non-ASCII
character of dsh's conversation dictionary. Hinting and layout tables are dropped (the providers draw without hinting
and the cases need no shaping features), the face (index 2 of the collection, "Noto Sans CJK SC") is otherwise
unchanged. After a rebuild, update the sha256 values in manifest.json (`tool/parity fonts` verifies them).
"""
import argparse
import hashlib
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTCollection, TTFont

SC_INDEX = 2


def main():
    here = pathlib.Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--ttc-dir', default='/usr/share/fonts/opentype/noto')
    ap.add_argument('--out', default=str(here / 'files'))
    args = ap.parse_args()
    text = (here / 'cjk-charset.txt').read_text().strip('\n')
    for weight in ('Regular', 'Bold'):
        source = pathlib.Path(args.ttc_dir) / ('NotoSansCJK-%s.ttc' % weight)
        font = TTCollection(str(source), recalcTimestamp=False).fonts[SC_INDEX]
        name = font['name'].getDebugName(1)
        if 'CJK SC' not in name:
            sys.exit('%s: face %d is %r, not Noto Sans CJK SC' % (source, SC_INDEX, name))
        options = subset.Options()
        options.hinting = False
        options.layout_features = []
        options.notdef_outline = True
        options.name_IDs = ['*']
        subsetter = subset.Subsetter(options)
        subsetter.populate(text=text)
        subsetter.subset(font)
        target = pathlib.Path(args.out) / ('NotoSansCJKsc-%s.subset.otf' % weight)
        font.save(str(target))
        print(target.name, target.stat().st_size, hashlib.sha256(target.read_bytes()).hexdigest())


if __name__ == '__main__':
    main()
