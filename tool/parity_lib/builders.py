"""Manifest builders of the extension suite.

`tool/parity-ext/run` generates the extension manifest at run time instead of committing it: every
tool/parity-ext/build-*.py is discovered automatically and executed (build-cases.py, when present, first;
then by the optional top-level `ORDER = n` constant of the builder, default 1000; then by file name).
Each builder amends the manifest at the path in $PARITY_EXT_MANIFEST. Builders import `manifest_path()`
and `append_cases()` from tool/parity-ext/builders_api.py, never a hard-coded path.
"""
from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys

DEFAULT_ORDER = 1000
FIRST_BUILDER = 'build-cases.py'
_ORDER_RE = re.compile(r'^ORDER\s*=\s*(-?\d+)\b', re.M)


def builder_order(path):
    m = _ORDER_RE.search(pathlib.Path(path).read_text())
    return int(m.group(1)) if m else DEFAULT_ORDER


def ordered_builders(ext):
    paths = sorted(pathlib.Path(ext).glob('build-*.py'), key=lambda p: p.name)
    first = [p for p in paths if p.name == FIRST_BUILDER]
    rest = sorted((p for p in paths if p.name != FIRST_BUILDER), key=lambda p: (builder_order(p), p.name))
    return [p.name for p in first + rest]


def build_manifest(out, ext, name='extension'):
    """Run every builder; returns the manifest path (<out>/cases.json)."""
    ext, out = pathlib.Path(ext), pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=True)
    target = out / 'cases.json'
    target.write_text('{"schema": "dsh-parity-cases/1", "name": "%s", "cases": []}\n' % name)
    env = {**os.environ, 'PARITY_EXT_MANIFEST': str(target)}
    log = out / 'builders.log'
    with open(log, 'w') as sink:
        for builder in ordered_builders(ext):
            r = subprocess.run([sys.executable, str(ext / builder)], cwd=ext.parents[1], env=env,
                               stdout=sink, stderr=subprocess.STDOUT)
            if r.returncode != 0:
                sys.exit('builder %s failed (exit %d); see %s' % (builder, r.returncode, log))
    return target
