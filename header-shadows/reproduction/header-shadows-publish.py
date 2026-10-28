#!/usr/bin/env python3
"""Stage completed Header/shadow evidence; no network, devices or Git writes.

All final checks, four builds, separate menu/Header GPU receipts, Android and
normal-app cleanup must exist before an atomic fresh stage can be created.
"""
from __future__ import annotations
import argparse
import ast
from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
BASE = '875ef6936bc5337afcc3a187b2de80ad22963ccb'
SOURCE = '687f282e8625c6b8d11ff58211a90524be2e4317'
MENU_MANIFEST = 'tool/parity-desktop/reported-families-cases.json'
HEADER_MANIFEST = 'tool/parity-desktop/header-leading-cases.json'
MENU_SHA = '556f7d56fb867fdc09cd4f4fd18865a2b9947736c9e3fb14094679383da648cf'
HEADER_SHA = '3b06e28f95438aca1fad9ccb2c7f48857a2e05e78d8ea8699ad7ee21333e1a30'
FAILED_RUNTIME = '2293a830c1edecc18d5e488e67493fd2e90f2d10'
ANDROID_SHA = '9d72dd09cf82451798454143f19160aabbd4e732b61f5dbfd7daecfd1098553d'
spec = importlib.util.spec_from_file_location('header_evidence_common', ROOT / 'scripts/menu-compositing-publish.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
require = common.require
LIMITS = [
    'The source-derived CSS blur conversion replaces a screenshot-fitted formula. The measured 108-pair non-text mean decreases; the original scores are retained and no font, classifier or threshold changes are permitted.',
    'Header native Chromium outline:auto raster/geometry remains unmatched, especially in dark mode. Correct focus visibility does not establish matching focus pixels.',
    'The shadow correction covers the current rounded translucent owner path. Authored opaque backgrounds, square-border hard exclusion, transforms and superellipse contours are not certified.',
    'Statistics composed backdrop sampling, native macOS vibrancy, model natural input line height, composer icon compaction, selection Toast and programmatic outside-focus dismissal remain unfinished.',
    'Header AppFrame/platform mounting, window traffic-light placement, cross-window blur/composition and aria-keyshortcuts mapping are outside this bounded component migration.',
    '895 existing numeric metric matches and 173 unretained UI CSS inputs remain. Source-input retention is not component implementation or state/visual acceptance.',
    'All images contain synthetic fixture data. No real user images, credentials or application request logs are included. No release, deployment or publication occurs in this script.',
]


def configure(repo):
    common.REPO = repo
    def git(*arguments, cwd=None):
        return subprocess.check_output(['git', *arguments], cwd=cwd or repo, text=True).strip()
    common.git = git
    return git


def gpu_receipt(folder, manifest_path, committed_path, runtime_head, fixture, final_head):
    """Every replay, manifest and compiled build must use the new final head."""
    data = common.load(folder / 'runtime.json')
    source_head = data.get('replaySourceHead', data.get('manifestCommit', data.get('runtimeHead')))
    require(source_head == runtime_head == final_head and runtime_head != FAILED_RUNTIME,
            'GPU proof must use the new exact final runtime; failed history is not acceptance')
    blob = subprocess.check_output(['git', 'show', source_head + ':' + committed_path], cwd=common.REPO)
    manifest = common.load(manifest_path)
    require(common.digest(manifest_path) == hashlib.sha256(blob).hexdigest() == data.get('manifestSha256')
            and json.loads(blob) == manifest
            and not common.git('diff', '--name-only', source_head, final_head, '--', committed_path),
            'GPU manifest differs from its committed replay source or final contract')
    require(not common.git('diff', '--name-only', runtime_head, source_head, '--', 'apps', 'features', 'packages'),
            'GPU replay source product differs from compiled runtime')
    require(data.get('status') == 'passed' and data.get('exitCode') == 0 and data.get('binaryUnchanged') is True
            and data.get('ownedPidsAbsent') is True and data.get('ownedFixturePidsRemaining') == []
            and data.get('runtimeHead') == runtime_head
            and data.get('runtimeTree') == common.git('rev-parse', runtime_head + '^{tree}')
            and data.get('executableSha256') == fixture['sha256']
            and data.get('applicationLibrarySha256') == fixture['applicationLibrarySha256'],
            'GPU build/replay/teardown proof incomplete')
    before, after = data.get('binaryBefore'), data.get('binaryAfter')
    require(isinstance(before, dict) and before == after and all(before.get(k) == data.get(k) for k in
            ('runtimeHead', 'runtimeTree', 'executableSha256', 'applicationLibrarySha256', 'manifestSha256')),
            'GPU before/after identity differs')
    cases = manifest['cases']
    require({p.parent.name for p in folder.glob('*/environment.json')} == {c['id'] for c in cases}
            and any(c['width'] < 600 for c in cases) and any(c['width'] >= 1024 for c in cases), 'GPU case coverage differs')
    rows = []
    for case in cases:
        directory = folder / common.name(case['id'])
        env = common.load(directory / 'environment.json')
        expected = [s['expect'] for s in case['app'] if 'expect' in s]
        actual = env.get('captureAssertions', [])
        require(expected and len(expected) == len(actual) and all(a.get('passed') is True
                and all(a.get(k) == v for k, v in e.items()) for a, e in zip(actual, expected)), 'GPU actual assertions incomplete')
        require(env.get('backend') == 'native-wayland' and env.get('pairedHost') is False
                and env.get('size') == [case['width'], case['height']] and env.get('appRenderDevices')
                and not re.search('llvmpipe|softpipe|swrast|software', env.get('renderer', ''), re.I), 'GPU hardware/viewport proof missing')
        pids = common.load(directory / 'pids.json')
        require(bool(pids), 'GPU owned PID record missing')
        for pid in pids.values():
            require(type(pid) is int and pid > 1, 'invalid GPU PID')
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                pass
            else:
                raise ValueError('recorded GPU PID still exists')
        shots = [s['capture'] for s in case['app'] if 'capture' in s]
        require(shots and len(shots) == len(set(shots)), 'GPU screenshots missing/duplicate')
        for shot in shots:
            common.png(directory / (common.name(shot) + '.png'))
        common.png(folder / (case['id'] + '.png'))
        rows.append({'case': case['id'], 'environment': env, 'captures': shots, 'assertions': len(actual)})
    return rows, data


def raw_identity(folder, runtime, repo, expected, tracked, previous):
    identity = common.load(folder / 'capture-identity.json')
    captured = identity.get('headAtCompletion', '')
    require(captured == runtime and runtime != FAILED_RUNTIME and identity.get('captured') == len(expected),
            'fresh captures from the exact new runtime required; prior captures are history only')
    require(identity.get('shadowSourceSha256') == tracked(repo / 'packages/dsh_ui/lib/src/dsh_shadow_box.dart'),
            'captured shadow implementation differs from runtime')
    require(identity.get('sourcePlanSha256') == tracked(previous / 'flutter-plan.json'), 'original source plan differs')
    for key in expected:
        path = folder / 'visual-testing-results/react' / (key + '.png')
        require(identity.get('sourcePngSha256', {}).get(key) == tracked(path), 'retained source PNG differs')
        require(tracked(path) == tracked(previous / 'visual-testing-results/react' / path.name),
                'current original-source image differs from retained reference')
        meta = common.load(path.with_suffix('.metadata.json'))
        require(meta.get('react', {}).get('dshCommit') == SOURCE, 'reference capture source pin differs')
    return identity


def header_pairs(folder, before, tracked, runtime=None):
    rows = common.load(folder / 'comparison.json')
    expected = {f'{theme}-dpr{density}-{state}' for theme in ('light', 'dark')
                for density in (1, 2) for state in ('idle', 'hover', 'pressed', 'focus')}
    require(len(rows) == 16 and {r.get('id') for r in rows} == expected, 'all sixteen Header comparisons required')
    if runtime is not None:
        identity = common.load(folder / 'capture-identity.json')
        require(identity.get('headAtCompletion') == runtime and runtime != FAILED_RUNTIME
                and identity.get('treeAtCompletion') == common.git('rev-parse', runtime + '^{tree}')
                and set(identity.get('flutterPngSha256', {})) == expected,
                'fresh exact-runtime Header capture identity required')
    source = common.load(folder / 'source-receipt.json')
    shots = [r for r in source.get('receipts', []) if r.get('file')]
    behavior = [r for r in source.get('receipts', []) if not r.get('file')]
    require(source.get('passed') is True and len(shots) == 16
            and {r['file'] for r in shots} == {'source-' + key + '.png' for key in expected}
            and len(behavior) == 4 and all(r.get('passed') is True for r in behavior)
            and {v.get('density') for v in source.get('chromiumVersions', [])} == {1, 2}
            and all(v.get('version') == '145.0.7632.6' for v in source.get('chromiumVersions', [])),
            'actual pinned Header browser proof missing')
    for row in rows:
        key = common.name(row['id'])
        a, b, old = (folder / ('source-' + key + '.png'), folder / ('flutter-' + key + '.png'),
                     before / ('flutter-' + key + '.png'))
        require(common.png(a) == common.png(b) == row['size'], 'Header pair dimensions differ')
        require(tracked(a) == row['sourceSha256'] and tracked(b) == row['flutterSha256'], 'Header raster hash differs')
        if runtime is not None:
            require(identity['flutterPngSha256'][key] == tracked(b), 'Header final capture identity hash differs')
        require(tracked(a) == tracked(before / a.name), 'original Header reference PNG differs')
        tracked(old)
        with Image.open(a) as ia, Image.open(b) as ib, Image.open(old) as prior:
            x, y, z = ia.convert('RGBA'), ib.convert('RGBA'), prior.convert('RGBA')
            require(y.size == z.size and y.tobytes() == z.tobytes()
                    and row.get('priorFlutterRGBAIdentical') is True, 'Header prior Flutter pixels changed')
            difference = ImageChops.difference(x, y)
            count = sum(any(pixel) for pixel in difference.getdata())
            maximum = max(high for _, high in difference.getextrema())
            require(count == row['sourceChangedPixels'] and maximum == row['sourceMaxChannelDifference'],
                    'Header comparison does not match actual raw pixels')
    return rows, source


def pixel_difference(first, second, rect):
    with Image.open(first) as a, Image.open(second) as b:
        require(a.size == b.size and len(rect) == 4 and all(type(n) is int for n in rect)
                and 0 <= rect[0] < rect[2] <= a.width and 0 <= rect[1] < rect[3] <= a.height,
                'source control comparison bounds invalid')
        difference = ImageChops.difference(a.convert('RGBA').crop(rect), b.convert('RGBA').crop(rect))
        return {'changedPixels': sum(any(p) for p in difference.getdata()),
                'maxChannelDifference': max(high for _, high in difference.getextrema())}


def menu_source_proof(folder, repo, source, tracked):
    """Verify actual Chromium positive/negative controls, separately from native acceptance."""
    proof = common.load(folder / 'source-controls/geometry.json')
    require(proof.get('passed') is True and proof.get('referenceCommit') == SOURCE
            and proof.get('chromiumVersion') == '145.0.7632.6'
            and proof.get('scriptSha256') == tracked(folder / 'capture-source.mjs')
            and proof.get('recipeSha256') == tracked(repo / 'tool/design-system/recipes.generated.json')
            and proof.get('themeSha256') == tracked(repo / 'packages/dsh_theme/assets/themes/official.theme.json'),
            'actual Chromium menu proof is incomplete or stale')
    lock = common.load(repo / 'tool/design-system/sources.lock.json')
    hashes = {path: value for package in lock['packages']
              for path, value in package.get('referenceSourceSha256', {}).items()}
    required_source = {
        'packages/client/ui-model-selection/src/client/ModelSelect.tsx',
        'packages/client/ui-model-selection/src/client/ModelSelect.module.css',
        'packages/client/ui-primitives/src/MenuSurface.tsx',
        'packages/client/ui-primitives/src/MenuSurface.module.css',
    }
    require(set(proof.get('sourceFiles', {})) == required_source, 'menu proof source scope differs')
    for path, row in proof['sourceFiles'].items():
        blob = subprocess.check_output(['git', 'show', SOURCE + ':' + path], cwd=source)
        require(hashlib.sha256(blob).hexdigest() == row['sha256'] == tracked(source / path)
                and row.get('matchedExplicitSourceLock') == (path in hashes), 'menu proof source fingerprint differs')
        if path in hashes:
            require(row['sha256'] == hashes[path], 'menu proof explicit source lock differs')
    pins = common.load(repo / 'tool/parity-fonts/manifest.json')
    faces = {f['file']: f for family in pins['families'] for f in family['faces']}
    require({r['file'] for r in proof.get('fontFaces', [])} == set(faces), 'menu proof font coverage differs')
    for row in proof['fontFaces']:
        file = (repo / 'tool/parity-fonts' / common.relative(row['file'])).resolve()
        require(row['sha256'] == tracked(file), 'menu proof font bytes differ')
    recipe = common.load(repo / 'tool/design-system/recipes.generated.json')['metrics']['DshModelMenuRecipe']
    require({c['id'] for c in proof.get('cases', [])} == {'desktop-light', 'phone-dark'}, 'menu proof source controls missing')
    manifest = common.load(repo / MENU_MANIFEST)
    for case in proof['cases']:
        key = common.name(case['id'])
        one, two = case['oneBounds'], case['twoBounds']
        row_height, padding = recipe['cellHeight'], recipe['padding']
        require(one['height'] == row_height + 2 * padding
                and two['height'] == 2 * row_height + 2 * padding
                and len(case['css']['rows']) == 1 and case['css']['rows'][0]['height'] == row_height,
                'source one-row/two-row geometry differs from generated recipe')
        layers = [[float(v.removesuffix('px')) for v in layer.strip().split()[:4]]
                  for layer in case['authoredShadow'].split(',')]
        reach = max(0, *(3 * blur / 2 + spread - y for _, y, blur, spread in layers))
        rect = case['sourceDerivedRect']
        require(case['upwardReach'] == reach < row_height and rect[1] == one['y'] - row_height
                and rect[3] == one['y'] - reach and two['x'] <= rect[0] < rect[2] <= two['x'] + two['width'],
                'menu assertion band is not derived from source geometry/shadow reach')
        require(any(s.get('expect', {}).get('rect') == rect and s['expect'].get('changed') is False
                    and s['expect'].get('reference') == 'model-pro-selected'
                    for c in manifest['cases'] for s in c['app']), 'source proof band absent from committed menu assertions')
        files = {name: folder / 'source-controls' / (key + '-' + name + '.png')
                 for name in ('closed', 'two-row-root', 'pro-selected', 'pro-root')}
        for path in files.values():
            common.png(path)
        correct = pixel_difference(files['pro-selected'], files['pro-root'], rect)
        wrong = pixel_difference(files['closed'], files['two-row-root'], rect)
        require(correct == case['correctOneRow'] and wrong == case['actualTwoRowControl']
                and correct['changedPixels'] == 0 and wrong['changedPixels'] > 0,
                'actual source positive/negative controls do not distinguish the extra row')
    history = common.load(folder / 'native-control-comparison.json')
    require(history.get('runtimeHead') == FAILED_RUNTIME and 'failed' in history.get('method', '').lower(),
            'historical native diagnostic must remain explicitly failed history')
    return proof


def android_expected_scenes(script):
    tree = ast.parse(script.read_text())
    replay = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'Replay')
    methods = {n.name: n for n in replay.body if isinstance(n, ast.FunctionDef)}
    order = [n.func.attr for n in ast.walk(methods['run']) if isinstance(n, ast.Call)
             and isinstance(n.func, ast.Attribute) and isinstance(n.func.value, ast.Name)
             and n.func.value.id == 'self' and n.func.attr in ('run_reported', 'run_header')]
    require(order == ['run_reported', 'run_header'], 'Android replay branch order differs')
    scenes = []
    for name, count in (('run_reported', 15), ('run_header', 8)):
        names = [n.args[0].value for n in ast.walk(methods[name]) if isinstance(n, ast.Call)
                 and isinstance(n.func, ast.Attribute) and n.func.attr == 'capture'
                 and n.args and isinstance(n.args[0], ast.Constant) and isinstance(n.args[0].value, str)]
        require(len(names) == count, 'Android literal capture contract differs: ' + name)
        scenes.extend(names)
    require(len(set(scenes)) == 23, 'Android scene identities missing/duplicate')
    return set(scenes)


