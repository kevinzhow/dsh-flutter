"""Offline self-checks of the parity tool: `tool/parity selftest` (tool/preflight runs it as `parity`).

Exit 0 = ok, 1 = a check failed, 2 = skipped because numpy/Pillow or the vendored CLI's dependency (`tool/parity
setup`, Node + sharp) are not installed. Nothing here needs the dsh checkout, a browser or Flutter: it checks the
committed manifest (dsh schema and the vendored CLI's validation), the font pins, the extension builders, the
vendored CLI's diff on synthetic images, the dsh bucket metrics and that the generated Flutter case map is fresh.
"""
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile

from . import env, fonts, manifest as mf, vt


def _check(name, fn, results):
    try:
        detail = fn()
        results.append((name, True, detail or ''))
    except Exception as exc:  # noqa: BLE001 - a self-test reports every failure
        results.append((name, False, '%s: %s' % (type(exc).__name__, exc)))


def core_manifest():
    man = mf.load_manifest(env.SHARED / 'cases.json')
    return '%d cases, %d captures' % (len(man['cases']), len(mf.entries(man)))


def vendored_validate():
    """The vendored CLI accepts the flattened core manifest and rejects a broken one."""
    man = mf.load_manifest(env.SHARED / 'cases.json')
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        text = vt.validate(mf.entries(man), tmp)
        broken = vt.cli_cases(mf.entries(man))[:1]
        broken[0]['viewport'] = {'width': 10}
        path = tmp / 'broken.json'
        path.write_text(json.dumps({'cases': broken}))
        try:
            vt.run_cli(['validate', '--manifest', str(path)], tmp)
        except vt.CliError:
            return text.strip().splitlines()[-1]
        raise AssertionError('the vendored CLI accepted a case without a viewport size')


def vendored_diff():
    """Provider contract end to end on synthetic captures: identical -> same, one moved column -> different."""
    import numpy as np
    from PIL import Image
    from . import pipeline
    with tempfile.TemporaryDirectory() as tmp:
        out = pathlib.Path(tmp)
        case = {'id': 'components.selftest.box.a.light', 'title': 'Box', 'kind': 'selftest.box', 'theme': 'light', 'locale': 'en',
                'viewport': {'width': 40, 'height': 20, 'density': 1}, 'variants': [{'id': 'default', 'name': 'Default'}]}
        entries = mf.entries({'cases': [case, {**case, 'id': 'components.selftest.box.b.light'}]})
        img = np.full((20, 40, 3), 255, np.uint8)
        img[4:16, 6:34] = (20, 20, 200)
        for provider in (vt.BASELINE, vt.CURRENT):
            (out / 'visual-testing-results' / provider).mkdir(parents=True)
        for key, other in (('components.selftest.box.a.light', img), ('components.selftest.box.b.light', np.roll(img, 1, axis=1))):
            Image.fromarray(img).save(out / 'visual-testing-results' / vt.BASELINE / ('%s.png' % key))
            Image.fromarray(other).save(out / 'visual-testing-results' / vt.CURRENT / ('%s.png' % key))
        rows = pipeline.compare(entries, out, out / 'visual-testing-results')
        same, moved = rows
        assert same['officialStatus'] == 'same' and same['pixelPerfectPct'] == 100.0 and same['status'] == 'same', same
        assert moved['officialStatus'] != 'same' and moved['pixelPerfectPct'] < 100.0 and moved['nonTextPct'] < 100.0, moved
        assert (out / 'visual-testing-results' / 'diff' / vt.PAIR / ('%s.side-by-side.png' % same['key'])).is_file()
    return 'same=%.1f%% moved=%.2f%%' % (same['pixelPerfectPct'], moved['pixelPerfectPct'])


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
    assert res['exactPct'] == 100.0 and res['nonTextPct'] == 100.0, res
    moved = np.roll(img, 1, axis=1)
    res = dm.compare_arrays(img, moved, 1.0)[0]
    assert res['exactPct'] < 100.0 and res['nonTextPct'] < 100.0, res
    assert res['buckets']['text'] == 0, res
    small = img.copy()
    small[0, 0] = (254, 255, 255)
    res = dm.compare_arrays(img, small, 1.0)[0]
    assert res['closePct'] == 100.0 and res['exactPct'] < 100.0, res
    return 'ok'


def reference_modes():
    """The React cache key follows the reference mode for a density above 1 only, and emulated keys are the old ones."""
    from . import react
    base = {'dsh': 'x'}

    def key(density, reference):
        entry = {'key': 'k', 'case': {'viewport': {'width': 1, 'height': 1, 'density': density}}, 'variant': {'id': 'default'}}
        return react.entry_key(entry, 'f', base, reference)

    assert key(1, 'native') == key(1, 'emulated'), 'density 1 must not depend on the mode'
    assert key(2, 'native') != key(2, 'emulated') and key(2.625, 'native') != key(3, 'native')
    assert react.DEFAULT_REFERENCE == 'native'
    return 'native default; density 1 shared, emulated keys unchanged'


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
                     ('diff-metrics', diff_metrics), ('reference-modes', reference_modes),
                     ('case-map', case_map_fresh)):
        _check(name, fn, results)
    skipped = not vt.ready()
    if not skipped:
        for name, fn in (('vendored-validate', vendored_validate), ('vendored-diff', vendored_diff)):
            _check(name, fn, results)
    for name, ok, detail in results:
        print('%-18s %s  %s' % (name, 'ok  ' if ok else 'FAIL', detail))
    failed = [n for n, ok, _ in results if not ok]
    if skipped:
        print('%-18s skip  node or the vendored CLI dependency is missing (tool/parity setup)' % 'vendored-*')
    print('parity selftest: %s' % ('FAILED ' + ','.join(failed) if failed else ('skipped vendored CLI checks' if skipped else 'ok')))
    return 1 if failed else (2 if skipped else 0)
