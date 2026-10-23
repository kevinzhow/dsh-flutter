"""Verify the pinned parity fonts (tool/parity-fonts/manifest.json) against their sha256."""
from __future__ import annotations

import json

from . import env


def load():
    return json.loads((env.FONTS / 'manifest.json').read_text())


def check():
    """-> list of problems (empty = every pinned file is present and matches)."""
    manifest = load()
    problems = []
    for family in manifest['families']:
        for face in family['faces']:
            path = env.FONTS / face['file']
            if not path.is_file():
                problems.append('%s missing' % path)
            elif env.sha256_file(path) != face['sha256']:
                problems.append('%s: sha256 does not match manifest' % path)
    for name in [manifest['licenseFile']] + [f['licenseFile'] for f in manifest['families'] if 'licenseFile' in f]:
        if not (env.FONTS / name).is_file():
            problems.append('license file %s missing' % name)
    for family in manifest['families']:
        if 'charset' in family and not (env.FONTS / family['charset']).is_file():
            problems.append('charset file %s missing' % family['charset'])
    return problems


def cjk_charset():
    """-> the set of characters the pinned CJK subset covers (cjk-charset.txt)."""
    return set((env.FONTS / 'cjk-charset.txt').read_text().strip('\n'))


def uncovered_cjk(text):
    """-> characters of [text] above U+2000 that the pinned CJK subset has no glyph for (a case error: the React
    provider would fall back to a system font and the Flutter provider to a missing glyph)."""
    covered = cjk_charset()
    return sorted({ch for ch in text if ord(ch) > 0x2000 and ch not in covered and not ch.isspace()})
