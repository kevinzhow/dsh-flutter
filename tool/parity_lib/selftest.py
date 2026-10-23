"""Offline self-checks of the parity tool: `tool/parity selftest` (tool/preflight runs it as `parity`).

Exit 0 = ok, 1 = a check failed, 2 = skipped because numpy/Pillow are not installed. Nothing here
needs the dsh checkout, Node, a browser or Flutter: it checks the committed manifest, the font pins, the
extension builders, the diff metrics on synthetic images and that the generated Flutter case map is fresh.
"""
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile

from . import env, fonts, manifest as mf


def _check(name, fn, results):
    try:
        detail = fn()
        results.append((name, True, detail or ''))
    except Exception as exc:  # noqa: BLE001 - a self-test reports every failure
        results.append((name, False, '%s: %s' % (type(exc).__name__, exc)))


def core_manifest():
    man = mf.load_manifest(env.SHARED / 'cases.json')
    return '%d cases, %d captures' % (len(man['cases']), len(mf.entries(man)))


def font_pins():
    problems = fonts.check()
    if problems:
        raise AssertionError('; '.join(problems))
    return 'sha256 ok'


def ext_builders():
    from . import builders, sampling
    with tempfile.TemporaryDirectory() as tmp:
        path = builders.build_manifest(pathlib.Path(tmp), env.EXT)
        full = mf.load_manifest(path)
        sampled = sampling.sample_themes(full)
        errors = mf.validate_manifest(sampled)
        if errors:
            raise AssertionError('\n'.join(errors))
        core_ids = {c['id'] for c in mf.load_manifest(env.SHARED / 'cases.json')['cases']}
        clash = core_ids & {c['id'] for c in full['cases']}
        if clash:
            raise AssertionError('extension ids duplicate core ids: %s' % sorted(clash))
    return '%d cases (%d after theme sampling)' % (len(full['cases']), len(sampled['cases']))


def diff_metrics():
    import numpy as np
    from . import diffmetrics as dm
    img = np.full((40, 80, 3), 255, np.int16)
    img[8:32, 10:70] = (20, 20, 200)
    res = dm.compare_arrays(img, img.copy(), 1.0)[0]
    assert res['exactPct'] == 100.0 and res['verdict'] == 'same', res
    moved = np.roll(img, 1, axis=1)
    res = dm.compare_arrays(img, moved, 1.0)[0]
    assert res['exactPct'] < 100.0 and res['nonTextPct'] < 100.0, res
    assert res['buckets']['text'] == 0, res
    small = img.copy()
    small[0, 0] = (254, 255, 255)
    res = dm.compare_arrays(img, small, 1.0)[0]
    assert res['closePct'] == 100.0 and res['exactPct'] < 100.0 and res['verdict'] == 'pass', res
    return 'ok'


def case_map_fresh():
    sys.path.insert(0, str(env.TOOL))
    import parity_case_map
    parity_case_map.generate()
    return 'regenerated tool/parity_flutter/test/parity/case_map.g.dart'


def run():
    try:
        import numpy  # noqa: F401
        import PIL  # noqa: F401
    except ImportError:
        print('parity selftest: skipped (pip install -r tool/parity-requirements.txt for numpy and Pillow)')
        return 2
    results = []
    for name, fn in (('core-manifest', core_manifest), ('font-pins', font_pins), ('ext-builders', ext_builders),
                     ('diff-metrics', diff_metrics), ('case-map', case_map_fresh)):
        _check(name, fn, results)
    for name, ok, detail in results:
        print('%-14s %s  %s' % (name, 'ok  ' if ok else 'FAIL', detail))
    failed = [n for n, ok, _ in results if not ok]
    print('parity selftest: %s' % ('FAILED ' + ','.join(failed) if failed else 'ok'))
    return 1 if failed else 0