def android_pixel_contract(script):
    replay = next(n for n in ast.parse(script.read_text()).body if isinstance(n, ast.ClassDef) and n.name == 'Replay')
    result = {}
    for method in replay.body:
        if not isinstance(method, ast.FunctionDef) or method.name not in ('run_reported', 'run_header'):
            continue
        for node in ast.walk(method):
            if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                    and node.func.attr in ('changed', 'unchanged')):
                require(len(node.args) == 4 and all(isinstance(node.args[i], ast.Constant)
                        and isinstance(node.args[i].value, str) for i in (0, 1, 3)), 'Android pixel contract is not explicit')
                key = tuple(node.args[i].value for i in (0, 1, 3))
                require(key not in result, 'duplicate Android pixel comparison')
                result[key] = node.func.attr == 'changed'
    require(len(result) == 6, 'all six exact-driver pixel comparisons required')
    return result


def validate_android(folder, script, fixture_hash):
    receipt = common.load(folder / 'receipt.json')
    expected = android_expected_scenes(script)
    require(receipt.get('passed') is True and receipt.get('apkSha256') == fixture_hash
            and receipt.get('avd') == 'whalee-api36' and len(receipt.get('scenes', [])) == 23
            and set(receipt['scenes']) == expected and receipt.get('inputs')
            and receipt.get('checks') and all(c.get('passed') is True for c in receipt['checks']),
            'completed exact-driver Android replay required')
    for scene in receipt['scenes']:
        common.name(scene)
        ET.parse(folder / (scene + '.xml'))
        common.png(folder / (scene + '.png'))
    contract = android_pixel_contract(script)
    proofs = [c for c in receipt['checks'] if 'rect' in c]
    require(len(proofs) == len(contract) and {(p.get('before'), p.get('after'), p.get('assertion'))
                                             for p in proofs} == set(contract), 'Android pixel proof coverage differs')
    verified = []
    for proof in proofs:
        key = (proof.get('before'), proof.get('after'), proof.get('assertion'))
        require(key in contract and key[0] in expected and key[1] in expected, 'unknown Android pixel comparison')
        rect = proof['rect']
        with Image.open(folder / (key[0] + '.png')) as a, Image.open(folder / (key[1] + '.png')) as b:
            require(a.size == b.size and len(rect) == 4 and all(type(n) is int for n in rect)
                    and 0 <= rect[0] < rect[2] <= a.width and 0 <= rect[1] < rect[3] <= a.height,
                    'Android proof rectangle outside actual screenshots')
            difference = ImageChops.difference(a.convert('RGB').crop(rect), b.convert('RGB').crop(rect))
            changed = sum(any(p) for p in difference.getdata())
            maximum = max(high for _, high in difference.getextrema())
        require((changed > 0) == contract[key], 'Android pixel proof disagrees with exact driver comparison mode')
        verified.append({**proof, 'expectsDifference': contract[key], 'changedPixels': changed,
                         'maxChannelDifference': maximum, 'comparisonChannels': 'RGB'})
    return receipt, verified


