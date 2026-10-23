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
    if not (env.FONTS / manifest['licenseFile']).is_file():
        problems.append('license file %s missing' % manifest['licenseFile'])
    return problems
