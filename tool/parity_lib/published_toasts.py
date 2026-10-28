"""Actual published Toast source provider for only toast.source.

The existing generic provider, cache, selected keys and comparison pipeline are
unchanged. Dedicated source runs are retained under the normal output directory;
only their explicitly selected images/metadata are copied into shared results.
"""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile

from PIL import Image

from . import env, manifest

KIND = 'toast.source'


def prepare_archive():
    """Use the existing credential-free public archive verifier/cache policy."""
    path = env.ROOT / 'tool/design-system/verify_release_inputs.py'
    spec = importlib.util.spec_from_file_location('toast_provider_release', path)
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    lock = json.loads((env.ROOT / 'tool/design-system/sources.lock.json').read_text())
    package = next(p for p in lock['packages'] if p['name'] == '@deepseek-ai/dsh-client-ui-primitives')
    cache = Path(os.environ.get('PARITY_SOURCE_ARCHIVES', env.ROOT / '.local/release-input-archives'))
    offline = os.environ.get('PARITY_SOURCE_ARCHIVES_OFFLINE') == '1'
    verifier.ensure_archive(package, cache, offline=offline)
    return cache


def selected_manifest(entries):
    cases = {}
    for entry in entries:
        case, variant = entry['case'], entry['variant']
        if case['kind'] != KIND or entry['key'] != manifest.capture_key(case['id'], variant['id']):
            raise ValueError('published Toast provider received an unrelated/misidentified entry')
        selected = cases.setdefault(case['id'], {**case, 'variants': []})
        if any(v['id'] == variant['id'] for v in selected['variants']):
            raise ValueError('duplicate published Toast variant')
        selected['variants'].append(variant)
    return {'schema': 'dsh-parity-cases/1', 'name': 'selected-published-toasts', 'cases': list(cases.values())}


def capture(entries, out, results, reference):
    from . import react
    if reference not in react.REFERENCE_MODES:
        raise ValueError('unknown published Toast reference mode')
    plan = selected_manifest(entries)
    react.check_dsh_checkout()
    log = out / 'published-toasts.log'
    react.setup(log)
    archives = prepare_archive()
    work = Path(tempfile.mkdtemp(prefix='published-toasts-', dir=out))
    plan_path, source = work / 'cases.json', work / 'source'
    plan_path.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + '\n')
    script = env.ROOT / 'tool/design-system/capture-toasts.mjs'
    code = react.run_node(
        ['node', script, '--repo', env.ROOT, '--archives', archives, '--plan', plan_path,
         '--out', source, '--reference', reference], env.ROOT, log,
        extra_env={'DSH_SRC': str(env.dsh_src()), 'PARITY_WEB_DEPS': str(env.web_deps())})
    if code != 0:
        raise SystemExit('published Toast source capture failed; output retained at ' + str(work))
    trace_path = source / 'source-trace.json'
    if not trace_path.is_file():
        raise ValueError('published Toast source completed without a receipt; output retained at ' + str(work))
    trace = json.loads(trace_path.read_text())
    expected = {e['key']: e for e in entries}
    rows = trace.get('traces', [])
    if (trace.get('passed') is not True or trace.get('captures') != len(entries)
            or len(rows) != len(expected) or {r['key'] for r in rows} != set(expected)):
        raise ValueError('published Toast source receipt does not cover the exact selected entry set')
    reference_dir = source / 'visual-testing-results/react'
    if {p.name for p in reference_dir.iterdir()} != {
            key + suffix for key in expected for suffix in ('.png', '.metadata.json')}:
        raise ValueError('published Toast source output set differs from selected keys')
    pin = json.loads((env.ROOT / 'tool/design-system/sources.lock.json').read_text())['referenceCommit']
    copies = []
    for row in rows:
        key, entry = row['key'], expected[row['key']]
        png, meta = reference_dir / (key + '.png'), reference_dir / (key + '.metadata.json')
        if (not row.get('checks') or any(c.get('passed') is not True for c in row['checks'])
                or env.sha256_file(png) != row.get('sha256')):
            raise ValueError('published Toast source checks or actual PNG hash differ')
        with Image.open(png) as image:
            if image.format != 'PNG':
                raise ValueError('published Toast source image is not a PNG')
            image.load()
        metadata = json.loads(meta.read_text())
        if (metadata.get('provider') != 'react' or metadata.get('captureKey') != key
                or metadata.get('caseId') != entry['case']['id'] or metadata.get('variantId') != entry['variant']['id']
                or metadata.get('react', {}).get('dshCommit') != pin or metadata.get('pixelModel') != reference):
            raise ValueError('published Toast source metadata differs from the selected entry/reference')
        copies.extend([(png, key + '.png'), (meta, key + '.metadata.json')])
    # No shared result is modified until the entire new-family set validates.
    destination = results / 'react'
    destination.mkdir(parents=True, exist_ok=True)
    for source_file, name in copies:
        shutil.copy2(source_file, destination / name)
    (work / 'provider-receipt.json').write_text(json.dumps({
        'schema': 'dsh-published-toast-provider/1', 'reference': reference,
        'selectedKeys': list(expected), 'sourceTraceSha256': env.sha256_file(trace_path),
        'planSha256': env.sha256_file(plan_path), 'kind': KIND, 'genericCacheUsed': False,
        'sourceBodiesOrStylesRewritten': False}, indent=2) + '\n')
    return {key: 'captured' for key in expected}
