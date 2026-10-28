#!/usr/bin/env python3
"""Validate and atomically stage completed IconAction evidence, locally only.

Source the absolute pr16-env.sh before invoking. --inputs is a JSON object of
explicit absolute paths: preflight, checkLogs, builds, gpu, manifest, android,
cleanup, androidDriver, source, sourceRoot, raster, manager, preservation108,
preservation96, baseline108, baseline96, releaseReceipt, archiveCache,
and logs (a nonempty list of explicitly selected source-contract/RED/preparation
logs). Optional historical192 retains an old receipt as historical evidence only.
No subprocess other than read-only git is executed. No network or devices.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SOURCE = '687f282e8625c6b8d11ff58211a90524be2e4317'
CHECKS = {'check-deps', 'tool-tests', 'codegen', 'theme-pack', 'design-system',
          'i18n', 'icons', 'vector', 'parity', 'capability', 'format', 'analyze', 'tests'}
PROFILES = {'iconAction': 80, 'headerAction': 64}
LIMITS = [
    'Chromium post-touch-up sticky hover remains UNMATCHED/PENDING; it is not an approved platform exception.',
    'Header Chromium UA outline:auto pixels remain UNMATCHED/PENDING. Source input retention and a visible native focus cue do not establish matching rasterization.',
    '36 source/native focus ownership differences remain UNMATCHED/PENDING. Matching callback effects do not close those differences.',
    'Android reverse-tab injection remains UNMATCHED/PENDING: API36 keycombination 59,61 advanced forward in the retained diagnostics. Acceptance uses the explicitly committed ordinary-forward sequence; reverse keyboard navigation is not certified.',
    'The three native connection-route actions adopt the canonical source profile and are exercised with synthetic offline services and an injected camera body. Web route, production camera and network parity are not claimed.',
    'Back and Close counters observe actual route-pop effects; they do not independently count raw callback invocations. GPU image-change assertions do not read exact numeric counter text.',
    '144 comparisons cover source-measured control regions, not the surrounding Web page. Raw nonzero differences are retained without an equality gate or fitted threshold.',
    '892 manual metric matches, 0 duplicate button matches and 11 platform control matches remain in the family inventory. Source coverage is not implementation completion; the overall 99.5% visual target remains unfinished.',
    'Historical108 scores and historical192 provider comparisons are retained separately. Their equality is not assumed for this candidate.',
    'No publication, deployment, release, network access, product write, git write or device operation occurs in this staging script.',
]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


common = module('icon_evidence_sanitizer', ROOT / 'scripts/reported-families-publish.py')


def digest(path):
    path = Path(path)
    require(not path.is_symlink() and stat.S_ISREG(path.stat().st_mode), 'missing/linked/nonregular input: ' + path.name)
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def safe_relative(value):
    path = PurePosixPath(value)
    require(isinstance(value, str) and value and not path.is_absolute()
            and '..' not in path.parts and '\\' not in value, 'unsafe relative evidence path')
    return path


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], text=True,
                                   env=dict(os.environ, GIT_OPTIONAL_LOCKS='0')).strip()


def identity(repo, head, tree):
    require(re.fullmatch('[0-9a-f]{40}', head) and re.fullmatch('[0-9a-f]{40}', tree), 'full head/tree required')
    actual = {'head': git(repo, 'rev-parse', 'HEAD'), 'tree': git(repo, 'rev-parse', 'HEAD^{tree}')}
    require(actual == {'head': head, 'tree': tree} and not git(repo, 'status', '--porcelain'),
            'exact clean current candidate required; no post-runtime allowance')
    return actual


class Inputs:
    """Read each byte identity once, recheck it before publishing any output."""
    def __init__(self):
        self.raw = {}
        self.copies = {}
        self.generated = {}

    def hash(self, file):
        file = Path(file)
        value = digest(file)
        key = str(file.absolute())
        require(key not in self.raw or self.raw[key] == value, 'input changed during collection: ' + file.name)
        self.raw[key] = value
        return value

    def text(self, file):
        self.hash(file)
        return Path(file).read_text()

    def json(self, file):
        return json.loads(self.text(file), parse_constant=lambda x: (_ for _ in ()).throw(ValueError('nonfinite JSON')))

    def png(self, file):
        self.hash(file)
        with Image.open(file) as picture:
            require(picture.format == 'PNG' and min(picture.size) > 0, 'invalid PNG')
            for value in picture.info.values():
                if isinstance(value, str):
                    require(common.clean_text(value) == value, 'private PNG metadata')
            size = list(picture.size)
            picture.load()
        return size

    def copy(self, file, destination):
        destination = str(safe_relative(destination))
        require(destination not in self.copies and destination not in self.generated, 'duplicate staged output')
        self.hash(file)
        self.copies[destination] = Path(file)

    def emit(self, destination, data):
        require(destination not in self.copies and destination not in self.generated, 'duplicate staged output')
        safe_relative(destination)
        self.generated[destination] = data

    def keep_json(self, file, destination):
        data = self.json(file)
        self.copy(file, destination)
        return data

    def keep_png(self, file, destination):
        size = self.png(file)
        self.copy(file, destination)
        return size

    def recheck(self):
        require(all(digest(Path(path)) == value for path, value in self.raw.items()), 'an input changed after validation')

    def write(self, target):
        records = []
        for name, source in sorted(self.copies.items()):
            raw_hash = self.hash(source)
            if source.suffix == '.png':
                self.png(source)
                data = source.read_bytes()
            elif source.suffix == '.json':
                data = (json.dumps(common.clean(self.json(source)), ensure_ascii=False, indent=2, allow_nan=False) + '\n').encode()
            else:
                data = common.clean_text(self.text(source)).encode()
            file = target / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(data)
            records.append({'path': name, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data),
                            'rawSha256': raw_hash, 'rawInput': common.clean_text(str(source.absolute())),
                            'sanitized': raw_hash != hashlib.sha256(data).hexdigest()})
        for name, value in sorted(self.generated.items()):
            data = (json.dumps(common.clean(value), ensure_ascii=False, indent=2, allow_nan=False) + '\n').encode()
            file = target / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(data)
            records.append({'path': name, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data),
                            'rawSha256': None, 'generated': True})
        return records


def raw_delta(a, b):
    require(a.size == b.size, 'raw delta requires equal-sized regions')
    delta = ImageChops.difference(a.convert('RGBA'), b.convert('RGBA'))
    pixels = list(delta.getdata())
    return {'comparedPixels': len(pixels), 'changedPixels': sum(any(p) for p in pixels),
            'maxChannelError': max(max(p) for p in pixels),
            'meanAbsoluteRgbaError': sum(sum(p) for p in pixels) / (len(pixels) * 4)}


def exact_png_set(folder, expected):
    require({p.name for p in folder.glob('*.png')} == set(expected), 'actual PNG set differs: ' + folder.name)


def validate_builds(i, folder, head, tree):
    require(i.text(folder / 'runtime-head.txt').strip() == head
            and i.text(folder / 'runtime-tree.txt').strip() == tree, 'build head/tree differs')
    for marker in ('linux-fixture.ready', 'android-fixture.ready', 'normal.ready'):
        i.hash(folder / marker)
    rows = []
    for name in ('android-fixture.apk', 'android-normal.apk', 'linux-fixture/dsh_flutter', 'linux-normal/dsh_flutter'):
        log = name.split('/')[0] if '/' in name else name.removesuffix('.apk')
        log_file = folder / (log + '.log')
        success = [line.strip() for line in i.text(log_file).splitlines() if 'Built ' in line]
        require(success, 'build success line absent: ' + name)
        i.copy(log_file, 'builds/' + log_file.name)
        row = {'name': name, 'sha256': i.hash(folder / name), 'successLine': success[-1]}
        if '/' in name:
            row['applicationLibrarySha256'] = i.hash((folder / name).parent / 'lib/libapp.so')
        rows.append(row)
    i.copy(folder / 'runtime-head.txt', 'builds/runtime-head.txt')
    i.copy(folder / 'runtime-tree.txt', 'builds/runtime-tree.txt')
    return {r['name']: r for r in rows}


def validate_gpu(i, folder, manifest, manifest_hash, builds, head, tree):
    data = i.keep_json(folder / 'runtime.json', 'gpu/runtime.json')
    expected_identity = {'runtimeHead': head, 'runtimeTree': tree, 'manifestSha256': manifest_hash,
                         'executableSha256': builds['linux-fixture/dsh_flutter']['sha256'],
                         'applicationLibrarySha256': builds['linux-fixture/dsh_flutter']['applicationLibrarySha256']}
    require(all(data.get(k) == v for k, v in expected_identity.items())
            and data.get('binaryBefore') == data.get('binaryAfter') == expected_identity,
            'GPU before/after runtime/binary identity differs')
    require(data.get('status') == 'passed' and data.get('exitCode') == 0
            and data.get('binaryUnchanged') is True and data.get('ownedPidsAbsent') is True
            and data.get('ownedFixturePidsRemaining') == [], 'GPU replay/cleanup incomplete')
    require(i.json(folder / 'cases.json') == manifest, 'GPU replayed a different manifest')
    i.copy(folder / 'cases.json', 'gpu/cases.json')
    assertions, shots = 0, set()
    require(len(manifest['cases']) == 4 and len({c['id'] for c in manifest['cases']}) == 4,
            'four distinct viewport/theme GPU cases required')
    require({(c['width'] < 600, c['theme']) for c in manifest['cases']} ==
            {(False, 'light'), (False, 'dark'), (True, 'light'), (True, 'dark')}, 'GPU theme/viewport matrix differs')
    for case in manifest['cases']:
        key = case['id']
        safe_relative(key)
        env = i.keep_json(folder / key / 'environment.json', f'gpu/{key}/environment.json')
        pids = i.keep_json(folder / key / 'pids.json', f'gpu/{key}/pids.json')
        expected = [s['expect'] for s in case['app'] if 'expect' in s]
        actual = env.get('captureAssertions', [])
        require(len(actual) == len(expected) and all(a.get('passed') is True and
                all(a.get(k) == v for k, v in e.items()) for a, e in zip(actual, expected)), 'GPU assertion contract differs')
        require(env.get('backend') == 'native-wayland' and env.get('pairedHost') is False
                and env.get('size') == [case['width'], case['height']]
                and '/dev/dri/renderD128' in env.get('appRenderDevices', [])
                and not re.search('llvmpipe|softpipe|swrast|software', env.get('renderer', ''), re.I), 'hardware GPU evidence missing')
        require(pids and all(type(pid) is int and pid > 1 and not Path('/proc', str(pid)).exists()
                             for pid in pids.values()), 'recorded owned GPU PID remains')
        names = [s['capture'] + '.png' for s in case['app'] if 'capture' in s]
        require(len(names) == len(set(names)), 'duplicate named GPU capture')
        exact_png_set(folder / key, names)
        for name in names:
            require(i.keep_png(folder / key / name, f'gpu/{key}/{name}') == [case['width'], case['height']],
                    'GPU actual screenshot dimensions differ')
            shots.add(key + '/' + name)
        require(i.keep_png(folder / (key + '.png'), f'gpu/{key}.png') == [case['width'], case['height']],
                'GPU final screenshot dimensions differ')
        shots.add(key + '.png')
        assertions += len(actual)
    exact_png_set(folder, [c['id'] + '.png' for c in manifest['cases']])
    require(assertions == data.get('totalAssertions') == data.get('totalPassedAssertions') == 76
            and len(shots) == data.get('totalScreenshots') == 76, 'derived GPU output/count contract differs')
    runtime_cases = {row['id']: row for row in data.get('cases', [])}
    require(len(runtime_cases) == len(data.get('cases', [])) == len(manifest['cases']), 'GPU case runtime records missing/duplicate')
    for case in manifest['cases']:
        row = runtime_cases[case['id']]
        expected_inputs = Counter(k for step in case['app'] for k in step
                                  if k in ('move', 'click', 'secondaryClick', 'drag', 'scroll', 'keys', 'text'))
        expected_shots = [case['id'] + '/' + step['capture'] + '.png' for step in case['app'] if 'capture' in step]
        expected_shots.append(case['id'] + '.png')
        expected_assertions = sum('expect' in step for step in case['app'])
        require(row.get('inputCounts') == dict(expected_inputs) and row.get('inputCount') == sum(expected_inputs.values())
                and row.get('screenshots') == expected_shots and row.get('assertionCount') == row.get('passedAssertions') == expected_assertions
                and row.get('assertionsMatchManifest') is True and row.get('ownedPidsAbsent') is True,
                'GPU actual case input/screenshot/assertion record differs from literal manifest')
    return {'assertions': assertions, 'pngs': len(shots), 'hardware': True}


def android_contract(manifest):
    steps = manifest['android']['steps']
    scenes, checks, inputs = [], [], []
    for step in steps:
        require(isinstance(step, dict) and len(step) == 1, 'ambiguous Android manifest step')
        op, value = next(iter(step.items()))
        if op == 'capture':
            safe_relative(value)
            scenes.append(value)
        elif op == 'expect':
            checks.extend('Visible: ' + label for label in value)
        elif op == 'sourceButton':
            checks.append('Source-sized clickable action: ' + value)
        elif op == 'focused':
            checks.append('Keyboard focuses the real action: ' + value)
        else:
            require(op in ('tap', 'key', 'chord'), 'unknown Android manifest operation')
            inputs.append((op, value))
    require(len(scenes) == len(set(scenes)) == 12 and inputs and len(checks) == 27,
            'literal Android contract differs from bounded acceptance')
    for op in ('tap', 'focused'):
        labels = [step[op] for step in steps if op in step]
        require(len(labels) == 3 and set(labels) == {'Settings', 'Back', 'Close'},
                'each actual native action needs exactly one pointer and one focused-subtree proof')
    return scenes, checks, inputs


def validate_android(i, folder, cleanup_path, driver, manifest, manifest_hash, builds, head, tree, recipe):
    data = i.keep_json(folder / 'receipt.json', 'android/receipt.json')
    cleanup = i.keep_json(cleanup_path, 'android/cleanup.json')
    scenes, checks, inputs = android_contract(manifest)
    for record in (data, cleanup):
        require(record.get('passed') is True and record.get('runtimeHead') == head and record.get('runtimeTree') == tree
                and record.get('manifestSha256') == manifest_hash and record.get('avd') == 'whalee-api36'
                and record.get('serial') == 'emulator-5560' and record.get('androidApi') == '36'
                and record.get('adbdShellUid') == '2000' and record.get('displayOverrideApplied') is False
                and record.get('adbRootUsed') is False, 'Android identity/ownership/default display proof incomplete')
    require(data.get('driverSha256') == i.hash(driver), 'Android driver identity differs')
    i.copy(driver, 'tools/android-driver.py')
    fixture, normal = builds['android-fixture.apk']['sha256'], builds['android-normal.apk']['sha256']
    require(data.get('apkSha256') == data.get('installedFixtureSha256') == fixture
            and i.hash(folder / 'installed-fixture.apk') == fixture, 'fixture APK install readback differs')
    require(data.get('scenes') == scenes and data.get('contract') == {
        'sceneCount': len(scenes), 'scenes': scenes, 'inputCount': len(inputs), 'checkCount': len(checks)}, 'Android executed capture contract differs')
    require(len(data.get('checks', [])) == len(checks) and all(a.get('assertion') == e and a.get('passed') is True
            for a, e in zip(data['checks'], checks)), 'Android checks incomplete or reordered')
    actual_inputs = data.get('inputs', [])
    require(len(actual_inputs) == len(inputs), 'Android input count differs')
    for a, (op, value) in zip(actual_inputs, inputs):
        if op == 'tap':
            bounds = a.get('bounds', [])
            require(a.get('label') == value and len(bounds) == 4 and a.get('semanticClickable') == 'true'
                    and a.get('tap') == [(bounds[0] + bounds[2]) // 2, (bounds[1] + bounds[3]) // 2], 'Android tap did not use actual semantic bounds')
        else:
            require(a.get('keycode' if op == 'key' else 'keycombination') == value, 'Android keyboard inputs differ')
    require(data.get('geometryProofs') and all(p.get('passed') is True and p.get('clickable') == 'true'
            for p in data['geometryProofs']), 'source-sized Android geometry proof missing')
    physical_density = re.fullmatch(r'Physical density:\s*(\d+)', data.get('displayDensity', ''))
    require(physical_density is not None and 'Override' not in data.get('displaySize', ''), 'unmodified physical Android density/size missing')
    density = int(physical_density[1]) / 160
    for proof in data['geometryProofs']:
        bounds = proof.get('bounds', [])
        require(len(bounds) == 4 and proof.get('density') == density
                and proof.get('sourceLogicalSize') == [recipe['width'], recipe['height']]
                and abs((bounds[2] - bounds[0]) - recipe['width'] * density) <= 1
                and abs((bounds[3] - bounds[1]) - recipe['height'] * density) <= 1,
                'Android geometry differs from generated source recipe and physical density')
    focused = [p for p in data['geometryProofs'] if 'keyboardFocusNode' in p]
    require({p['label'] for p in focused} == {'Settings', 'Back', 'Close'} and len(focused) == 3
            and all(p['keyboardFocusNode'].get('sameBoundsAsLabeledAction') is True for p in focused), 'action subtree keyboard-focus proof missing')
    exact_png_set(folder, [s + '.png' for s in scenes])
    for scene in scenes:
        i.keep_png(folder / (scene + '.png'), 'android/' + scene + '.png')
        xml = folder / (scene + '.xml')
        import xml.etree.ElementTree as ET
        ET.fromstring(i.text(xml))
        i.copy(xml, 'android/' + scene + '.xml')
    require(cleanup.get('normalApkLocalSha256') == cleanup.get('normalApkInstalledSha256') == normal
            and i.hash(folder / 'installed-normal.apk') == normal
            and all(cleanup.get(k) is True for k in ('normalApkRestored', 'normalAppForceStopped', 'ownedEmulatorStopped', 'sharedAdbRetained')),
            'normal APK restoration/force-stop/owned cleanup incomplete')
    old_pids, before_adb, after_adb = (cleanup.get(k) for k in ('ownedEmulatorPidsBefore', 'sharedAdbPidsBefore', 'sharedAdbPidsAfter'))
    require(old_pids and before_adb and after_adb and set(before_adb) <= set(after_adb)
            and all(type(p) is int and p > 1 and not Path('/proc', str(p)).exists() for p in old_pids), 'owned emulator PID/shared ADB evidence incomplete')
    return {'captures': len(scenes), 'inputs': len(inputs), 'checks': len(checks), 'cleanupPassed': True}


def validate_release(i, repo, receipt_path, archive_cache):
    receipt = i.keep_json(receipt_path, 'source/release-inputs.json')
    lock = i.keep_json(repo / 'tool/design-system/sources.lock.json', 'source/sources.lock.json')
    ledger = i.keep_json(repo / 'tool/design-system/source-inventory.generated.json', 'source/source-inventory.generated.json')
    require(lock.get('referenceCommit') == receipt.get('referenceCommit') == ledger.get('referenceCommit') == SOURCE
            and receipt.get('allPassed') is True and receipt.get('verificationInputsUnchanged') is True, 'pinned completed release reconstruction required')
    bindings = {'sourceLockSha256': 'sources.lock.json', 'sourceInventorySha256': 'source-inventory.generated.json',
                'verificationToolSha256': 'verify_release_inputs.py', 'publishedVerifierSha256': 'published.py',
                'inventoryVerifierSha256': 'source_inventory.py'}
    for key, name in bindings.items():
        require(receipt.get(key) == i.hash(repo / 'tool/design-system' / name), 'stale release verifier binding: ' + name)
    published = module('icon_stage_published', repo / 'tool/design-system/published.py')
    inventory = module('icon_stage_inventory', repo / 'tool/design-system/source_inventory.py')
    inventory.check_snapshots(ledger, repo)
    rows = {row['name']: row for row in receipt.get('packages', [])}
    require(len(rows) == len(receipt.get('packages', [])) == len(lock['packages']) == receipt.get('packageCount') == 13,
            'thirteen distinct integrity-verified archives required')
    verified = 0
    for package in lock['packages']:
        row = rows[package['name']]
        require(row.get('verified') is True and row.get('archiveUnchanged') is True
                and all(row.get(k) == package[k] for k in ('version', 'tarball', 'integrity'))
                and row.get('snapshotFiles') == len(package['files']), 'release row does not bind current lock')
        archive = archive_cache / str(safe_relative(row['archiveFile']))
        require(i.hash(archive) == row['archiveSha256'], 'actual retained archive bytes differ')
        folder = repo / 'tool/design-system/upstream' / str(safe_relative(package['snapshotFolder']))
        actual_outputs = published.verify_snapshot(archive, package, folder)
        require(set(actual_outputs) == set(package['files']), 'reconstructed output set differs')
        for name, value in package['files'].items():
            file = folder / str(safe_relative(name))
            require(i.hash(file) == value, 'retained reconstructed output hash differs')
            i.copy(file, 'source/upstream/' + package['snapshotFolder'] + '/' + name)
        verified += len(actual_outputs)
    require(verified == receipt.get('verifiedSnapshotFiles') == 85, '85 reconstructed outputs required')
    policy_file = repo / 'tool/design-system/families.json'
    policy = i.keep_json(policy_file, 'source/families.json')
    guard = module('icon_stage_guard', repo / 'tool/design-system/check.py')
    guard.validate_contract(policy)
    counts, failures = guard.inspect(repo, policy)
    require(not failures, 'current component family guard failed')
    total = Counter()
    for row in counts.values():
        total.update(row)
    require(total['manual-metric'] == 892 and total['duplicate-button'] == 0 and total['platform-control'] == 11,
            'current actual family debt differs from 892/0/11')
    for name in ('published.py', 'source_inventory.py', 'check.py', 'verify_release_inputs.py', 'generate.py'):
        i.copy(repo / 'tool/design-system' / name, 'tools/' + name)
    i.emit('source/actual-family-counts.json', {'perFile': counts, 'totals': dict(total)})
    total['duplicate-button'] = total['duplicate-button']
    return lock, ledger['summary'], dict(total)


def validate_source(i, folder, source_root, repo, lock, release=None):
    provenance = i.keep_json(folder / 'provenance.json', 'profiles/source/provenance.json')
    trace = i.keep_json(folder / 'source-trace.json', 'profiles/source/source-trace.json')
    require(trace.get('passed') is True and trace.get('provenance') == provenance
            and provenance.get('referenceCommit') == SOURCE and git(source_root, 'rev-parse', 'HEAD') == SOURCE,
            'actual published-source provenance/pin differs')
    package_map = {p['name'].removeprefix('@deepseek-ai/dsh-client-ui-'): p for p in lock['packages']}
    for name, row in provenance['packages'].items():
        package = package_map[name]
        require(row['version'] == package['version'] and row['integrity'] == package['integrity']
                and row['publishedBundleSha256'] == package['publishedBundleSha256'], 'source bundle identity differs')
        if release is not None:
            actual_archive = next(p for p in release['packages'] if p['name'] == package['name'])
            require(row['archiveSha256'] == actual_archive['archiveSha256'], 'source actual archive bytes differ')
    for name, row in provenance['sourceFiles'].items():
        require(i.hash(source_root / str(safe_relative(name))) == row['sha256'], 'actual source TS/CSS hash differs')
    for font in provenance['fonts']:
        require(i.hash(repo / 'tool/parity-fonts' / str(safe_relative(font['file']))) == font['sha256'], 'actual source font bytes differ')
    snapshots = {}
    require(len(trace['traces']) == 8, 'source theme/DPR/input matrix incomplete')
    require({(t['theme'], t['density'], t['input']) for t in trace['traces']} ==
            {(t, d, p) for t in ('light', 'dark') for d in (1, 2.625) for p in ('mouse', 'touch')}, 'source matrix differs')
    for t in trace['traces']:
        require(t.get('chromium') and not t.get('errors') and t.get('checks')
                and all(c.get('passed') is True for c in t['checks']), 'source browser assertions incomplete')
        for s in t['snapshots']:
            name = s['file']
            require(name not in snapshots, 'duplicate source snapshot')
            safe_relative(name)
            size = i.keep_png(folder / name, 'profiles/source/' + name)
            require(size == [round(t['viewport']['width'] * t['density']), round(t['viewport']['height'] * t['density'])],
                    'source viewport/DPR dimensions differ')
            snapshots[name] = {**s, 'theme': t['theme'], 'density': t['density'], 'input': t['input']}
    require(dict(Counter(s['profile'] for s in snapshots.values())) == PROFILES, 'actual source profile counts differ')
    exact_png_set(folder, snapshots)
    i.copy(repo / 'tool/design-system/capture-icon-actions.mjs', 'tools/capture-icon-actions.mjs')
    for name in ('plugin-manager.js', 'sidebar.js'):
        file = folder / 'host' / name
        package = provenance['packages'][name.removesuffix('.js')]
        require(i.hash(file) == package['instrumentedSha256'], 'source-only measurement instrumentation differs')
        i.copy(file, 'profiles/source/host/' + name)
    return snapshots


def validate_raster(i, folder, snapshots, source_folder, head, tree):
    receipt = i.keep_json(folder / 'receipt.json', 'profiles/raster/receipt.json')
    comparison = i.keep_json(folder / 'comparison.json', 'profiles/raster/comparison.json')
    frames = i.keep_json(folder / 'flutter/frames.json', 'profiles/raster/flutter/frames.json')
    for data in (receipt, comparison, frames):
        require(data.get('head') == head and data.get('tree') == tree, 'raster identity differs from exact current tree')
    require(receipt.get('status') == 'captured-and-compared' and receipt.get('noPixelFittingOrAcceptanceThreshold') is True
            and frames.get('mode') == 'export' and receipt.get('comparedFrames') == comparison.get('comparedFrames') == 144,
            'completed uncensored profile comparison required')
    require(receipt.get('profiles') == comparison.get('profiles') == PROFILES, 'raster profile counts differ')
    outputs = {str(p.relative_to(folder)) for p in folder.rglob('*') if p.is_file() and p != folder / 'receipt.json'}
    require(outputs == set(receipt['outputSha256']), 'raster actual output set differs from hash receipt')
    for name, value in receipt['outputSha256'].items():
        file = folder / str(safe_relative(name))
        require(i.hash(file) == value, 'raster output hash differs')
        if name not in ('comparison.json', 'flutter/frames.json'):
            if file.suffix == '.png':
                i.png(file)
            i.copy(file, 'profiles/raster/' + name)
    for name, value in receipt['inputSha256'].items():
        require(Path(name).is_absolute() and i.hash(Path(name)) == value, 'raster source/product/renderer input hash changed')
    require(frames.get('sourceTraceSha256') == i.hash(source_folder / 'source-trace.json')
            and frames.get('sourceProvenanceSha256') == i.hash(source_folder / 'provenance.json'), 'raster source trace binding differs')
    rows = comparison['rows']
    require(len(rows) == len(frames['frames']) == 144 and {r['sourceFile'] for r in rows} == set(snapshots)
            and len({r['sourceFile'] for r in rows}) == 144, 'raster mappings incomplete/duplicate')
    frame_map = {r['sourceFile']: r for r in frames['frames']}
    reaches = {}
    for source in snapshots.values():
        actual = source['actual']
        reach = float(actual['outlineWidth'].removesuffix('px')) + float(actual['outlineOffset'].removesuffix('px'))
        reaches[source['profile']] = max(reach, reaches.get(source['profile'], 0))
    for row in rows:
        s, name = snapshots[row['sourceFile']], row['sourceFile']
        require(all(row.get(k) == v for k, v in frame_map[name].items())
                and all(row.get(k) == s[k] for k in ('profile', 'state', 'theme', 'density', 'input'))
                and row['sourceComputed'] == s['actual'] and row['sourceCalls'] == s['calls'], 'raster row/source metadata differs')
        source, actual = source_folder / name, folder / 'flutter' / row['flutterFile']
        require(i.hash(source) == row['sourceSha256'] and i.hash(actual) == row['flutterSha256'], 'raster raw fullframe hash differs')
        rect = row['cropPhysical']
        require(len(rect) == 4 and all(type(v) is int for v in rect), 'invalid source crop')
        bounds, density, reach = s['actual']['bounds'], row['density'], reaches[row['profile']]
        source_rect = [math.floor((bounds['x'] - reach) * density + 1e-4),
                       math.floor((bounds['y'] - reach) * density + 1e-4),
                       math.ceil((bounds['x'] + bounds['width'] + reach) * density - 1e-4),
                       math.ceil((bounds['y'] + bounds['height'] + reach) * density - 1e-4)]
        require(rect == source_rect and row['cropReachCss'] == reach,
                'profile crop must derive from actual source bounds/maximum outline, not fitted pixels')
        with Image.open(source) as a, Image.open(actual) as b:
            for image in (a, b):
                require(0 <= rect[0] < rect[2] <= image.width and 0 <= rect[1] < rect[3] <= image.height, 'profile crop outside actual image')
            crop_a, crop_b = a.convert('RGBA').crop(rect), b.convert('RGBA').crop(rect)
            delta = raw_delta(crop_a, crop_b)
            require(row['physicalSurfaces'] == {'source': list(a.size), 'flutter': list(b.size)}
                    and row['surfaceDimensionsMatch'] == (a.size == b.size), 'raw surface dimensions differ from report')
        require(all(row[k] == v for k, v in delta.items()) and row['exactScopedRgbaEquality'] == (delta['changedPixels'] == 0),
                'profile raw pixel metrics differ from actual images')
        pair_folder = folder / 'pairs' / Path(name).stem
        for label, image in [('source', crop_a), ('flutter', crop_b), ('rgba-difference', ImageChops.difference(crop_a, crop_b))]:
            with Image.open(pair_folder / (label + '.png')) as recorded:
                require(recorded.convert('RGBA').tobytes() == image.tobytes() and recorded.size == image.size, 'profile region/delta image differs')
        require(row.get('callbackCountsMatch') is True and row['sourceCalls'] == row['flutterCalls'], 'source/native callback effects differ')
        require(row['focusOwnershipMatches'] == (bool(row['sourceComputed']['focused']) == row['flutterFocused']), 'focus ownership comparison is censored')
        if not row['focusOwnershipMatches']:
            require(any('focus' in reason.lower() and 'PENDING' in reason for reason in row.get('pending', [])), 'focus difference lost pending label')
    require(sum(not r['focusOwnershipMatches'] for r in rows) == 36, 'actual 36 focus differences must remain explicit')
    require(comparison['exactCrops'] == sum(r['exactScopedRgbaEquality'] for r in rows)
            and comparison['knownPendingFrames'] == sum(bool(r['pending']) for r in rows), 'profile aggregate comparison differs')
    require(any(('sticky' in p.lower() or ('touch' in p.lower() and 'hover' in p.lower())) for p in receipt['pending'])
            and any('outline' in p.lower() for p in receipt['pending']), 'known sticky-hover/UA-outline limits missing')
    return {k: comparison[k] for k in ('comparedFrames', 'profiles', 'exactCrops', 'knownPendingFrames')}


def capture_cohort(i, folder, count, destination, head=None, tree=None, baseline=None):
    summary = i.keep_json(folder / 'summary.json', destination + '/summary.json')
    plan_file = folder / 'flutter-plan.json'
    plan = i.keep_json(plan_file, destination + '/flutter-plan.json')
    rows = summary.get('cases', [])
    require(len(rows) == len({r['key'] for r in rows}) == summary.get('counts', {}).get('compared') == count,
            'actual complete capture cohort differs: ' + destination)
    identity_row = None
    if head is not None:
        identity_row = i.keep_json(folder / 'capture-identity.json', destination + '/capture-identity.json')
        require(identity_row.get('head', identity_row.get('headAtCompletion')) == head
                and identity_row.get('tree', identity_row.get('treeAtCompletion')) == tree
                and identity_row.get('captured') == count, 'current cohort capture identity differs')
        if destination == 'manager':
            expected_identity = {'head': head, 'tree': tree}
            require(identity_row.get('identityBefore') == identity_row.get('identityAfter') == expected_identity,
                    'Manager before/after clean identity missing')
    keys = {r['key'] for r in rows}
    if destination == 'manager' and head is not None:
        require(set(identity_row.get('sourcePngSha256', {})) == set(identity_row.get('flutterPngSha256', {})) == keys,
                'Manager exact provider hash sets differ')
    require(len(plan.get('entries', [])) == count and {entry['key'] for entry in plan['entries']} == keys,
            'capture plan and actual summary/output identities differ')
    if baseline is not None:
        baseline_plan = baseline / 'flutter-plan.json'
        require(identity_row.get('sourcePlanSha256') == i.hash(baseline_plan)
                and plan['entries'] == i.json(baseline_plan)['entries'], 'original immutable source plan differs')
    for provider in ('react', 'flutter'):
        exact_png_set(folder / 'visual-testing-results' / provider, [key + '.png' for key in keys])
    comparisons = []
    for row in rows:
        key = row['key']
        safe_relative(key)
        for field in ('nonTextPct', 'pixelPerfectPct', 'rgbPct'):
            require(type(row.get(field)) in (int, float) and math.isfinite(row[field]) and 0 <= row[field] <= 100,
                    'invalid measured metric')
        for provider, field in (('react', 'sizeReact'), ('flutter', 'sizeFlutter')):
            file = folder / 'visual-testing-results' / provider / (key + '.png')
            require(i.keep_png(file, destination + '/' + provider + '/' + file.name) == row[field], 'cohort PNG dimensions differ')
            meta_file = file.with_suffix('.metadata.json')
            meta = i.keep_json(meta_file, destination + '/' + provider + '/' + meta_file.name)
            require(meta.get('provider') == provider and meta.get('captureKey') == key, 'capture metadata differs')
            if provider == 'react':
                require(meta.get('react', {}).get('dshCommit') == SOURCE, 'reference capture pin differs')
            if destination == 'manager' and head is not None:
                require(identity_row.get('sourcePngSha256' if provider == 'react' else 'flutterPngSha256', {}).get(key)
                        == i.hash(file), 'Manager source/Flutter output hash identity differs')
            if baseline is not None:
                old = baseline / 'visual-testing-results' / provider / file.name
                i.png(old)
                if provider == 'react':
                    require(i.hash(old) == i.hash(file), 'immutable original source image changed')
                with Image.open(old) as a, Image.open(file) as b:
                    same_size = a.size == b.size
                    exact = same_size and raw_delta(a, b)['changedPixels'] == 0
                comparisons.append({'provider': provider, 'key': key, 'dimensionsEqual': same_size,
                                    'rgbaEqual': exact, 'oldSha256': i.hash(old), 'newSha256': i.hash(file)})
    if baseline is not None:
        recorded = identity_row.get('comparisons')
        require(isinstance(recorded, list) and len(recorded) == len(comparisons), 'before/after comparisons absent')
        indexed = {(r['provider'], r['key']): r for r in recorded}
        require(len(indexed) == len(comparisons) and all(indexed.get((r['provider'], r['key'])) == r for r in comparisons),
                'actual cohort before/after identities or raw pixels differ from recorded values')
        require(identity_row.get('rgbaEqual') == sum(r['rgbaEqual'] for r in comparisons), 'preservation summary equality differs')
    metrics = {'compared': count, 'dimensionsEqual': sum(r['sizeReact'] == r['sizeFlutter'] for r in rows),
               'nonTextAtLeast99_5': sum(r['nonTextPct'] >= 99.5 for r in rows),
               'meanNonTextPct': sum(r['nonTextPct'] for r in rows) / count}
    return metrics, comparisons


def stage(args):
    repo, out = args.repo.resolve(), args.out.absolute()
    before = identity(repo, args.head, args.tree)
    require(out.parent.is_dir() and not out.exists() and not out.is_symlink(), 'fresh output under an existing directory required')
    require(not out.resolve().is_relative_to(repo), 'evidence output must be outside the product repository')
    i = Inputs()
    i.hash(Path(__file__))
    i.copy(Path(__file__), 'tools/icon-actions-evidence.py')
    i.copy(ROOT / 'scripts/icon-actions-report.py', 'tools/icon-actions-report.py')
    i.hash(ROOT / 'scripts/reported-families-publish.py')
    config = i.json(args.inputs)
    required = {'preflight', 'checkLogs', 'builds', 'gpu', 'manifest', 'android', 'cleanup', 'androidDriver',
                'source', 'sourceRoot', 'raster', 'manager', 'preservation108', 'preservation96',
                'baseline108', 'baseline96', 'releaseReceipt', 'archiveCache', 'logs'}
    require(required <= set(config) and not (set(config) - required - {'historical192'}), 'explicit inputs keys missing/unknown')
    require(config['logs'] and isinstance(config['logs'], list), 'explicit source-contract/RED/preparation logs required')
    paths = {k: Path(v) for k, v in config.items() if k != 'logs'}
    require(all(p.is_absolute() for p in paths.values()) and all(Path(p).is_absolute() for p in config['logs']),
            'all input paths must be explicit absolute paths')
    full = i.keep_json(paths['preflight'], 'preflight.json')
    require(full.get('headTree') == args.tree and full.get('fast') is False and set(full.get('results', {})) == CHECKS
            and all(r.get('state') == 'ok' for r in full['results'].values()), 'all thirteen final-tree checks must be ok')
    for name in sorted(CHECKS):
        i.copy(paths['checkLogs'] / (name + '.txt'), 'checks/' + name + '.txt')
    for index, path in enumerate(config['logs']):
        i.copy(Path(path), f'focused/{index:02d}-' + Path(path).name)
    builds = validate_builds(i, paths['builds'], args.head, args.tree)
    manifest_path = paths['manifest']
    relative_manifest = manifest_path.relative_to(repo).as_posix()
    manifest = i.keep_json(manifest_path, 'manifest.json')
    manifest_hash = i.hash(manifest_path)
    require(hashlib.sha256(subprocess.check_output(['git', '-C', str(repo), 'show', args.head + ':' + relative_manifest])).hexdigest()
            == manifest_hash, 'manifest differs from committed candidate')
    gpu = validate_gpu(i, paths['gpu'], manifest, manifest_hash, builds, args.head, args.tree)
    recipes = i.keep_json(repo / 'tool/design-system/recipes.generated.json', 'source/recipes.generated.json')
    android = validate_android(i, paths['android'], paths['cleanup'], paths['androidDriver'], manifest, manifest_hash,
                               builds, args.head, args.tree, recipes['metrics']['DshIconActionRecipe'])
    lock, coverage, debt = validate_release(i, repo, paths['releaseReceipt'], paths['archiveCache'])
    snapshots = validate_source(i, paths['source'], paths['sourceRoot'], repo, lock, i.json(paths['releaseReceipt']))
    raster = validate_raster(i, paths['raster'], snapshots, paths['source'], args.head, args.tree)
    baseline, _ = capture_cohort(i, paths['baseline108'], 108, 'history/baseline108')
    visual108, comparisons108 = capture_cohort(i, paths['preservation108'], 108, 'preservation108',
                                              args.head, args.tree, paths['baseline108'])
    capture_cohort(i, paths['baseline96'], 96, 'history/baseline96')
    visual96, comparisons96 = capture_cohort(i, paths['preservation96'], 96, 'preservation96',
                                            args.head, args.tree, paths['baseline96'])
    manager, _ = capture_cohort(i, paths['manager'], 16, 'manager', args.head, args.tree)
    manager_raw = []
    for row in i.json(paths['manager'] / 'summary.json')['cases']:
        key = row['key']
        with Image.open(paths['manager'] / 'visual-testing-results/react' / (key + '.png')) as a, \
                Image.open(paths['manager'] / 'visual-testing-results/flutter' / (key + '.png')) as b:
            delta = raw_delta(a, b) if a.size == b.size else None
            manager_raw.append({'key': key, 'dimensionsEqual': a.size == b.size, 'rawRgbaDelta': delta,
                                'noResizeOrCropFitting': True})
    i.emit('manager/raw-comparison.json', manager_raw)
    if 'historical192' in paths:
        historical = i.keep_json(paths['historical192'], 'history/historical192.json')
        historical_rows = historical if isinstance(historical, list) else historical.get('comparisons', historical.get('preservedProviderImages'))
        require(historical_rows == 192 or (isinstance(historical_rows, list) and len(historical_rows) == 192
                and len({(r.get('provider'), r.get('key')) for r in historical_rows}) == 192),
                'historical192 receipt must identify its actual historical scope')
    i.emit('score-history.json', {'baseline108': baseline, 'current108': visual108, 'current96': visual96,
        'nonTextMeanDelta108': visual108['meanNonTextPct'] - baseline['meanNonTextPct'],
        'current108ProviderRGBAEqual': sum(r['rgbaEqual'] for r in comparisons108),
        'current96ProviderRGBAEqual': sum(r['rgbaEqual'] for r in comparisons96) if comparisons96 else None,
        'historical192IsCurrentAcceptance': False})
    product_trees = {name: git(repo, 'rev-parse', args.head + ':' + name) for name in ('apps', 'features', 'packages')}
    receipt = {'schema': 'whalee-icon-actions-evidence/1', **before, 'runtimeHead': args.head, 'runtimeTree': args.tree,
               'identityBefore': before, 'identityAfter': identity(repo, args.head, args.tree), 'productTrees': product_trees,
               'manifestSha256': manifest_hash, 'builds': list(builds.values()), 'fullChecks': len(CHECKS),
               'gpu': gpu, 'android': android, 'profiles': raster, 'manager': manager,
               'preservation108': visual108, 'preservation96': visual96, 'baseline108': baseline,
               'sourceCoverage': coverage, 'legacyDebt': debt, 'sourcePin': SOURCE,
               'releasePackages': 13, 'releaseFiles': 85, 'allowedPostRuntimeChanges': [],
               'focusOwnershipMismatches': 36, 'limitations': LIMITS, 'published': False}
    i.emit('receipt.json', receipt)
    i.emit('raw-inputs.json', [{'path': path, 'sha256': value} for path, value in sorted(i.raw.items())])
    with tempfile.TemporaryDirectory(prefix='.icon-evidence-', dir=out.parent) as temporary:
        prepared = Path(temporary) / out.name
        prepared.mkdir()
        records = i.write(prepared)
        (prepared / 'files.json').write_text(json.dumps({'schema': 'whalee-sanitized-files/1', 'files': records}, indent=2) + '\n')
        i.recheck()
        identity(repo, args.head, args.tree)
        require(not out.exists(), 'output appeared while staging')
        prepared.rename(out)
    print(json.dumps({'head': args.head, 'tree': args.tree, 'files': len(records), 'stage': str(out), 'published': False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for name in ('repo', 'inputs', 'out'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('head', 'tree'):
        parser.add_argument('--' + name, required=True)
    stage(parser.parse_args())


if __name__ == '__main__':
    main()