def android_count_history(repo, driver, history_path, tracked):
    correction_path = repo / '.local/header-shadows-scene-count-correction.json'
    before_path = repo / '.local/header-shadows-android-before-scene-count.py'
    correction = common.load(correction_path)
    require(tracked(driver) == correction.get('newDriverSha256') == ANDROID_SHA
            and tracked(before_path) == correction.get('oldDriverSha256')
            and correction.get('literalCaptureCalls') == {'run_reported': 15, 'run_header': 8}
            and correction.get('inputsActionsAssertionsUnchanged') is True, 'Android count correction provenance differs')
    old, new = correction['onlyChange']
    before = before_path.read_text()
    require(old == 'len(self.scenes) != 24 or len(self.checks) != 54'
            and new == 'len(self.scenes) != 23 or len(self.checks) != 54'
            and before.count(old) == 1 and before.replace(old, new) == driver.read_text(),
            'Android correction exceeds the single scene-count replacement')
    android_expected_scenes(driver)
    history = common.load(history_path)
    require(history.get('passed') is False and history.get('driverSha256') == correction['oldDriverSha256']
            and len(history.get('scenes', [])) == 23 and len(history.get('checks', [])) == 54
            and len(history.get('inputs', [])) == 30
            and all(c.get('passed') is True for c in history['checks']),
            'count-only failed Android history must remain separate from final acceptance')
    return correction, correction_path, before_path, history


