#!/usr/bin/env python3
"""Stage completed synthetic reported-family evidence, without network or devices.

Refuse incomplete checks, captures, builds, native receipts or cleanup. This
script only creates the new reported-families directory in the existing evidence
worktree. It never commits, pushes, uploads, changes the application, or runs it.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT / 'scratch/whalee-reported-families'
BASE = 'c0fa5c671aa0001ea6192050413e4043b4bc236e'
DEST = ROOT / 'scratch/whalee-menu-sticky-evidence/reported-families'
GPU_MANIFEST = 'tool/parity-desktop/reported-families-cases.json'
SIDEBAR_TEST = 'features/dsh_feature_sidebar/test/sidebar_test.dart'
MODEL_CAPTURE_BUILDER = 'tool/parity-ext/build-reported-model.py'
CHECKS = {'check-deps', 'tool-tests', 'codegen', 'theme-pack', 'design-system', 'i18n',
          'icons', 'vector', 'parity', 'capability', 'format', 'analyze', 'tests'}
METRICS = ('key', 'caseId', 'kind', 'theme', 'nonTextPct', 'pixelPerfectPct', 'rgbPct',
           'sizeReact', 'sizeFlutter', 'sideBySide')
SENSITIVE = re.compile(
    r'-----BEGIN [^-\n]*PRIVATE KEY-----|'
    r'\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|'
    r'github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})\b|'
    r'\bBearer\s+[A-Za-z0-9._=-]{12,}|'
    r'(?:password|access_token|refresh_token|client_secret)\s*[=:]\s*["\'][^"\'\s]{16,}', re.I)
HOME_PATH = re.compile(r'/(?:home|Users)/[^\s"\'<>]+|/(?:root)(?:/[^\s"\'<>]*)?')
SAFE_NAME = re.compile(r'[A-Za-z0-9_.-]+')
NOTES = ('reported-sidebar-audit.md', 'reported-model-audit.md', 'reported-stats-audit.md',
         'reported-families-independent-review.md', 'reported-stats-dom-geometry.md',
         'reported-model-sizing-audit.md', 'reported-model-sizing-audit.json',
         'reported-model-focus-audit.md')
SELECTED_PACKAGES = {'ui-sidebar', 'ui-workspace', 'ui-settings-general', 'ui-settings-account',
                     'ui-model-selection', 'ui-chat', 'ui-primitives', 'ui-theme'}
LIMITATIONS = [
    'The overall 99.5% visual target remains unfinished; measured results are reported without changing fonts, classifier or thresholds.',
    'Statistics panels remove the sharp backdrop-text bleed, but textured backdrop sampling still differs from Chromium in the composed Skia filter path. The explicit mirror-mode probe produced identical Flutter pixels and does not establish a similarity improvement.',
    'Linux tests with macOS geometry and scoped fill do not certify native macOS window vibrancy.',
    'Model-directory search retains a small natural input-line height difference under the unchanged fonts and renderers. The eight directory-card dimension differences remain visible in the full capture measurements.',
    'Account operations, pointer-linger sidebar scrollbars, collapse choreography and other navigation states remain outside this bounded migration.',
    'Composer-container icon compaction and selection Toast presentation remain incomplete. Programmatic focus transfer outside the model trigger/card does not yet implement the source onBlur dismissal.',
    'The phone sidebar component captures do not certify AppFrame drawer edge gestures or its open/close choreography.',
    'All published pictures use synthetic fixture data. Real user screenshots, credentials and application request logs are excluded. No release or deployment is performed.',
]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def git(*args, cwd=REPO):
    return subprocess.check_output(['git', *args], cwd=cwd, text=True).strip()


def load(path):
    require(path.is_file() and not path.is_symlink(), 'missing or linked JSON input: ' + path.name)
    return json.loads(path.read_text())


def digest(path):
    require(path.is_file() and not path.is_symlink(), 'missing or linked evidence input: ' + path.name)
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def relative(value):
    path = Path(value)
    require(value and not path.is_absolute() and '..' not in path.parts,
            'unsafe evidence relative path')
    return path


def name(value):
    require(isinstance(value, str) and SAFE_NAME.fullmatch(value), 'unsafe evidence name')
    return value


def clean_text(value):
    require(not SENSITIVE.search(value), 'credential-shaped text in an evidence input')
    value = value.replace(str(ROOT), '[workspace]')
    value = HOME_PATH.sub('[home-path]', value)
    value = re.sub(r'/run/user/\d+(?:/[^\s"\'<>]*)?', '[runtime-path]', value)
    return re.sub(r'https?://(?:127\.0\.0\.1|localhost|\[::1\])(?::\d+)?[^\s"\'<>]*',
                  '[local-runtime-url]', value)


def clean(value):
    if isinstance(value, dict):
        return {clean_text(str(key)): clean(item) for key, item in value.items()}
    if isinstance(value, list):
        return [clean(item) for item in value]
    return clean_text(value) if isinstance(value, str) else value


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(clean(value), indent=2, ensure_ascii=False) + '\n')


def copy_text(source, target):
    digest(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(clean_text(source.read_text()))


def png(path):
    digest(path)
    with Image.open(path) as picture:
        require(picture.format == 'PNG' and min(picture.size) > 0, 'invalid screenshot PNG')
        for value in picture.info.values():
            if isinstance(value, str):
                require(clean_text(value) == value, 'private text embedded in PNG metadata')
        size = list(picture.size)
        picture.verify()
    return size


def copy_png(source, target):
    png(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def groups():
    themes = ('light', 'dark')
    locales = ('en', 'zh')
    return {
        'sidebar': {f'components.reported-sidebar.{p}-{d}-{l}.{t}'
                    for p, d in (('darwin', 'desktop'), ('linux', 'desktop'), ('linux', 'phone'))
                    for l in locales for t in themes},
        'model': {f'components.reported-model.{p}-{c}-{d}-{l}.{t}'
                  for p in ('root', 'model', 'effort') for c in ('card', 'viewport')
                  for d in ('desktop', 'phone') for l in locales for t in themes},
        'stats': {f'components.reported-stats.{d}-{l}-{p}{edge}.{t}'
                  for d in ('desktop', 'mac', 'phone') for l in locales
                  for p in ('activity', 'usage') for edge in ('', '-right-edge') for t in themes},
    }


def preservation_keys():
    return {f'components.dialog-family.{p}-{d}-{l}-{page}.{t}'
            for p in ('reader', 'tabs', 'panel-scrolled', 'panel-retained')
            for d in ('desktop', 'phone') for l in ('en', 'zh')
            for page in ('explanation', 'usage') for t in ('light', 'dark')} | {
                f'components.checkbox-family.model-{d}-{l}-{state}.{t}'
                for d in ('desktop', 'phone') for l in ('en', 'zh')
                for state in ('off', 'on', 'off-disabled', 'on-disabled') for t in ('light', 'dark')}


def captures(folder, expected):
    summary = load(folder / 'summary.json')
    cases = summary.get('cases', [])
    require(len(cases) == len(expected) and {c.get('key') for c in cases} == expected,
            'capture cohort differs from declared identities')
    for case in cases:
        name(case['key'])
        for field in ('nonTextPct', 'pixelPerfectPct', 'rgbPct'):
            value = case.get(field)
            require(type(value) in (int, float) and math.isfinite(value) and 0 <= value <= 100,
                    'missing measured capture metric: ' + case['key'] + '/' + field)
        for provider, field in (('react', 'sizeReact'), ('flutter', 'sizeFlutter')):
            path = folder / 'visual-testing-results' / provider / (case['key'] + '.png')
            require(png(path) == case.get(field), 'capture/summary dimensions disagree')
            meta = load(path.with_suffix('.metadata.json'))
            require(meta.get('provider') == provider and meta.get('captureKey') == case['key'],
                    'capture metadata identity mismatch')
    require(summary.get('counts', {}).get('compared') == len(expected), 'capture summary is incomplete')
    return cases


def metrics(cases):
    return {'compared': len(cases),
            'dimensionsEqual': sum(c['sizeReact'] == c['sizeFlutter'] for c in cases),
            'nonTextAtLeast99_5': sum(c['nonTextPct'] >= 99.5 for c in cases),
            'meanNonTextPct': sum(c['nonTextPct'] for c in cases) / len(cases)}


def copy_captures(stage, folder, cases, destination, differences=False):
    for case in cases:
        for provider in ('react', 'flutter'):
            path = folder / 'visual-testing-results' / provider / (case['key'] + '.png')
            copy_png(path, stage / destination / provider / path.name)
            write_json(stage / destination / provider / path.with_suffix('.metadata.json').name,
                       load(path.with_suffix('.metadata.json')))
        if differences:
            diff = relative(case['sideBySide'])
            require(diff.parts[:3] == ('visual-testing-results', 'diff', 'react__flutter'),
                    'unexpected comparison image location')
            copy_png(folder / diff, stage / destination / 'diff' / diff.name)


def validate_preservation(before, after):
    expected = preservation_keys()
    first, second = captures(before, expected), captures(after, expected)
    pairs = []
    for key in sorted(expected):
        for provider in ('react', 'flutter'):
            left = before / 'visual-testing-results' / provider / (key + '.png')
            right = after / 'visual-testing-results' / provider / (key + '.png')
            with Image.open(left) as a, Image.open(right) as b:
                same = a.size == b.size and a.convert('RGBA').tobytes() == b.convert('RGBA').tobytes()
            require(same, 'preservation pixels changed: ' + provider + '/' + key)
            pairs.append({'key': key, 'provider': provider, 'rgbaByteEqual': True,
                          'beforeSha256': digest(left), 'afterSha256': digest(right)})
    require(len(pairs) == 192, 'the preservation contract requires 192 provider comparisons')
    return first, second, pairs


def validate_builds(folder, runtime_head):
    require((folder / 'runtime-head.txt').read_text().strip() == runtime_head
            and (folder / 'runtime-tree.txt').read_text().strip() == git('rev-parse', runtime_head + '^{tree}'),
            'runtime build identity differs from declared source')
    rows = []
    for file, log in (('android-fixture.apk', 'android-fixture.log'), ('android-normal.apk', 'android-normal.log'),
                      ('linux-fixture/dsh_flutter', 'linux-fixture.log'), ('linux-normal/dsh_flutter', 'linux-normal.log')):
        success = [line.strip() for line in (folder / log).read_text().splitlines() if 'Built ' in line]
        require(success, 'missing successful build output: ' + file)
        row = {'name': file, 'sha256': digest(folder / file), 'successLine': success[-1]}
        if file.endswith('/dsh_flutter'):
            row['applicationLibrarySha256'] = digest((folder / file).parent / 'lib/libapp.so')
        rows.append(row)
    return rows


def validate_gpu(folder, manifest, runtime_head, fixture_build):
    runtime = load(folder / 'runtime.json')
    require(runtime.get('runtimeHead') == runtime_head
            and runtime.get('runtimeTree') == git('rev-parse', runtime_head + '^{tree}')
            and runtime.get('binaryUnchanged') is True
            and runtime.get('executableSha256') == fixture_build['sha256']
            and runtime.get('applicationLibrarySha256') == fixture_build['applicationLibrarySha256'],
            'GPU replay is not bound to the exact unchanged fixture build')
    cases = manifest.get('cases', [])
    require(cases and len({c['id'] for c in cases}) == len(cases)
            and any(c['width'] < 600 for c in cases) and any(c['width'] >= 1024 for c in cases),
            'missing phone/desktop GPU manifest coverage')
    require({p.parent.name for p in folder.glob('*/environment.json')} == {c['id'] for c in cases},
            'GPU receipt coverage differs from manifest')
    keep = ('weston', 'renderer', 'appRenderDevices', 'glVersion', 'appRenderer', 'backend',
            'cursorIncluded', 'captureAssertions', 'pairedHost', 'size', 'theme', 'locale')
    result = []
    for case in cases:
        directory = folder / name(case['id'])
        env = load(directory / 'environment.json')
        expected = [step['expect'] for step in case['app'] if 'expect' in step]
        actual = env.get('captureAssertions', [])
        require(expected and len(actual) == len(expected)
                and all(row.get('passed') is True and all(row.get(k) == v for k, v in spec.items())
                        for row, spec in zip(actual, expected)), 'incomplete or failed GPU assertions')
        require(env.get('backend') == 'native-wayland' and env.get('appRenderDevices')
                and env.get('size') == [case['width'], case['height']]
                and env.get('pairedHost') is False
                and not re.search(r'llvmpipe|softpipe|swrast|software', env.get('renderer', ''), re.I),
                'missing native hardware GPU/size/fixture proof')
        for pid in load(directory / 'pids.json').values():
            require(type(pid) is int and pid > 1, 'invalid recorded GPU PID')
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                pass
            else:
                raise ValueError('recorded GPU PID still exists')
        shots = [step['capture'] for step in case['app'] if 'capture' in step]
        require(shots and len(shots) == len(set(shots)), 'missing or duplicate GPU shots')
        for shot in shots:
            png(directory / (name(shot) + '.png'))
        png(folder / (case['id'] + '.png'))
        result.append({'case': case['id'], 'environment': {k: env[k] for k in keep if k in env},
                       'captures': shots, 'assertions': len(actual)})
    return result, runtime


def android_scenes(script):
    tree = ast.parse(script.read_text())
    run = next(node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef) and node.name == 'run')
    result = [node.args[0].value for node in ast.walk(run)
              if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
              and node.func.attr == 'capture' and node.args and isinstance(node.args[0], ast.Constant)]
    require(result and len(result) == len(set(result)), 'missing or duplicate driver scene contract')
    return set(result)


def validate_android(folder, script, fixture_hash):
    receipt = load(folder / 'receipt.json')
    scenes = receipt.get('scenes', [])
    expected = android_scenes(script)
    require(receipt.get('passed') is True and receipt.get('apkSha256') == fixture_hash
            and receipt.get('avd') == 'whalee-api36'
            and len(scenes) == len(expected) and set(scenes) == expected,
            'Android receipt is incomplete or has a different APK/AVD/driver contract')
    require(receipt.get('inputs') and receipt.get('checks')
            and all(row.get('passed') is True for row in receipt['checks']),
            'Android actual input/check evidence is missing or failed')
    for scene in scenes:
        name(scene)
        ET.parse(folder / (scene + '.xml'))
        png(folder / (scene + '.png'))
    proofs = [row for row in receipt['checks'] if 'rect' in row]
    require(proofs, 'Android no-mask pixel proof is missing')
    for proof in proofs:
        require(proof.get('before') in expected and proof.get('after') in expected,
                'Android image proof references an unknown scene')
        rect = proof['rect']
        with Image.open(folder / (proof['before'] + '.png')) as a, Image.open(folder / (proof['after'] + '.png')) as b:
            require(a.size == b.size and len(rect) == 4 and all(type(n) is int for n in rect)
                    and 0 <= rect[0] < rect[2] <= a.width and 0 <= rect[1] < rect[3] <= a.height,
                    'Android proof bounds are invalid')
            require(a.convert('RGBA').crop(rect).tobytes() == b.convert('RGBA').crop(rect).tobytes(),
                    'Android no-mask proof disagrees with actual pixels')
    return receipt


def validate_cleanup(path, normal_hash):
    data = load(path)
    for key in ('normalApkRestored', 'normalAppForceStopped', 'ownedEmulatorStopped', 'sharedAdbRetained'):
        require(data.get(key) is True, 'missing completed cleanup: ' + key)
    require(data.get('normalApkLocalSha256') == normal_hash
            and data.get('normalApkInstalledSha256') == normal_hash, 'normal APK restoration hash mismatch')
    require(data.get('displayOverrideApplied') is False or data.get('displayOverrideReset') is True,
            'missing original display-state preservation/restoration proof')
    require(data.get('adbRootUsed') is False or data.get('adbdUnrootRequested') is True,
            'missing ADB privilege-state preservation/restoration proof')
    return data


def copy_stats_mirror_probe(stage):
    before = ROOT / 'scratch/stats-reference-smoke'
    after = ROOT / 'scratch/stats-mirror-smoke'
    rows = []
    for key in ('components.reported-stats.desktop-en-activity.light',
                'components.reported-stats.mac-en-activity.light',
                'components.reported-stats.mac-en-activity.dark'):
        original = before / 'visual-testing-results/flutter' / (key + '.png')
        corrected = after / 'visual-testing-results/flutter' / (key + '.png')
        reference = before / 'visual-testing-results/react' / (key + '.png')
        with Image.open(original) as a, Image.open(corrected) as b:
            require(a.size == b.size and a.convert('RGBA').tobytes() == b.convert('RGBA').tobytes(),
                    'mirror probe no longer supports its unchanged-pixel claim')
        rows.append({'key': key, 'sameRgba': True, 'beforeSha256': digest(original),
                     'afterSha256': digest(corrected), 'sourceSha256': digest(reference)})
        for provider, path in (('source', reference), ('before', original), ('after', corrected)):
            copy_png(path, stage / 'diagnostics/statistics-mirror' / provider / path.name)
    write_json(stage / 'diagnostics/statistics-mirror/rgba.json', rows)
    write_json(stage / 'diagnostics/statistics-mirror/computed-material-probes.json',
               load(before / 'computed-material-probes.json'))


def provenance(source):
    lock = load(REPO / 'tool/design-system/sources.lock.json')
    require(git('rev-parse', 'HEAD', cwd=source) == lock['referenceCommit'], 'reference checkout drift')
    snapshots, source_files = [], set()
    for package in lock['packages']:
        current, consumer = load(source / package['sourcePackage']), load(source / package['referenceConsumer'])
        require(current['version'] == package['version']
                and consumer[package['dependencyField']].get(package['name']) == package['dependencySpecifier'],
                'reference dependency or package version drift')
        for other in package.get('referenceConsumers', []):
            require(load(source / other['path'])[other['dependencyField']].get(package['name']) == other['dependencySpecifier'],
                    'additional reference dependency drift')
        for path, expected in package.get('referenceSourceSha256', {}).items():
            require(digest(source / relative(path)) == expected, 'reference source hash drift')
        if package['snapshotFolder'] in SELECTED_PACKAGES:
            for filename, expected in package['files'].items():
                path = REPO / 'tool/design-system/upstream' / package['snapshotFolder'] / relative(filename)
                require(digest(path) == expected, 'published snapshot hash drift')
                snapshots.append(path)
            source_files.update(package.get('referenceSourceSha256', {}))
            source_files.add(package['sourcePackage'])
    return lock, snapshots, sorted(source_files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-head', required=True, help='full source SHA recorded by all four final builds')
    parser.add_argument('--visual', type=Path, default=REPO / 'build/parity-reported-final')
    parser.add_argument('--before', type=Path, default=ROOT / 'scratch/whalee-headed-dialogs/build/parity-headed-regression-after')
    parser.add_argument('--preservation', type=Path, default=REPO / 'build/parity-reported-preservation')
    parser.add_argument('--preflight', type=Path, default=REPO / '.local/reported-full-final.json')
    parser.add_argument('--builds', type=Path, default=REPO / '.local/reported-builds')
    parser.add_argument('--gpu', type=Path, default=REPO / 'build/native-reported-gpu-final')
    parser.add_argument('--gpu-cases', type=Path, default=REPO / GPU_MANIFEST)
    parser.add_argument('--android', type=Path, default=REPO / 'build/native-reported-android')
    parser.add_argument('--cleanup', type=Path, default=REPO / '.local/reported-cleanup.json')
    parser.add_argument('--focused-log', type=Path, action='append', default=[], help='optional completed focused-check log, sanitized and scanned')
    args = parser.parse_args()
    require(not DEST.exists() and DEST.parent.is_dir(), 'new reported-families destination required; preserve any prior staging')
    require(not git('status', '--porcelain'), 'final product worktree must be clean')
    require(re.fullmatch(r'[0-9a-f]{40}', args.runtime_head), 'runtime head must be a full SHA')
    runtime = git('rev-parse', args.runtime_head + '^{commit}')
    head, tree = git('rev-parse', 'HEAD'), git('rev-parse', 'HEAD^{tree}')
    changes = git('diff', '--name-only', runtime, head).splitlines()
    require(all(path.startswith('docs/') or path in (GPU_MANIFEST, SIDEBAR_TEST, MODEL_CAPTURE_BUILDER) for path in changes),
            'runtime-to-final changes exceed the documented non-runtime allowance')
    if SIDEBAR_TEST in changes:
        original = git('show', runtime + ':' + SIDEBAR_TEST)
        revised = git('show', head + ':' + SIDEBAR_TEST)
        old = 't.binding.pipelineOwner.semanticsOwner!'
        require(original.count(old) == 2, 'runtime sidebar regression test differs')
        expected = subprocess.check_output(
            [os.environ.get('DART', 'dart'), 'format', '--output=show',
             '--stdin-name=' + str(REPO / SIDEBAR_TEST)],
            input=original.replace(old, 'node.owner!'), text=True,
        ).rsplit('Formatted ', 1)[0].strip()
        require(expected == revised,
                'post-runtime sidebar test changes exceed the exact deprecated-API replacement')
    if MODEL_CAPTURE_BUILDER in changes:
        original = git('show', runtime + ':' + MODEL_CAPTURE_BUILDER)
        revised = git('show', head + ':' + MODEL_CAPTURE_BUILDER)
        marker = "            for capture in ['card', 'viewport']:"
        settled = "            steps.append({'type': 'hover', 'target': 'reported-model-result'})\n"
        require(original.count(marker) == 1 and original.replace(marker, settled + marker) == revised,
                'post-runtime capture changes exceed the exact shared pointer-state settlement')
    require(not git('diff', '--name-only', BASE, head, '--', 'tool/parity-fonts', 'tool/parity_lib',
                    'tool/vendor/raft-visual-testing', 'tool/parity-ext/glyph-mask.py',
                    'tool/parity-web/capture.mjs', 'tool/parity-web/pixel-crop.mjs',
                    'apps/dsh_flutter/lib/src/platform/pinned_fonts.dart'), 'font/classifier/reference capture inputs changed')
    full = load(args.preflight)
    require(full.get('headTree') == tree and full.get('fast') is False and set(full.get('results', {})) == CHECKS
            and all(row.get('state') == 'ok' for row in full['results'].values()),
            'successful final-tree full thirteen-check preflight required')
    cohorts = groups()
    cases = captures(args.visual, set().union(*cohorts.values()))
    require(len(cases) == 108, 'all 108 reference/Flutter pairs are required')
    before, after, preserved = validate_preservation(args.before, args.preservation)
    builds = validate_builds(args.builds, runtime)
    hashes = {row['name']: row['sha256'] for row in builds}
    gpu_manifest = load(args.gpu_cases)
    gpu, gpu_runtime = validate_gpu(args.gpu, gpu_manifest, runtime,
                                    next(row for row in builds if row['name'] == 'linux-fixture/dsh_flutter'))
    driver = ROOT / 'scripts/reported-families-android.py'
    android = validate_android(args.android, driver, hashes['android-fixture.apk'])
    cleanup = validate_cleanup(args.cleanup, hashes['android-normal.apk'])
    source = Path(os.environ.get('DSH_SRC', str(ROOT / 'dsh-flutter/.local/dsh-src')))
    lock, snapshots, sources = provenance(source)
    changed = git('diff', '--name-only', '--diff-filter=ACMRT', BASE, head).splitlines()
    require(all(not Path(path).is_absolute() and '..' not in Path(path).parts for path in changed), 'unsafe changed-file path')
    measured = {'thresholdPct': 99.5, 'allCaptures': metrics(cases),
                'groups': {group: metrics([c for c in cases if c['key'] in keys]) for group, keys in cohorts.items()},
                'cases': [{key: c[key] for key in METRICS if key in c} for c in cases]}
    receipt = {'head': head, 'headTree': tree, 'base': BASE, 'runtimeHead': runtime,
               'runtimeTree': git('rev-parse', runtime + '^{tree}'), 'allowedPostRuntimeChanges': changes,
               'referenceCommit': lock['referenceCommit'], 'fullChecks': len(CHECKS), 'visual': measured,
               'builds': builds, 'preservedProviderImages': len(preserved),
               'gpu': [{'case': row['case'], 'assertions': row['assertions'], 'captures': len(row['captures'])} for row in gpu],
               'androidScenes': len(android['scenes']), 'androidChecks': len(android['checks']),
               'androidDriverSha256': digest(driver), 'gpuManifestSha256': digest(args.gpu_cases),
               'limitations': LIMITATIONS, 'releaseOrDeployment': False}
    with tempfile.TemporaryDirectory(prefix='.reported-staging-', dir=DEST.parent) as temporary:
        stage = Path(temporary) / 'reported-families'
        stage.mkdir()
        copy_captures(stage, args.visual, cases, 'components', differences=True)
        copy_stats_mirror_probe(stage)
        write_json(stage / 'components/summary.json', measured)
        manifest = load(args.visual / 'cases.sampled.json')
        selected_ids = {case['caseId'] for case in cases}
        manifest['cases'] = [case for case in manifest['cases'] if case['id'] in selected_ids]
        require(len(manifest['cases']) == len(selected_ids), 'capture manifest incomplete')
        write_json(stage / 'components/cases.json', manifest)
        copy_captures(stage, args.before, before, 'preservation/before')
        copy_captures(stage, args.preservation, after, 'preservation/after')
        write_json(stage / 'preservation/rgba.json', preserved)
        for row in gpu:
            directory = args.gpu / row['case']
            write_json(stage / 'gpu' / row['case'] / 'environment.json', row['environment'])
            for shot in row['captures']:
                copy_png(directory / (shot + '.png'), stage / 'gpu' / row['case'] / (shot + '.png'))
            copy_png(args.gpu / (row['case'] + '.png'), stage / 'gpu' / (row['case'] + '.png'))
        write_json(stage / 'gpu/runtime.json', gpu_runtime)
        for scene in android['scenes']:
            copy_png(args.android / (scene + '.png'), stage / 'android' / (scene + '.png'))
            copy_text(args.android / (scene + '.xml'), stage / 'android' / (scene + '.xml'))
        if (args.android / 'visual-review.json').is_file():
            write_json(stage / 'android/visual-review.json', load(args.android / 'visual-review.json'))
        write_json(stage / 'android/receipt.json', android)
        write_json(stage / 'preflight.json', full)
        write_json(stage / 'cleanup.json', cleanup)
        write_json(stage / 'receipt.json', receipt)
        for check in sorted(CHECKS):
            copy_text(REPO / '.local/preflight' / (check + '.txt'), stage / 'checks' / (check + '.txt'))
        for index, log in enumerate(args.focused_log):
            copy_text(log, stage / 'checks' / f'focused-{index + 1}-{name(log.name)}')
        for filename in ('sources.lock.json', 'families.json', 'recipes.generated.json', 'theme.generated.json'):
            write_json(stage / 'provenance' / filename, load(REPO / 'tool/design-system' / filename))
        write_json(stage / 'provenance/font-pins.json', load(REPO / 'tool/parity-fonts/manifest.json'))
        for path in snapshots:
            copy_text(path, stage / 'published-inputs' / path.relative_to(REPO / 'tool/design-system/upstream'))
        for path in sources:
            copy_text(source / path, stage / 'reference-source' / path)
        for path in changed:
            copy_text(REPO / path, stage / 'implementation' / path)
        diff = subprocess.check_output(['git', 'diff', '--no-ext-diff', '--binary', BASE, head], cwd=REPO, text=True)
        (stage / 'implementation.patch').write_text(clean_text(diff))
        for filename in NOTES:
            copy_text(ROOT / 'notes' / filename, stage / 'review' / filename)
        for filename in ('reported-families-android.py', 'reported-families-gpu.sh',
                         'reported-families-gpu-proof.py', 'reported-families-builds.sh',
                         'reported-families-publish.py', 'reported-families-report.py',
                         'reported-families-report-preview.cjs'):
            copy_text(ROOT / 'scripts' / filename, stage / 'reproduction' / filename)
        for filename in (GPU_MANIFEST, 'tool/parity-desktop/gpu_capture.py', 'tool/parity-desktop/weston_input.c'):
            copy_text(REPO / filename, stage / 'reproduction' / filename)
        total = measured['allCaptures']
        readme = (
            '# Sidebar, statistics and model-menu evidence\n\n'
            'The actual production sidebar/More launcher, statistics popovers and compact model selector consume '
            'canonical profiles generated from pinned published DSH 0.2.1-rc.2 packages. Their source reference '
            'fixtures mount the actual upstream components over synthetic data.\n\n'
            f'All {total["compared"]} pairs were compared; {total["dimensionsEqual"]} have equal capture dimensions, '
            f'{total["nonTextAtLeast99_5"]} meet the unchanged 99.5% non-text threshold, and mean non-text agreement '
            f'is {total["meanNonTextPct"]:.3f}%. Per-family and per-capture results remain in components/summary.json. '
            f'The previous 96 reader/model-checkbox cases retain identical RGBA pixels in both providers '
            f'({len(preserved)} provider comparisons).\n\n'
            f'The final tree passed all {len(CHECKS)} required checks. Four completed build hashes, '
            f'{sum(row["assertions"] for row in gpu)} GPU assertions across {len(gpu)} manifest cases, '
            f'and {len(android["checks"])} Android checks across {len(android["scenes"])} scenes are recorded. '
            'Counts come from completed receipts and their capture/input contracts, not a planned checklist. '
            'Normal APK installed-byte readback, owned process shutdown and shared ADB preservation are recorded.\n\n'
            'implementation.patch and implementation/ contain the delivered source. published-inputs/ preserves '
            'the locked decoded release data; reference-source/ contains the pinned source inputs. '
            'Reproduction scripts replace private machine paths with [workspace]/[home-path]; set these locally '
            'before rerunning. Raw native application/server logs and real user screenshots are omitted.\n\n'
            + '\n'.join('- ' + item for item in LIMITATIONS) + '\n')
        (stage / 'README.md').write_text(readme)
        hashes_out = []
        for path in sorted(stage.rglob('*')):
            if not path.is_file():
                continue
            if path.suffix != '.png':
                text = path.read_text()
                require(not SENSITIVE.search(text) and not HOME_PATH.search(text), 'unsafe staged text')
            hashes_out.append({'path': str(path.relative_to(stage)), 'sha256': digest(path), 'bytes': path.stat().st_size})
        write_json(stage / 'files.json', hashes_out)
        require(git('rev-parse', 'HEAD') == head and not git('status', '--porcelain'), 'product changed during staging')
        require(not DEST.exists(), 'destination appeared during staging')
        stage.rename(DEST)
    print(json.dumps({'head': head, 'tree': tree, 'files': len(hashes_out) + 1,
                      'visual': measured['allCaptures'], 'preservedProviderImages': len(preserved),
                      'gpuAssertions': sum(row['assertions'] for row in gpu),
                      'androidScenes': len(android['scenes']), 'androidChecks': len(android['checks'])}))


if __name__ == '__main__':
    main()