def release_and_debt(repo, path, tracked):
    receipt = common.load(path)
    lock = common.load(repo / 'tool/design-system/sources.lock.json')
    bindings = {'sourceLockSha256': 'sources.lock.json', 'sourceInventorySha256': 'source-inventory.generated.json',
                'verificationToolSha256': 'verify_release_inputs.py', 'publishedVerifierSha256': 'published.py',
                'inventoryVerifierSha256': 'source_inventory.py'}
    require(receipt.get('allPassed') is True and receipt.get('verificationInputsUnchanged') is True
            and receipt.get('referenceCommit') == SOURCE, 'completed source release reconstruction required')
    for field, filename in bindings.items():
        require(receipt.get(field) == tracked(repo / 'tool/design-system' / filename), 'release receipt is stale: ' + field)
    packages = {p['name']: p for p in lock['packages']}
    rows = receipt.get('packages', [])
    require(len(rows) == receipt.get('packageCount') == len(packages) == 13
            and {p['name'] for p in rows} == set(packages), 'all thirteen released packages required')
    for row in rows:
        package = packages[row['name']]
        require(row.get('verified') is True and row.get('archiveUnchanged') is True
                and row['snapshotFiles'] == len(package['files'])
                and all(row[k] == package[k] for k in ('version', 'integrity', 'tarball')), 'incomplete release row')
    require(sum(r['snapshotFiles'] for r in rows) == receipt.get('verifiedSnapshotFiles') == 85,
            'all 85 actual released outputs required')
    modules = {}
    for name in ('source_inventory', 'check'):
        file = repo / 'tool/design-system' / (name + '.py')
        tracked(file)
        s = importlib.util.spec_from_file_location('header_stage_' + name, file)
        module = importlib.util.module_from_spec(s)
        s.loader.exec_module(module)
        modules[name] = module
    ledger = common.load(repo / 'tool/design-system/source-inventory.generated.json')
    modules['source_inventory'].check_snapshots(ledger, repo)
    policy = common.load(repo / 'tool/design-system/families.json')
    modules['check'].validate_contract(policy)
    counts, failures = modules['check'].inspect(repo, policy)
    require(not failures, 'current family guard failed')
    debt = Counter()
    for row in counts.values():
        debt.update(row)
    require(debt['manual-metric'] == 895 and ledger['summary']['uiCssPendingInputs'] == 173,
            'current bounded debt/source coverage differs')
    return receipt, ledger, dict(debt)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=ROOT / 'scratch/whalee-source-shadows')
    parser.add_argument('--stage', type=Path, default=ROOT / 'scratch/whalee-menu-sticky-evidence/header-shadows')
    parser.add_argument('--runtime-head', required=True)
    for name in ('preflight', 'builds', 'gpu', 'header-gpu', 'android', 'cleanup'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--check-logs', type=Path)
    parser.add_argument('--visual', type=Path)
    parser.add_argument('--regression', type=Path)
    parser.add_argument('--before', type=Path, default=ROOT / 'scratch/whalee-menu-compositing/build/parity-menu-compositing-preservation')
    parser.add_argument('--previous-visual', type=Path, default=ROOT / 'scratch/whalee-menu-compositing/build/parity-menu-compositing-final')
    parser.add_argument('--header', type=Path)
    parser.add_argument('--menu-proof', type=Path)
    parser.add_argument('--header-before', type=Path, default=ROOT / 'scratch/whalee-header-leading/build/header-leading/raster')
    parser.add_argument('--gpu-cases', type=Path)
    parser.add_argument('--header-gpu-cases', type=Path)
    parser.add_argument('--android-driver', type=Path, default=ROOT / 'scripts/header-shadows-android.py')
    parser.add_argument('--android-history', type=Path)
    parser.add_argument('--release-receipt', type=Path)
    parser.add_argument('--focused-log', type=Path, action='append', default=[])
    parser.add_argument('--review-note', type=Path, action='append', default=[])
    args = parser.parse_args()
    repo, destination = args.repo.resolve(), args.stage.resolve()
    require(destination.is_relative_to(ROOT / 'scratch/whalee-menu-sticky-evidence')
            and destination.parent.is_dir() and not destination.exists(), 'fresh owned evidence stage required')
    git = configure(repo)
    require(re.fullmatch('[0-9a-f]{40}', args.runtime_head), 'full runtime SHA required')
    head, tree = git('rev-parse', 'HEAD'), git('rev-parse', 'HEAD^{tree}')
    runtime, runtime_tree = args.runtime_head, git('rev-parse', args.runtime_head + '^{tree}')
    require(head == runtime and runtime != FAILED_RUNTIME and not git('status', '--porcelain'),
            'new exact clean final runtime required; no runtime-to-final allowances')
    changes = git('diff', '--name-only', runtime, head).splitlines()
    require(not changes, 'post-runtime changes are not accepted for this fresh final batch')
    product_trees = {group: {'runtime': git('rev-parse', runtime + ':' + group),
                             'final': git('rev-parse', head + ':' + group)} for group in ('apps', 'features', 'packages')}
    require(all(v['runtime'] == v['final'] for v in product_trees.values()), 'compiled product inputs changed after runtime build')
    raw_inputs = {}
    original_digest = common.digest
    def tracked(path):
        path = Path(path)
        require(not path.is_symlink(), 'linked raw evidence input')
        path = path.resolve()
        value = original_digest(path)
        require(path.is_relative_to(ROOT), 'input is outside the owned workspace')
        key = path.relative_to(ROOT).as_posix()
        require(key not in raw_inputs or raw_inputs[key] == value, 'evidence input changed while reading')
        raw_inputs[key] = value
        return value
    common.digest = tracked
    original_load = common.load
    def load(path):
        tracked(path)
        return original_load(path)
    common.load = load
    tracked(Path(__file__))
    tracked(ROOT / 'scripts/menu-compositing-publish.py')
    full = common.load(args.preflight)
    require(full.get('headTree') == tree and full.get('fast') is False
            and set(full.get('results', {})) == common.CHECKS
            and all(r.get('state') == 'ok' for r in full['results'].values()), 'all final-tree thirteen checks must be ok')
    logs = args.check_logs or repo / '.local/preflight'
    tool_log = logs / 'tool-tests.txt'
    tracked(tool_log)
    matches = re.findall(r'Ran (\d+) tests?\b', tool_log.read_text())
    require(matches and int(matches[-1]) >= 201 and re.search(r'^OK\s*$', tool_log.read_text(), re.M),
            'completed current tool-test log (at least 201 tests) required')
    require(not git('diff', '--name-only', BASE, head, '--', 'tool/parity-fonts', 'tool/parity_lib',
                    'tool/vendor/raft-visual-testing', 'tool/parity-ext/glyph-mask.py',
                    'tool/parity-web/capture.mjs', 'tool/parity-web/pixel-crop.mjs',
                    'apps/dsh_flutter/lib/src/platform/pinned_fonts.dart'), 'font/scorer/capture rules changed')
    visual = args.visual or repo / 'build/parity-header-shadows-final'
    regression = args.regression or repo / 'build/parity-header-shadows-regression'
    cohorts = common.groups()
    expected = set().union(*cohorts.values())
    cases = common.captures(visual, expected)
    previous = common.captures(args.previous_visual, expected)
    capture_identity = raw_identity(visual, runtime, repo, expected, tracked, args.previous_visual)
    regression_identity = raw_identity(regression, runtime, repo, common.preservation_keys(), tracked, args.before)
    before, after, preserved = common.validate_preservation(args.before, regression)
    header = args.header or repo / 'build/header-leading-integrated/raster'
    header_rows, source_receipt = header_pairs(header, args.header_before, tracked, runtime)
    builds = common.validate_builds(args.builds, runtime)
    for filename in ('runtime-head.txt', 'runtime-tree.txt', 'android-fixture.log', 'android-normal.log', 'linux-fixture.log', 'linux-normal.log'):
        tracked(args.builds / filename)
    fixture = next(b for b in builds if b['name'] == 'linux-fixture/dsh_flutter')
    gpu_runs = []
    for label, folder, manifest_path, committed in (
        ('menu', args.gpu, args.gpu_cases or repo / MENU_MANIFEST, MENU_MANIFEST),
        ('header', args.header_gpu, args.header_gpu_cases or repo / HEADER_MANIFEST, HEADER_MANIFEST)):
        common.GPU_MANIFEST = committed
        manifest = common.load(manifest_path)
        if label == 'menu':
            original = subprocess.check_output(['git', 'show', runtime + ':' + MENU_MANIFEST], cwd=repo)
            require(hashlib.sha256(original).hexdigest() == MENU_SHA == tracked(manifest_path),
                    'exact source-backed corrected menu84 manifest required')
        else:
            require(tracked(manifest_path) == HEADER_SHA, 'bounded 72-assertion Header contract changed')
        rows, gpu_runtime = gpu_receipt(folder, manifest_path, committed, runtime, fixture, head)
        if label == 'menu':
            require(sum(r['assertions'] for r in rows) == 84, 'all 84 unchanged menu assertions required')
        else:
            require(sum(r['assertions'] for r in rows) == 72
                    and sum(len(r['captures']) + 1 for r in rows) == 40, 'all72 Header assertions/40 PNGs required')
        gpu_runs.append((label, folder, manifest_path, manifest, rows, gpu_runtime))
    history_path = args.android_history or repo / 'build/native-header-shadows-android-final/receipt.json'
    count_correction, count_proof_path, old_driver_path, android_history = android_count_history(
        repo, args.android_driver, history_path, tracked)
    android, android_pixel_proofs = validate_android(args.android, args.android_driver,
                                     next(b['sha256'] for b in builds if b['name'] == 'android-fixture.apk'))
    require(android.get('runtimeHead') == runtime and android.get('runtimeTree') == runtime_tree
            and android.get('installedFixtureSha256') == android['apkSha256']
            and android.get('driverSha256') == tracked(args.android_driver) == ANDROID_SHA
            and len(android['scenes']) == 23 and len(android['checks']) == 54
            and len(android.get('inputs', [])) == 30
            and len(android.get('geometryProofs', [])) == 3
            and all(p.get('passed') is True for p in android['geometryProofs']),
            'completed exact-driver Android Header/menu contract required')
    cleanup = common.validate_cleanup(args.cleanup, next(b['sha256'] for b in builds if b['name'] == 'android-normal.apk'))
    require(cleanup.get('runtimeHead') == runtime and cleanup.get('runtimeTree') == runtime_tree
            and cleanup.get('passed') is True and cleanup.get('displayOverrideApplied') is False
            and cleanup.get('adbRootUsed') is False, 'exact-runtime native cleanup required')
    release_path = args.release_receipt or logs / 'release-inputs.json'
    release, ledger, debt = release_and_debt(repo, release_path, tracked)
    lock = common.load(repo / 'tool/design-system/sources.lock.json')
    common.SELECTED_PACKAGES = {p['snapshotFolder'] for p in lock['packages']}
    source = Path(__import__('os').environ.get('DSH_SRC', str(ROOT / 'dsh-flutter/.local/dsh-src')))
    lock, snapshots, source_files = common.provenance(source)
    menu_proof = args.menu_proof or repo / 'build/native-menu-proof'
    proof = menu_source_proof(menu_proof, repo, source, tracked)
    measured = {'thresholdPct': 99.5, 'allCaptures': common.metrics(cases),
                'groups': {g: common.metrics([c for c in cases if c['key'] in keys]) for g, keys in cohorts.items()},
                'cases': [{k: c[k] for k in common.METRICS if k in c} for c in cases]}
    comparison = {'previous': common.metrics(previous), 'current': measured['allCaptures'],
                  'nonTextMeanDelta': measured['allCaptures']['meanNonTextPct'] - common.metrics(previous)['meanNonTextPct']}
    notes = sorted((ROOT / 'notes').glob('header-shadow*.md')) + args.review_note
    required_logs = ['header-semantic-whitespace-red.log', 'header-numeric-grammar-red.log',
                     'header-semantic-whitespace-green-all.log', 'header-numeric-grammar-green-all.log', 'source-shadows-red.log',
                     'source-shadows-fractional-red.log', 'source-shadows-per-layer-green.log',
                     'model-trigger-semantics-red.log', 'model-trigger-semantics-green.log',
                     'model-trigger-semantics-full-final.log', 'model-trigger-semantics-analyze-final.log']
    focused = [repo / '.local' / f for f in required_logs] + args.focused_log
    for path in focused + notes:
        tracked(path)
    require(notes, 'independent Header/shadow review note required')
    semantic_source = repo / 'features/dsh_feature_model_selection/lib/src/model_select.dart'
    tracked(semantic_source)
    require(re.search(r'builder:\s*\(context, panel\)\s*=>\s*Semantics\(\s*container:\s*true,',
                      semantic_source.read_text()), 'new ModelSeat semantic boundary is absent')
    for filename in ('model-trigger-semantics-green.log', 'model-trigger-semantics-full-final.log'):
        require('All tests passed!' in (repo / '.local' / filename).read_text(), 'ModelSeat regression log did not complete')
    require('No issues found' in (repo / '.local/model-trigger-semantics-analyze-final.log').read_text(),
            'ModelSeat final analysis incomplete')
    changed = git('diff', '--name-only', '--diff-filter=ACMRT', BASE, head).splitlines()
    receipt = {'schema': 'header-shadows-evidence/1', 'head': head, 'headTree': tree, 'runtimeHead': runtime,
               'runtimeTree': runtime_tree, 'base': BASE, 'referenceCommit': SOURCE, 'fullChecks': 13,
               'allowedPostRuntimeChanges': changes, 'productTrees': product_trees,
               'sourceInputPrefix': repo.relative_to(ROOT).as_posix(),
               'toolTests': int(matches[-1]), 'visual': measured, 'scoreHistory': comparison,
               'builds': builds, 'preservedProviderImages': len(preserved), 'headerPairs': len(header_rows),
               'headerPriorFlutterPreserved': 16, 'gpu': {}, 'androidScenes': 23, 'androidChecks': 54,
               'androidSceneCountCorrection': {'literalScenes': 23, 'oldCount': 24, 'newDriverSha256': ANDROID_SHA,
                                                'oldFailedRunIsAcceptance': False},
               'menuSourceProof': {'sourceCommit': SOURCE, 'caseCount': len(proof['cases']),
                                   'correctOneRowChangedPixels': [c['correctOneRow']['changedPixels'] for c in proof['cases']],
                                   'actualTwoRowChangedPixels': [c['actualTwoRowControl']['changedPixels'] for c in proof['cases']],
                                   'historicalNativeIsAcceptance': False},
               'modelSeatSemanticBoundary': True,
               'androidDriverSha256': tracked(args.android_driver), 'sourceCoverage': ledger['summary'],
               'legacyDebt': debt, 'releasePackages': 13, 'releaseFiles': 85, 'limitations': LIMITS,
               'releaseOrDeployment': False}
    for label, _, _, _, rows, runtime in gpu_runs:
        receipt['gpu'][label] = {'assertions': sum(r['assertions'] for r in rows),
                                 'captures': sum(len(r['captures']) + 1 for r in rows),
                                 'manifestSha256': runtime['manifestSha256'],
                                 'cases': [{'case': r['case'], 'assertions': r['assertions']} for r in rows]}
    with tempfile.TemporaryDirectory(prefix='.header-shadow-stage-', dir=destination.parent) as temporary:
        stage = Path(temporary) / 'header-shadows'
        stage.mkdir()
        common.copy_captures(stage, visual, cases, 'components', differences=True)
        common.copy_captures(stage, args.previous_visual, previous, 'previous-components')
        common.write_json(stage / 'previous-components/summary.json',
                          {'allCaptures': common.metrics(previous), 'cases': previous})
        common.write_json(stage / 'components/summary.json', measured)
        common.write_json(stage / 'components/score-history.json', comparison)
        for folder, target in ((visual, 'current'), (regression, 'regression')):
            common.write_json(stage / 'capture-identities' / (target + '.json'), common.load(folder / 'capture-identity.json'))
            common.write_json(stage / 'capture-identities' / (target + '-plan.json'), common.load(folder / 'flutter-plan.json'))
        common.copy_captures(stage, args.before, before, 'preservation/before')
        common.copy_captures(stage, regression, after, 'preservation/after')
        common.write_json(stage / 'preservation/rgba.json', preserved)
        common.write_json(stage / 'header/comparison.json', header_rows)
        common.write_json(stage / 'header/source-receipt.json', source_receipt)
        common.write_json(stage / 'header/capture-identity.json', common.load(header / 'capture-identity.json'))
        for path in sorted(menu_proof.rglob('*')):
            if path.is_file():
                target = stage / 'native-menu-proof' / path.relative_to(menu_proof)
                if path.suffix == '.png':
                    common.copy_png(path, target)
                else:
                    common.copy_text(path, target)
        for path in proof['sourceFiles']:
            common.copy_text(source / path, stage / 'native-menu-proof/reference-source' / path)
        for row in header_rows:
            key = row['id']
            for provider in ('source', 'flutter'):
                common.copy_png(header / (provider + '-' + key + '.png'), stage / 'header' / (provider + '-' + key + '.png'))
            common.copy_png(args.header_before / ('flutter-' + key + '.png'), stage / 'header/prior-flutter' / (key + '.png'))
        for label, folder, manifest_path, manifest, rows, runtime in gpu_runs:
            common.write_json(stage / 'gpu' / label / 'runtime.json', runtime)
            common.write_json(stage / 'gpu' / label / 'manifest.json', manifest)
            for row in rows:
                target = stage / 'gpu' / label / row['case']
                common.write_json(target / 'environment.json', row['environment'])
                for shot in row['captures']:
                    common.copy_png(folder / row['case'] / (shot + '.png'), target / (shot + '.png'))
                common.copy_png(folder / (row['case'] + '.png'), stage / 'gpu' / label / (row['case'] + '.png'))
        for scene in android['scenes']:
            common.copy_png(args.android / (scene + '.png'), stage / 'android' / (scene + '.png'))
            common.copy_text(args.android / (scene + '.xml'), stage / 'android' / (scene + '.xml'))
        for filename, value in [('android/receipt.json', android), ('cleanup.json', cleanup), ('preflight.json', full),
                                ('release-inputs.json', release), ('receipt.json', receipt)]:
            common.write_json(stage / filename, value)
        common.write_json(stage / 'android-history/scene-count-correction.json', count_correction)
        common.write_json(stage / 'android-history/failed-receipt.json', android_history)
        common.copy_text(old_driver_path, stage / 'android-history/driver-before-scene-count.py')
        common.write_json(stage / 'android/pixel-proofs.json', android_pixel_proofs)
        for check in sorted(common.CHECKS):
            common.copy_text(logs / (check + '.txt'), stage / 'checks' / (check + '.txt'))
        for i, path in enumerate(focused):
            common.copy_text(path, stage / 'checks' / f'focused-{i}-{path.name}')
        for filename in ('sources.lock.json', 'source-inventory.generated.json', 'families.json', 'recipes.generated.json', 'theme.generated.json'):
            common.write_json(stage / 'provenance' / filename, common.load(repo / 'tool/design-system' / filename))
        common.write_json(stage / 'provenance/font-pins.json', common.load(repo / 'tool/parity-fonts/manifest.json'))
        for path in snapshots:
            common.copy_text(path, stage / 'published-inputs' / path.relative_to(repo / 'tool/design-system/upstream'))
        for path in source_files:
            common.copy_text(source / path, stage / 'reference-source' / path)
        for path in changed:
            common.copy_text(repo / path, stage / 'implementation' / path)
        for filename in ('header-leading.md', 'source-shadows.md', 'native-menu-proof.md'):
            common.copy_text(repo / 'docs/design-system' / filename, stage / 'review' / filename)
        for path in notes:
            common.copy_text(path, stage / 'review' / path.name)
        for path in [*sorted((ROOT / 'scripts').glob('header-shadows-*.py')),
                     *sorted((ROOT / 'scripts').glob('header-shadows-*.sh')),
                     ROOT / 'scripts/header-shadows-report-preview.cjs',
                     ROOT / 'scripts/menu-compositing-publish.py', ROOT / 'scripts/menu-compositing-report.py']:
            common.copy_text(path, stage / 'reproduction' / path.name)
        for path in ('tool/design-system/capture-header-leading.mjs', 'tool/parity-ext/host/header-leading.tsx',
                     'tool/design-system/verify_release_inputs.py', 'tool/design-system/published.py',
                     'tool/design-system/source_inventory.py', 'tool/design-system/generate.py',
                     MENU_MANIFEST, HEADER_MANIFEST, 'tool/parity-desktop/gpu_capture.py', 'tool/parity-desktop/weston_input.c'):
            common.copy_text(repo / path, stage / 'reproduction' / path)
        diff = subprocess.check_output(['git', 'diff', '--no-ext-diff', '--binary', BASE, head], cwd=repo, text=True)
        (stage / 'implementation.patch').write_text(common.clean_text(diff))
        (stage / 'README.md').write_text('# Header and source-shadow migration\n\n'
            + json.dumps(common.clean(receipt), ensure_ascii=False, indent=2) + '\n\n'
            + '\n'.join('- ' + line for line in LIMITS) + '\n')
        for key, expected_hash in list(raw_inputs.items()):
            require(original_digest(ROOT / key) == expected_hash, 'input changed during staging: ' + key)
        common.write_json(stage / 'input-hashes.json', [{'path': k, 'sha256': v} for k, v in sorted(raw_inputs.items())])
        files = []
        for path in sorted(stage.rglob('*')):
            if not path.is_file():
                continue
            if path.suffix != '.png':
                text = path.read_text()
                require(not common.SENSITIVE.search(text) and not common.HOME_PATH.search(text), 'private staged text')
            files.append({'path': path.relative_to(stage).as_posix(), 'sha256': original_digest(path), 'bytes': path.stat().st_size})
        common.write_json(stage / 'files.json', files)
        require(git('rev-parse', 'HEAD') == head and not git('status', '--porcelain') and not destination.exists(),
                'final source/destination changed during staging')
        stage.rename(destination)
    print(json.dumps({'head': head, 'tree': tree, 'files': len(files) + 1, 'visual': measured['allCaptures'],
                      'scoreHistory': comparison, 'headerPairs': 16, 'preservedProviderImages': 192,
                      'gpu': receipt['gpu'], 'androidScenes': 23, 'published': False}))


if __name__ == '__main__':
    main()
