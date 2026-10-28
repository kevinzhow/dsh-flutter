#!/usr/bin/env python3
"""Offline, fail-closed staging of completed loaded PluginCard evidence.

Source the absolute scripts/pr16-env.sh first. No network, builds or native runs;
only read-only git queries and the existing source/metric verifiers are used.
--inputs JSON requires absolute paths for preflight, checkLogs, builds, gpu,
manifest, android, cleanup, androidDriver, source, sourcePlan, providerReceipt, sourceRepo, sourceRoot,
current, releaseReceipt, archiveCache; nonempty logs/history/files lists; and
cohorts {old108,old96,manager16,tag,switch}, each {before,after,count}.
sourceToolHead is the full capture-time Git commit for the original source tool.
Every fresh cohort needs capture-identity.json {head,tree,captured}; the current
224 additionally binds all original PNG hashes in that receipt. --base-head is
an explicit ancestral source for the retained implementation diff.
"""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

shared = module('card_evidence_shared', ROOT / 'scripts/icon-actions-evidence.py')
require, digest, safe_relative, git, identity = (getattr(shared, n) for n in
                                              ('require', 'digest', 'safe_relative', 'git', 'identity'))
Inputs, CHECKS, SOURCE, common = shared.Inputs, shared.CHECKS, shared.SOURCE, shared.common
LIMITS = [
    '本轮仅迁移已加载的 PluginManager 网格／卡片；管理器余下 31 处数值匹配不在本轮范围内。',
    'Highlight 高亮样式保持冻结／待修复；保留 CSS 和覆盖输入不代表已经实现。',
    'Chromium 触摸释放后的粘滞悬停仍未匹配／待修复，未作为平台例外接受。',
    '原生 SVG 等图像格式仍待核对；合成的无效 PNG 仅证明该输入下的回退／恢复。',
    '原版 DOM 与 Flutter 原始组件矩形分别实测；截图尺寸相同不能证明内部几何相同。',
    '描述裁切另有 13 个真实来源输入核对；复杂 Unicode 断行、双向文本和其他平台字体引擎行为仍待覆盖。',
    '224 组完整覆盖不代表视觉完成；原始差异和固定非文字 99.5% 目标与工具通用通过状态分开统计。',
    '旧 Manager 页面可能因卡片迁移而改变；每个提供方的前后原始 RGBA 都重新比较，不假定相同。',
    '脱敏后的源码／工具副本仅供阅读；可执行复现以原始输入哈希和已提交原件为准，脱敏可能改变本机模板 URL。',
    '全部是离线合成数据；不含真实用户截图、请求日志、凭据，也不执行发布、部署或设备操作。',
]


def validate_preflight(full, tree):
    require(full.get('headTree') == tree and full.get('fast') is False
            and set(full.get('results', {})) == CHECKS
            and all(row.get('state') == 'ok' for row in full['results'].values()),
            'all thirteen final-tree checks must be ok; skipped checks are incomplete')


def raw_delta(a, b):
    require(a.size == b.size, 'RGBA comparison requires equal dimensions')
    left, right = np.asarray(a.convert('RGBA'), dtype=np.int16), np.asarray(b.convert('RGBA'), dtype=np.int16)
    delta = np.abs(left - right)
    return {'comparedPixels': int(delta.shape[0] * delta.shape[1]),
            'changedPixels': int(np.count_nonzero(np.any(delta != 0, axis=2))),
            'maxChannelError': int(delta.max()), 'meanAbsoluteRgbaError': float(delta.mean())}


def tree_files(i, folder, destination):
    require(folder.is_dir() and not folder.is_symlink(), 'retained input folder missing: ' + folder.name)
    files = sorted(p for p in folder.rglob('*') if p.is_file())
    require(files, 'empty retained evidence folder')
    binary = []
    for file in files:
        require(not file.is_symlink(), 'linked retained evidence')
        if file.suffix == '.png':
            i.png(file)
        else:
            try:
                i.text(file)
            except UnicodeDecodeError:
                binary.append({'path': file.relative_to(folder).as_posix(), 'sha256': i.hash(file),
                               'bytes': file.stat().st_size, 'rawRetainedLocally': True,
                               'includedInSanitizedStage': False})
                continue
        i.copy(file, destination + '/' + file.relative_to(folder).as_posix())
    if binary:
        i.emit(destination + '/retained-binary-inputs.json', binary)


def validate_gpu(i, folder, manifest, manifest_hash, builds, head, tree):
    data = i.keep_json(folder / 'runtime.json', 'gpu/runtime.json')
    wanted = {'runtimeHead': head, 'runtimeTree': tree, 'manifestSha256': manifest_hash,
              'executableSha256': builds['linux-fixture/dsh_flutter']['sha256'],
              'applicationLibrarySha256': builds['linux-fixture/dsh_flutter']['applicationLibrarySha256']}
    require(all(data.get(k) == v for k, v in wanted.items())
            and data.get('binaryBefore') == data.get('binaryAfter') == wanted,
            'GPU exact runtime/build/manifest identity differs')
    require(data.get('status') == 'passed' and data.get('exitCode') == 0
            and data.get('binaryUnchanged') is True and data.get('ownedPidsAbsent') is True
            and data.get('ownedFixturePidsRemaining') == [], 'GPU failed or owned process remains')
    require(i.keep_json(folder / 'cases.json', 'gpu/cases.json') == manifest, 'GPU literal manifest differs')
    cases = manifest.get('cases', [])
    require(len(cases) == len({c['id'] for c in cases}) == 4
            and {(c['width'] < 600, c['theme']) for c in cases} ==
            {(False, 'light'), (False, 'dark'), (True, 'light'), (True, 'dark')}, 'four-case GPU matrix required')
    actual_rows = {c['id']: c for c in data.get('cases', [])}
    require(len(actual_rows) == len(data.get('cases', [])) == 4, 'GPU runtime cases incomplete/duplicate')
    assertions = pngs = total_inputs = 0
    ordered_inputs = []
    for case in cases:
        key = str(safe_relative(case['id']))
        env = i.keep_json(folder / key / 'environment.json', f'gpu/{key}/environment.json')
        pids = i.keep_json(folder / key / 'pids.json', f'gpu/{key}/pids.json')
        expected = [step['expect'] for step in case['app'] if 'expect' in step]
        actual = env.get('captureAssertions', [])
        require(len(actual) == len(expected) and all(a.get('passed') is True and
                all(a.get(k) == v for k, v in e.items()) for a, e in zip(actual, expected)),
                'GPU assertions missing/reordered/failed')
        require(env.get('backend') == 'native-wayland' and env.get('pairedHost') is False
                and env.get('size') == [case['width'], case['height']]
                and '/dev/dri/renderD128' in env.get('appRenderDevices', [])
                and not re.search('llvmpipe|softpipe|swrast|software', env.get('renderer', ''), re.I),
                'actual hardware GPU evidence required')
        require(pids and all(type(pid) is int and pid > 1 and not Path('/proc', str(pid)).exists()
                             for pid in pids.values()), 'recorded owned GPU PID remains')
        names = [step['capture'] + '.png' for step in case['app'] if 'capture' in step]
        require(len(names) == len(set(names)), 'duplicate GPU screenshot')
        shared.exact_png_set(folder / key, names)
        screenshots = []
        for name in names:
            require(i.keep_png(folder / key / name, f'gpu/{key}/{name}') == [case['width'], case['height']],
                    'GPU screenshot dimensions differ')
            screenshots.append(key + '/' + name)
        require(i.keep_png(folder / (key + '.png'), f'gpu/{key}.png') == [case['width'], case['height']],
                'GPU final dimensions differ')
        screenshots.append(key + '.png')
        inputs = Counter(k for step in case['app'] for k in step if k in
                         ('move', 'click', 'secondaryClick', 'drag', 'scroll', 'keys', 'text'))
        ordered_inputs.append({'case': key, 'literalInputs': [
            {'stepIndex': index, 'operation': op, 'value': value}
            for index, step in enumerate(case['app']) for op, value in step.items()
            if op in ('move', 'click', 'secondaryClick', 'drag', 'scroll', 'keys', 'text')],
            'recordedInputCounts': actual_rows[key].get('inputCounts'),
            'literalAssertionOrder': expected, 'literalScreenshotOrder': screenshots})
        row = actual_rows[key]
        require(row.get('inputCounts') == dict(inputs) and row.get('inputCount') == sum(inputs.values())
                and row.get('screenshots') == screenshots
                and row.get('assertionCount') == row.get('passedAssertions') == len(expected)
                and row.get('assertionsMatchManifest') is True and row.get('ownedPidsAbsent') is True,
                'GPU literal input/capture/assertion order record differs')
        assertions += len(expected); pngs += len(screenshots); total_inputs += sum(inputs.values())
    shared.exact_png_set(folder, [c['id'] + '.png' for c in cases])
    require(assertions == data.get('totalAssertions') == data.get('totalPassedAssertions') == 112
            and pngs == data.get('totalScreenshots') == 80, 'GPU actual scope differs from 112/80')
    i.emit('gpu/input-order.json', ordered_inputs)
    return {'cases': len(cases), 'assertions': assertions, 'pngs': pngs, 'inputs': total_inputs, 'hardware': True}


def android_contract(manifest):
    require(manifest.get('schema') == 'whalee-plugin-cards-native/1'
            and manifest.get('fixtureTarget') == 'test/parity/plugin_cards_main.dart'
            and manifest.get('sourceReferenceCommit') == SOURCE
            and manifest.get('android', {}).get('schema') == 'whalee-plugin-cards-android-steps/1',
            'wrong native Card contract')
    scenes, checks, inputs, proofs = [], [], [], []
    for step in manifest['android']['steps']:
        require(isinstance(step, dict) and len(step) == 1, 'ambiguous Android operation')
        op, value = next(iter(step.items()))
        if op == 'capture':
            safe_relative(value); scenes.append(value)
        elif op in ('expect', 'absent'):
            require(isinstance(value, list) and value and all(isinstance(x, str) and x for x in value), 'empty Android check')
            checks.extend(op + ': ' + label for label in value)
        elif op in ('sourceCard', 'sourceSwitch'):
            checks.append(('Source card layout: ' if op == 'sourceCard' else 'Independent source switch: ') + value['label'])
            proofs.append((op, value))
        elif op == 'focused':
            checks.append('Keyboard focuses independent action: ' + value); proofs.append((op, value))
        else:
            require(op in ('tap', 'tapDisabled', 'tapText', 'edgeTap', 'key'), 'unknown Android operation')
            inputs.append((op, value))
            if op == 'tapText':
                proofs.append((op, value))
    require(len(scenes) == len(set(scenes)) == 17 and len(checks) == 57 and len(inputs) == 30,
            'literal Android scope differs from 17/57/30')
    require(Counter(op for op, value in proofs) == {'sourceCard': 6, 'sourceSwitch': 5, 'focused': 2, 'tapText': 1}
            and {v for op, v in proofs if op == 'focused'} == {'View Synthetic plugin', 'Enable Synthetic plugin'}
            and {v['corner'] for op, v in inputs if op == 'edgeTap'} == {True, False},
            'independent action/geometry/contour coverage incomplete')
    return scenes, checks, inputs, proofs


def validate_android(i, folder, cleanup_path, driver, manifest, manifest_hash, builds, head, tree, recipes):
    scenes, checks, inputs, expected_proofs = android_contract(manifest)
    data = i.keep_json(folder / 'receipt.json', 'android/receipt.json')
    cleanup = i.keep_json(cleanup_path, 'android/cleanup.json')
    require(data.get('schema') == 'whalee-plugin-cards-android-runtime/1', 'wrong Android receipt schema')
    for row in (data, cleanup):
        require(row.get('passed') is True and row.get('runtimeHead') == head and row.get('runtimeTree') == tree
                and row.get('manifestSha256') == manifest_hash and row.get('avd') == 'whalee-api36'
                and row.get('serial') == 'emulator-5560' and row.get('androidApi') == '36'
                and row.get('adbdShellUid') == '2000' and row.get('displayOverrideApplied') is False
                and row.get('adbRootUsed') is False, 'Android exact source/ownership/display receipt missing')
    require(data.get('driverSha256') == i.hash(driver), 'Android driver bytes differ')
    i.copy(driver, 'tools/plugin-cards-android.py')
    fixture, normal = builds['android-fixture.apk']['sha256'], builds['android-normal.apk']['sha256']
    require(data.get('apkSha256') == data.get('installedFixtureSha256') == i.hash(folder / 'installed-fixture.apk') == fixture,
            'installed fixture readback differs')
    require(data.get('contract') == {'sceneCount': len(scenes), 'scenes': scenes, 'inputCount': len(inputs), 'checkCount': len(checks)}
            and data.get('scenes') == scenes and len(data.get('checks', [])) == len(checks)
            and all(a.get('assertion') == e and a.get('passed') is True for a, e in zip(data['checks'], checks)),
            'Android actual capture/check order differs')
    physical = re.fullmatch(r'Physical density:\s*(\d+)', data.get('displayDensity', ''))
    size = re.fullmatch(r'Physical size:\s*(\d+)x(\d+)', data.get('displaySize', ''))
    require(physical is not None and size is not None, 'actual unchanged physical density/size required')
    density, width = int(physical[1]) / 160, int(size[1])
    card, switch = recipes['DshPluginCardRecipe'], recipes['DshSwitchRecipe']
    actual_inputs = data.get('inputs', [])
    require(len(actual_inputs) == len(inputs), 'Android input order/count differs')
    for actual, (op, value) in zip(actual_inputs, inputs):
        if op == 'key':
            require(actual == {'keycode': value}, 'Android key input differs'); continue
        label = value['label'] if op == 'edgeTap' else value
        bounds = actual.get('bounds', [])
        require(actual.get('label') == label and len(bounds) == 4
                and bounds[0] < bounds[2] and bounds[1] < bounds[3], 'Android action label/bounds differ')
        point = [(bounds[0] + bounds[2]) // 2, (bounds[1] + bounds[3]) // 2]
        purpose = 'tap'
        if op == 'edgeTap':
            inset = abs(card['horizontalMargin']) / 4 * density
            point = [round(bounds[0] + inset), round(bounds[1] + inset) if value['corner'] else point[1]]
            purpose = 'outside source contour' if value['corner'] else 'extended side margin'
        elif op == 'tapDisabled':
            purpose = 'disabled switch must absorb without opening'
            require(actual.get('semanticClickable') != 'true', 'disabled switch unexpectedly clickable')
        elif op == 'tapText':
            purpose = 'actual metadata region opens the owning card'
            require(actual.get('semanticClickable') != 'true', 'metadata incorrectly has its own action')
        else:
            require(actual.get('semanticClickable') == 'true', 'real action must own native tap')
        require(actual.get('tap') == point and actual.get('purpose') == purpose, 'Android actual input coordinates/purpose differ')
    proofs = data.get('geometryProofs', [])
    require(len(proofs) == len(expected_proofs), 'Android geometry/focus proofs incomplete')
    last_card = None
    base_height = card['headPadding'] * 2 + card['iconHeight'] + 2 * max(1, int(card['iconBorderWidth'] * density)) / density
    for proof, (op, value) in zip(proofs, expected_proofs):
        bounds = proof.get('bounds', [])
        require(proof.get('passed') is True and len(bounds) == 4, 'failed/malformed native geometry proof')
        if op == 'sourceCard':
            logical = width / density
            inset = min(48, max(24, logical * .04)); content = min(960, logical - inset * 2)
            left = (logical - content) / 2 + card['horizontalMargin']
            require(proof.get('type') == 'card' and proof.get('label') == value['label']
                    and proof.get('density') == density and proof.get('sourceBaseHeight') == base_height
                    and proof.get('expectedLogicalLeft') == left and proof.get('heightMode') == value['height']
                    and proof.get('clickable') == 'true'
                    and abs(bounds[0] - left * density) <= 1 and abs(bounds[2] - (logical - left) * density) <= 1
                    and (abs((bounds[3] - bounds[1]) - base_height * density) <= 1 if value['height'] == 'base'
                         else (bounds[3] - bounds[1]) > base_height * density), 'native card contour/natural layout differs')
            last_card = bounds
        elif op == 'sourceSwitch':
            require(proof.get('type') == 'switch' and proof.get('label') == value['label']
                    and (proof.get('enabled') != 'false') is value['enabled']
                    and proof.get('checked') == str(value['checked']).lower()
                    and abs(bounds[2] - bounds[0] - switch['width'] * density) <= 1
                    and abs(bounds[3] - bounds[1] - switch['height'] * density) <= 1, 'native independent switch proof differs')
        elif op == 'focused':
            require(proof.get('type') == 'focus' and proof.get('label') == value
                    and proof.get('sameBoundsAsLabeledAction') is True and proof.get('focusedBounds') == bounds,
                    'independent native focus owner missing')
        else:
            require(proof.get('type') == 'metadata' and proof.get('card') == last_card and last_card is not None
                    and last_card[0] <= bounds[0] < bounds[2] <= last_card[2]
                    and bounds[1] >= last_card[1] + base_height * density - 1
                    and bounds[3] <= last_card[3] + 1, 'native metadata ownership geometry differs')
    require(data.get('dumpDiagnostics') == [], 'native XML diagnostics unresolved')
    shared.exact_png_set(folder, [name + '.png' for name in scenes])
    for name in scenes:
        require(i.keep_png(folder / (name + '.png'), 'android/' + name + '.png') == [int(size[1]), int(size[2])],
                'Android screenshot is not the complete original physical display')
        xml = folder / (name + '.xml'); ET.fromstring(i.text(xml)); i.copy(xml, 'android/' + name + '.xml')
    require(cleanup.get('normalApkLocalSha256') == cleanup.get('normalApkInstalledSha256') == i.hash(folder / 'installed-normal.apk') == normal
            and all(cleanup.get(k) is True for k in ('normalApkRestored', 'normalAppForceStopped', 'ownedEmulatorStopped', 'sharedAdbRetained')),
            'normal APK readback/restoration/cleanup missing')
    old, before, after = (cleanup.get(k) for k in ('ownedEmulatorPidsBefore', 'sharedAdbPidsBefore', 'sharedAdbPidsAfter'))
    require(old and before and after and set(before) <= set(after)
            and all(type(pid) is int and pid > 1 and not Path('/proc', str(pid)).exists() for pid in old),
            'owned AVD/shared ADB ownership receipt incomplete')
    return {'scenes': len(scenes), 'checks': len(checks), 'inputs': len(inputs), 'geometryProofs': len(proofs), 'cleanupPassed': True}


def validate_release(i, repo, receipt_file, archive_cache):
    receipt = i.keep_json(receipt_file, 'source/release-inputs.json')
    lock = i.keep_json(repo / 'tool/design-system/sources.lock.json', 'source/sources.lock.json')
    ledger = i.keep_json(repo / 'tool/design-system/source-inventory.generated.json', 'source/source-inventory.generated.json')
    require(lock.get('referenceCommit') == receipt.get('referenceCommit') == ledger.get('referenceCommit') == SOURCE
            and receipt.get('allPassed') is True and receipt.get('verificationInputsUnchanged') is True,
            'completed pinned archive reconstruction required')
    for field, name in {'sourceLockSha256': 'sources.lock.json', 'sourceInventorySha256': 'source-inventory.generated.json',
                        'verificationToolSha256': 'verify_release_inputs.py', 'publishedVerifierSha256': 'published.py',
                        'inventoryVerifierSha256': 'source_inventory.py'}.items():
        require(receipt.get(field) == i.hash(repo / 'tool/design-system' / name), 'stale release receipt: ' + name)
    published = module('card_published', repo / 'tool/design-system/published.py')
    inventory = module('card_inventory', repo / 'tool/design-system/source_inventory.py')
    inventory.check_snapshots(ledger, repo)
    rows = {row['name']: row for row in receipt.get('packages', [])}
    require(len(rows) == len(receipt.get('packages', [])) == len(lock['packages']) == receipt.get('packageCount') == 13,
            'thirteen unique release archives required')
    verified = 0
    for package in lock['packages']:
        row = rows[package['name']]
        require(row.get('verified') is True and row.get('archiveUnchanged') is True
                and all(row.get(k) == package[k] for k in ('version', 'tarball', 'integrity'))
                and row.get('snapshotFiles') == len(package['files']), 'release row differs from actual lock')
        archive = archive_cache / str(safe_relative(row['archiveFile']))
        require(i.hash(archive) == row['archiveSha256'], 'archive hash differs')
        folder = repo / 'tool/design-system/upstream' / str(safe_relative(package['snapshotFolder']))
        outputs = published.verify_snapshot(archive, package, folder)
        require(set(outputs) == set(package['files']), 'archive verified output-name set differs')
        for name, value in package['files'].items():
            file = folder / str(safe_relative(name))
            require(i.hash(file) == value, 'retained released source bytes differ')
            i.copy(file, 'source/upstream/' + package['snapshotFolder'] + '/' + name)
        verified += len(outputs)
    require(verified == receipt.get('verifiedSnapshotFiles') == 86, 'actual 86 reconstructed outputs required')
    policy = i.keep_json(repo / 'tool/design-system/families.json', 'source/families.json')
    guard = module('card_guard', repo / 'tool/design-system/check.py')
    guard.validate_contract(policy); counts, failures = guard.inspect(repo, policy)
    require(not failures, 'current component family guard failed')
    total = Counter()
    for row in counts.values(): total.update(row)
    total['duplicate-button'] = total['duplicate-button']
    manager = counts.get('features/dsh_feature_plugins/lib/src/manager_page.dart', {}).get('manual-metric', 0)
    require(total['manual-metric'] == 880 and total['duplicate-button'] == 0 and total['platform-control'] == 11
            and manager == 31, 'actual remaining debt differs from 880/31manager/0duplicate/11platform')
    recipes = i.keep_json(repo / 'tool/design-system/recipes.generated.json', 'source/recipes.generated.json')
    require(len(recipes['metrics']) == 33 and {'DshPluginCardListRecipe', 'DshPluginCardRecipe', 'DshPluginStatusTagRecipe'} <= set(recipes['metrics']),
            'actual 33 generated recipes required')
    for name in ('published.py', 'source_inventory.py', 'verify_release_inputs.py', 'check.py', 'generate.py'):
        i.copy(repo / 'tool/design-system' / name, 'tools/' + name)
    i.emit('source/actual-family-counts.json', {'perFile': counts, 'totals': dict(total), 'remainingManagerMetrics': manager})
    return lock, ledger['summary'], dict(total), recipes['metrics'], receipt


def scenario_data(i, helper):
    text = i.text(helper)
    match = re.search(r"const pluginCardScenarioJson\s*=\s*r'''(.*?)''';", text, re.S)
    require(match is not None, 'one compiled canonical scenario literal required')
    # The source builder hashes the literal between its delimiting newlines.
    literal = match[1].strip('\n')
    return literal, json.loads(literal)


def validate_source(i, folder, source_plan, capture_repo, source_tool_head, source_root, repo, lock, release, archive_cache, manifest):
    provenance = i.keep_json(folder / 'provenance.json', 'cards/source/provenance.json')
    trace = i.keep_json(folder / 'source-trace.json', 'cards/source/source-trace.json')
    plan = i.keep_json(folder / 'flutter-plan.json', 'cards/source/flutter-plan.json')
    require(trace.get('schema') == 'whalee-plugin-card-published-source/1' and trace.get('passed') is True
            and trace.get('provenance') == provenance and trace.get('sourceBodiesUnchanged') is True
            and trace.get('stylesUnchanged') is True and provenance.get('referenceCommit') == SOURCE
            and git(source_root, 'rev-parse', 'HEAD') == SOURCE, 'actual published-source provenance/pin missing')
    package = next(p for p in lock['packages'] if p['snapshotFolder'] == 'ui-plugin-manager')
    row = provenance['packages']['plugin-manager']
    actual_archive = next(p for p in release['packages'] if p['name'] == package['name'])
    require(row['version'] == package['version'] == '0.2.1-rc.2' and row['integrity'] == package['integrity']
            and row['archiveSha256'] == actual_archive['archiveSha256']
            and row['publishedBundleSha256'] == package['publishedBundleSha256'], 'published archive/bundle binding differs')
    archive = archive_cache / str(safe_relative(actual_archive['archiveFile']))
    with tarfile.open(archive, 'r:*') as tar:
        body = tar.extractfile('package/lib/client.js').read()
    require(hashlib.sha256(body).hexdigest() == row['publishedBundleSha256'], 'actual archive factory differs')
    end = b'\t\treturn module.exports;\n\t}\n});'
    hook = b'\t\tglobalThis.__PublishedManager = PluginManagerPage;\n\t\tglobalThis.__CardCss = PluginManagerPage_module_css_default;\n'
    require(body.count(end) == 1 and (folder / 'host/plugin-manager.js').read_bytes() == body.replace(end, hook + end)
            and i.hash(folder / 'host/plugin-manager.js') == row['instrumentedSha256'],
            'actual source factory/CSS changed beyond export-only hook')
    for name, value in provenance['sourceFiles'].items():
        file = source_root / str(safe_relative(name))
        committed = subprocess.check_output(['git', '-C', str(source_root), 'show', SOURCE + ':' + name])
        require(i.hash(file) == value['sha256'] == hashlib.sha256(committed).hexdigest(), 'pinned TS/CSS source mismatch')
        i.copy(file, 'cards/source/reference/' + name)
    for font in provenance['fonts']:
        require(i.hash(repo / 'tool/parity-fonts' / str(safe_relative(font['file']))) == font['sha256'], 'source font bytes differ')
    helper_rel = manifest['scenarioInput']['path']
    helper = repo / str(safe_relative(helper_rel))
    literal, scenarios = scenario_data(i, helper)
    require(i.hash(helper) == manifest['scenarioInput']['sha256'] == provenance['fixtureHelperSha256']
            and hashlib.sha256(literal.encode()).hexdigest() == provenance['scenarioJsonSha256'], 'canonical compiled scenario data differs')
    original_plan = i.keep_json(source_plan, 'cards/source/cases.json')
    require(i.hash(source_plan) == provenance['planSha256']
            and plan.get('reference') == 'native'
            and plan.get('runInfo', {}).get('sourcePlanSha256') == provenance['planSha256'], 'actual source plan bytes differ')
    planned_entries = [{'key': c['id'] if v['id'] == 'default' else c['id'] + '~' + v['id'], 'case': c, 'variant': v}
                       for c in original_plan['cases'] for v in c['variants']]
    require(plan['entries'] == planned_entries, 'actual published source plan transformation differs')
    require(re.fullmatch('[0-9a-f]{40}', source_tool_head), 'full source capture-tool Git identity required')
    capture_name = 'tool/design-system/capture-plugin-cards.mjs'
    capture_bytes = subprocess.check_output(['git', '-C', str(capture_repo), 'show', source_tool_head + ':' + capture_name])
    require(hashlib.sha256(capture_bytes).hexdigest() == provenance['captureToolSha256'], 'capture-time source tool Git blob differs')
    i.emit('cards/source/capture-tool.json', {'head': source_tool_head, 'path': capture_name,
           'rawSha256': provenance['captureToolSha256'], 'text': capture_bytes.decode(),
           'sanitizedCopyNotExecutableAuthority': True})
    capture_lock = capture_repo / 'tool/design-system/sources.lock.json'
    require(i.hash(capture_lock) == provenance['sourceLockSha256'], 'capture-time source lock differs')
    # The retained behavior file name is derived from the actual lock, not guessed.
    candidates = [capture_repo / 'tool/design-system/upstream/ui-plugin-manager' / name
                  for name in package['files'] if 'loaded' in name and name.endswith('.json')]
    require(len(candidates) == 1 and i.hash(candidates[0]) == provenance['loadedRegionsSha256'], 'retained complete loaded regions differ')
    for file, name in ((capture_lock, 'capture-sources.lock.json'), (helper, 'plugin_card_fixture.dart')):
        i.copy(file, 'cards/source/' + name)
    tree_files(i, folder / 'host', 'cards/source/host')
    tree_files(i, folder / 'dist', 'cards/source/dist')
    if (folder / 'source-trace.partial.json').is_file():
        i.copy(folder / 'source-trace.partial.json', 'cards/source-history/source-trace.partial.json')
    traces = trace.get('traces', [])
    entries = {e['key']: e for e in plan.get('entries', [])}
    indexed = {t['key']: t for t in traces}
    require(len(traces) == len(indexed) == trace.get('captures') == len(entries) == len(plan['entries']) == 224,
            'source 224 matrix incomplete/duplicate')
    # 11 idle scenarios plus three default input states, all at two locales,
    # themes, viewports and native densities. No selected/coerced subset.
    require(scenarios.get('schema') == 'dsh-plugin-card-scenarios/1', 'wrong canonical scenario schema')
    scenario_map = {row['id']: {**row, 'package': {**scenarios['basePackage'], **row['package']}}
                    for row in scenarios['scenarios']}
    scenario_ids = set(scenario_map)
    require(len(scenario_ids) == len(scenarios['scenarios']) == 11
            and {t['scenarioId'] for t in traces} == scenario_ids, 'eleven canonical source scenarios required')
    expected = {(sid, state, theme, locale, width, density)
                for sid, state in [(sid, 'idle') for sid in scenario_ids] + [('default', s) for s in ('hover', 'press', 'focus')]
                for theme in ('light', 'dark') for locale in ('en', 'zh-CN')
                for width in (800, 390) for density in (1, 2.625)}
    actual = {(t['scenarioId'], t['state'], t['theme'], t['locale'], t['viewport']['width'], t['viewport']['density']) for t in traces}
    require(actual == expected and set(entries) == set(indexed), 'source matrix or plan key set differs')
    shared.exact_png_set(folder / 'visual-testing-results/react', [k + '.png' for k in entries])
    compact_provenance_hash = hashlib.sha256(json.dumps(provenance, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
    for key, t in indexed.items():
        e = entries[key]
        expected_interaction = ([] if t['state'] == 'idle' else [{
            'type': 'focus-by-tab' if t['state'] == 'focus' else t['state'],
            'target': 'plugin-card-' + scenario_map[t['scenarioId']]['package']['name']}])
        require(e['case']['kind'] == 'plugin-cards.manager' and e['case']['theme'] == t['theme']
                and e['case']['locale'] == t['locale'] and e['case']['viewport'] == t['viewport']
                and t['viewport']['height'] == 900
                and e['case']['capture'] == {'selector': '[data-plugin-cards-capture]', 'flutterKey': 'plugin-cards-capture', 'crop': 'viewport'}
                and e['variant']['props']['scenarioId'] == t['scenarioId']
                and e['variant']['props']['scenario'] == scenario_map[t['scenarioId']]
                and (e['variant'].get('interactions') or []) == expected_interaction
                and not t.get('errors') and t.get('checks') and all(c.get('passed') is True for c in t['checks']),
                'actual source checks/case scenario differs')
        scenario = scenario_map[t['scenarioId']]
        expected_state, actual_state = scenario['expected'], t['actual']
        require(actual_state['switch']['checked'] == str(expected_state['enabled']).lower()
                and actual_state['switch']['disabled'] is expected_state['locked']
                and len(actual_state['tags']) == len(expected_state['tagKeys'])
                and bool(actual_state['metadataError']) == bool(expected_state.get('metadataError')),
                'actual source controlled status/tags/metadata ownership differs')
        if t['scenarioId'] == 'no-description': require(actual_state['description'] is None, 'source optional description not absent')
        if t['scenarioId'] == 'image-failed': require(actual_state['artwork']['tag'] == 'svg', 'actual source image fallback missing')
        if t['state'] == 'focus': require(actual_state['titleFocusVisible'] is True, 'actual source keyboard focus cue missing')
        probes = t.get('postCaptureProbes', [])
        if expected_state['locked'] or scenario.get('refuseToggle'):
            require(len(probes) == 1 and probes[0].get('input') == 'one actual switch click'
                    and probes[0]['before'] == probes[0]['after'] == str(expected_state['enabled']).lower(),
                    'source disabled/refused controlled-switch probe missing')
            calls = probes[0]['calls']
            refuse = bool(scenario.get('refuseToggle'))
            require(calls == {'attempts': int(refuse), 'refusals': int(refuse), 'opens': 0,
                              'requestedValues': [not expected_state['enabled']] if refuse else []},
                    'source switch probe did not preserve callback ownership/refusal')
        else: require(probes == [], 'unexpected source post-capture probe')
        file = folder / str(safe_relative(t['file']))
        require(i.hash(file) == t['sha256'], 'source PNG hash differs')
        require(i.keep_png(file, 'cards/react/' + key + '.png') ==
                [math.floor(t['viewport']['width'] * t['viewport']['density'] + .5),
                 math.floor(900 * t['viewport']['density'] + .5)],
                'actual source viewport/native DPR dimensions differ')
        meta = i.keep_json(file.with_suffix('.metadata.json'), 'cards/react/' + key + '.metadata.json')
        require(meta.get('provider') == 'react' and meta.get('captureKey') == key and meta.get('actual') == t['actual']
                and meta.get('react', {}).get('dshCommit') == SOURCE and meta.get('viewport') == t['viewport']
                and meta.get('react', {}).get('publishedBundleSha256') == row['publishedBundleSha256']
                and meta.get('pixelModel') == 'native' and isinstance(meta.get('chromium'), str) and meta['chromium']
                and meta.get('provenanceSha256') == compact_provenance_hash, 'actual DOM/PNG provenance differs')
    return indexed, entries, provenance


def capture_identity(i, folder, head, tree, count, required_hashes=False):
    value = i.json(folder / 'capture-identity.json')
    require(value.get('head') == head and value.get('tree') == tree and value.get('captured') == count,
            'fresh exact-tree capture identity required: ' + folder.name)
    if required_hashes:
        expected = {'head': head, 'tree': tree}
        require(value.get('identityBefore') == value.get('identityAfter') == expected
                and value.get('summarySha256') == i.hash(folder / 'summary.json'),
                'current224 clean before/after identity and summary hash required')
        for provider, field in (('react', 'sourcePngSha256'), ('flutter', 'flutterPngSha256')):
            hashes = value.get(field, {})
            require(len(hashes) == count, 'all current224 PNG hashes required in capture identity')
            for key, sha in hashes.items():
                require(i.hash(folder / 'visual-testing-results' / provider / (str(safe_relative(key)) + '.png')) == sha,
                        'capture identity PNG bytes differ')
    return value


def derived_subset(i, folder, destination, plan, summary):
    """Verify a split cohort without rerendering or changing any original byte.

    Optional capture-identity fields: derivedFrom is an absolute parent capture
    directory; parentCaptureHashes maps parent-relative files to original SHAs.
    At minimum it binds summary.json and flutter-plan.json. All selected PNGs
    and metadata are independently compared to that parent even if omitted
    from the caller's hash map.
    """
    file = folder / 'capture-identity.json'
    if not file.is_file(): return
    receipt = i.json(file)
    if 'derivedFrom' not in receipt: return
    parent = Path(receipt['derivedFrom'])
    require(parent.is_absolute() and parent.is_dir() and not parent.is_symlink()
            and parent.resolve() != folder.resolve(), 'derived subset needs its actual separate parent capture')
    hashes = receipt.get('parentCaptureHashes')
    require(isinstance(hashes, dict) and {'summary.json', 'flutter-plan.json'} <= set(hashes),
            'derived subset parent plan/summary hashes missing')
    for name, value in hashes.items():
        require(i.hash(parent / str(safe_relative(name))) == value, 'derived parent input hash differs')
    parent_plan, parent_summary = i.json(parent / 'flutter-plan.json'), i.json(parent / 'summary.json')
    entries = {e['key']: e for e in parent_plan['entries']}
    cases = {r['key']: r for r in parent_summary['cases']}
    require(all(entries.get(e['key']) == e for e in plan['entries'])
            and all(cases.get(r['key']) == r for r in summary['cases']), 'derived subset changed parent entries/metric rows')
    proof = []
    for entry in plan['entries']:
        for provider in ('react', 'flutter'):
            for suffix in ('.png', '.metadata.json'):
                relative = 'visual-testing-results/' + provider + '/' + entry['key'] + suffix
                require(i.hash(folder / relative) == i.hash(parent / relative), 'derived subset altered parent original bytes')
                proof.append({'path': relative, 'sha256': i.hash(parent / relative)})
    i.emit(destination + '/derived-subset-proof.json', {'parent': str(parent), 'files': proof,
            'parentPlanSha256': i.hash(parent / 'flutter-plan.json'), 'parentSummarySha256': i.hash(parent / 'summary.json'),
            'originalBytesIdentical': True, 'rerendered': False, 'fitted': False})


def metric_summary(rows):
    require(rows, 'empty measured cohort')
    return {'compared': len(rows), 'dimensionsEqual': sum(r['sizeReact'] == r['sizeFlutter'] for r in rows),
            'nonTextAtLeast99_5': sum(r['nonTextPct'] >= 99.5 for r in rows),
            **{'mean' + field[0].upper() + field[1:]: sum(r[field] for r in rows) / len(rows)
               for field in ('nonTextPct', 'rgbPct', 'pixelPerfectPct')}}


def validate_component_geometry(value):
    require(isinstance(value, dict) and value.get('schema') == 'dsh-plugin-card-geometry/1',
            'real Flutter component geometry required; viewport dimensions are insufficient')
    parts = {'card', 'innerCard', 'action', 'title', 'description', 'artworkFrame', 'artwork', 'tags', 'metadataError', 'switch'}
    require(parts <= set(value) and isinstance(value['tags'], list), 'component geometry parts missing')
    require(value.get('status') == 'measured' and value.get('cardCount') == 1
            and value.get('coordinateBasis', {}).get('rounding') == 'none', 'component geometry was not measured as raw single-card Rects')
    for name in parts - {'tags'}:
        require(value[name] is None or isinstance(value[name], dict), 'invalid optional component geometry')
    for part in [value[n] for n in parts - {'tags'}] + value['tags']:
        if part is None: continue
        bounds, rect = part.get('bounds'), part.get('rawFlutterRect')
        require(isinstance(bounds, list) and len(bounds) == 4
                and all(type(x) in (int, float) and math.isfinite(x) for x in bounds)
                and bounds[2] >= 0 and bounds[3] >= 0 and isinstance(rect, dict)
                and set(rect) == {'left', 'top', 'right', 'bottom'}
                and all(type(x) in (int, float) and math.isfinite(x) for x in rect.values())
                and all(abs(a - b) < 1e-9 for a, b in zip(bounds, [rect['left'], rect['top'],
                                    rect['right'] - rect['left'], rect['bottom'] - rect['top']])),
                'raw component Rect and unrounded bounds differ')
    require(all(value[n] is not None for n in ('card', 'action', 'title', 'artworkFrame', 'artwork', 'switch')),
            'required rendered component geometry absent')


def read_cohort(i, repo, folder, destination, count, metric_module, head=None, tree=None, current_source=None):
    summary = i.keep_json(folder / 'summary.json', destination + '/summary.json')
    rows = summary.get('cases', [])
    require(len(rows) == len({r['key'] for r in rows}) == count, 'cohort key/count differs: ' + destination)
    for row in rows: safe_relative(row['key'])
    if head:
        capture_identity(i, folder, head, tree, count, destination == 'cards')
        i.copy(folder / 'capture-identity.json', destination + '/capture-identity.json')
    elif (folder / 'capture-identity.json').is_file():
        i.copy(folder / 'capture-identity.json', destination + '/capture-identity.json')
    plan = i.keep_json(folder / 'flutter-plan.json', destination + '/flutter-plan.json')
    planned = {e['key']: e for e in plan.get('entries', [])}
    require(len(planned) == len(plan.get('entries', [])) == count and set(planned) == {r['key'] for r in rows},
            'actual cohort plan/summary keys differ')
    derived_subset(i, folder, destination, plan, summary)
    raw_rows = []
    for provider in ('react', 'flutter'):
        shared.exact_png_set(folder / 'visual-testing-results' / provider, [r['key'] + '.png' for r in rows])
    for row in rows:
        key = str(safe_relative(row['key']))
        for field in ('nonTextPct', 'pixelPerfectPct', 'rgbPct'):
            require(type(row.get(field)) in (int, float) and math.isfinite(row[field]) and 0 <= row[field] <= 100, 'invalid actual metric')
        files, metadata = {}, {}
        for provider, field in (('react', 'sizeReact'), ('flutter', 'sizeFlutter')):
            file = folder / 'visual-testing-results' / provider / (key + '.png')
            files[provider] = file
            size = i.png(file)
            require(size == row[field], 'actual PNG dimensions differ from summary')
            meta = i.json(file.with_suffix('.metadata.json')); metadata[provider] = meta
            require(meta.get('provider') == provider and meta.get('captureKey') == key, 'capture metadata key/provider differs')
            if provider == 'react':
                require(meta.get('react', {}).get('dshCommit') == SOURCE, 'actual reference pin differs')
            if destination != 'cards' or provider != 'react':
                i.copy(file, destination + '/' + provider + '/' + file.name)
                i.copy(file.with_suffix('.metadata.json'), destination + '/' + provider + '/' + key + '.metadata.json')
        density = metadata['flutter']['viewport']['density']
        require(metadata['flutter'].get('viewport') == planned[key]['case']['viewport']
                and metadata['flutter'].get('theme') == planned[key]['case']['theme']
                and metadata['flutter'].get('locale') == planned[key]['case']['locale'], 'Flutter actual plan/metadata state differs')
        if destination == 'cards':
            require(planned[key]['case']['kind'] == 'plugin-cards.manager', 'current224 must use actual Manager route kind')
            meta, view = metadata['flutter'], planned[key]['case']['viewport']
            crop = meta.get('crop', {})
            require(meta.get('providerType') == 'flutter-widget-test'
                    and crop.get('mode') == 'viewport'
                    and crop.get('rect') == {'x': 0, 'y': 0, 'width': view['width'], 'height': view['height']}
                    and crop.get('pixelRect') == {'x': 0, 'y': 0,
                       'width': math.floor(view['width'] * density + .5), 'height': math.floor(view['height'] * density + .5)},
                    'current224 must retain the complete native viewport without fitted crop/resize')
        if metric_module is not None:
            measured = metric_module.compare_files(files['react'], files['flutter'], density, [])[0]
            # Optional deeper replay uses the unchanged classifier, never fitted
            # crops. Default staging recomputes all raw RGBA and aggregate scores
            # while binding the actual completed pipeline rows/classifier bytes.
            for field in ('nonTextPct', 'exactPct', 'closePct', 'pixels', 'mismatched', 'buckets'):
                require(row.get(field) == measured[field], 'unchanged metric recomputation differs: ' + key + '/' + field)
        with Image.open(files['react']) as a, Image.open(files['flutter']) as b:
            delta = raw_delta(a, b) if a.size == b.size else None
        geometry = metadata['flutter'].get('componentGeometry')
        if destination == 'cards':
            require(current_source is not None and key in current_source
                    and i.hash(files['react']) == current_source[key]['sha256'], 'current pair is not the actual source original')
            validate_component_geometry(geometry)
        raw_rows.append({'key': key, 'sizeReact': row['sizeReact'], 'sizeFlutter': row['sizeFlutter'],
                         'sourceSha256': i.hash(files['react']), 'flutterSha256': i.hash(files['flutter']),
                         'rawRgbaDelta': delta, 'dimensionsEqual': row['sizeReact'] == row['sizeFlutter'],
                         'sourceGeometry': metadata['react'].get('actual'), 'flutterGeometry': geometry,
                         'metrics': {k: row[k] for k in ('nonTextPct', 'rgbPct', 'pixelPerfectPct')},
                         'rawOriginalsUnmodified': True})
    i.emit(destination + '/raw-comparison.json', raw_rows)
    return metric_summary(rows), raw_rows


def preservation(i, repo, config, metric_module, head, tree):
    require(set(config) == {'old108', 'old96', 'manager16', 'tag', 'switch'}, 'explicit five preservation cohorts required')
    result = {}
    for name, row in config.items():
        require(set(row) == {'before', 'after', 'count'} and type(row['count']) is int and row['count'] > 0,
                'preservation paths/count must be explicit')
        count = row['count']
        if name in ('old108', 'old96', 'manager16'):
            require(count == {'old108': 108, 'old96': 96, 'manager16': 16}[name], 'preservation bounded count differs')
        before, after = Path(row['before']), Path(row['after'])
        require(before.is_absolute() and after.is_absolute(), 'absolute cohort paths required')
        old, _ = read_cohort(i, repo, before, 'history/' + name, count, metric_module)
        new, current = read_cohort(i, repo, after, 'preservation/' + name, count, metric_module, head, tree)
        require(i.json(before / 'flutter-plan.json')['entries'] == i.json(after / 'flutter-plan.json')['entries'],
                'preservation changed the original case/scenario/state plan')
        comparisons = []
        for entry in current:
            key = entry['key']
            for provider in ('react', 'flutter'):
                a_file = before / 'visual-testing-results' / provider / (key + '.png')
                b_file = after / 'visual-testing-results' / provider / (key + '.png')
                with Image.open(a_file) as a, Image.open(b_file) as b:
                    same_size = a.size == b.size
                    delta = raw_delta(a, b) if same_size else None
                comparisons.append({'key': key, 'provider': provider, 'beforeSha256': i.hash(a_file),
                                    'afterSha256': i.hash(b_file), 'dimensionsEqual': same_size,
                                    'rgbaEqual': delta is not None and delta['changedPixels'] == 0, 'rawRgbaDelta': delta})
        require(len(comparisons) == count * 2, 'provider preservation count differs')
        i.emit('preservation/' + name + '/before-after.json', comparisons)
        result[name] = {'before': old, 'after': new, 'providerImages': len(comparisons),
                        'rgbaEqual': sum(r['rgbaEqual'] for r in comparisons),
                        'changed': sum(not r['rgbaEqual'] for r in comparisons),
                        'nonTextMeanDelta': new['meanNonTextPct'] - old['meanNonTextPct']}
    return result


def stage(args):
    repo, out = args.repo.resolve(), args.out.absolute()
    before = identity(repo, args.head, args.tree)
    require(re.fullmatch('[0-9a-f]{40}', args.base_head), 'full ancestral base head required')
    subprocess.check_call(['git', '-C', str(repo), 'merge-base', '--is-ancestor', args.base_head, args.head],
                          env=dict(os.environ, GIT_OPTIONAL_LOCKS='0'))
    require(out.parent.is_dir() and not out.exists() and not out.is_symlink()
            and not out.resolve().is_relative_to(repo), 'fresh external output under existing parent required')
    i = Inputs(); config = i.json(args.inputs)
    fields = {'preflight', 'checkLogs', 'builds', 'gpu', 'manifest', 'android', 'cleanup', 'androidDriver',
              'source', 'sourcePlan', 'providerReceipt', 'sourceRepo', 'sourceToolHead', 'sourceRoot', 'current', 'releaseReceipt', 'archiveCache', 'logs', 'history', 'files', 'cohorts'}
    require(set(config) == fields, 'explicit inputs keys missing/unknown')
    require(all(isinstance(config[k], list) and config[k] for k in ('logs', 'history', 'files')), 'focused logs/history/source files must be explicit/nonempty')
    paths = {k: Path(v) for k, v in config.items() if k not in ('logs', 'history', 'files', 'cohorts', 'sourceToolHead')}
    require(all(p.is_absolute() for p in paths.values()), 'absolute input paths required')
    full = i.keep_json(paths['preflight'], 'preflight.json')
    validate_preflight(full, args.tree)
    for name in sorted(CHECKS): i.copy(paths['checkLogs'] / (name + '.txt'), 'checks/' + name + '.txt')
    for group in ('logs', 'history', 'files'):
        for index, value in enumerate(config[group]):
            path = Path(value); require(path.is_absolute(), 'absolute selected evidence path required')
            dest = f'{group}/{index:03d}-' + path.name
            if path.is_dir(): tree_files(i, path, dest)
            else:
                if path.suffix == '.png': i.png(path)
                else: i.text(path)
                i.copy(path, dest)
    builds = shared.validate_builds(i, paths['builds'], args.head, args.tree)
    manifest = i.keep_json(paths['manifest'], 'manifest.json'); mh = i.hash(paths['manifest'])
    rel = paths['manifest'].relative_to(repo).as_posix()
    require(hashlib.sha256(subprocess.check_output(['git', '-C', str(repo), 'show', args.head + ':' + rel])).hexdigest() == mh,
            'native manifest differs from committed candidate')
    helper = repo / str(safe_relative(manifest['scenarioInput']['path']))
    require(i.hash(helper) == manifest['scenarioInput']['sha256'], 'native shared scenarios differ')
    gpu = validate_gpu(i, paths['gpu'], manifest, mh, builds, args.head, args.tree)
    lock, coverage, debt, recipes, release = validate_release(i, repo, paths['releaseReceipt'], paths['archiveCache'])
    android = validate_android(i, paths['android'], paths['cleanup'], paths['androidDriver'], manifest, mh,
                               builds, args.head, args.tree, recipes)
    traces, entries, provenance = validate_source(i, paths['source'], paths['sourcePlan'], paths['sourceRepo'], config['sourceToolHead'], paths['sourceRoot'], repo,
                                                 lock, release, paths['archiveCache'], manifest)
    require(paths['sourceRepo'].resolve() == repo and config['sourceToolHead'] == args.head
            and provenance.get('preparationRepository') == {'head': args.head, 'tree': args.tree, 'sourceOnly': True},
            'final source capture must use this exact final clean candidate, not preparation history')
    provider = i.keep_json(paths['providerReceipt'], 'cards/source/provider-receipt.json')
    require(provider.get('schema') == 'dsh-published-plugin-card-provider/1' and provider.get('reference') == 'native'
            and provider.get('kind') == 'plugin-cards.manager' and provider.get('genericCacheUsed') is False
            and provider.get('sourceBodiesOrStylesRewritten') is False and provider.get('selectedKeys') == list(entries)
            and provider.get('sourceTraceSha256') == i.hash(paths['source'] / 'source-trace.json')
            and provider.get('planSha256') == i.hash(paths['sourcePlan']),
            'normal routed actual-published provider receipt/selection differs')
    metric_path = repo / 'tool/parity_lib/diffmetrics.py'
    i.copy(metric_path, 'tools/diffmetrics.py'); dm = module('card_unchanged_metrics', metric_path)
    require(i.hash(metric_path) == hashlib.sha256(subprocess.check_output([
                'git', '-C', str(repo), 'show', args.base_head + ':tool/parity_lib/diffmetrics.py'])).hexdigest(),
            'non-text classifier changed from the explicit baseline')
    require(dm.GEOMETRY_PASS == 99.5, 'unchanged non-text threshold required')
    replay = dm if args.recompute_classifier else None
    current, pairs = read_cohort(i, repo, paths['current'], 'cards', 224, replay, args.head, args.tree, traces)
    require({r['key'] for r in pairs} == set(entries), 'source/current full matrix differs')
    require(i.json(paths['current'] / 'flutter-plan.json')['entries'] == list(entries.values()),
            'current224 case/scenario/input plan differs from actual published source plan')
    preserved = preservation(i, repo, config['cohorts'], replay, args.head, args.tree)
    for script in ('plugin-cards-evidence.py', 'plugin-cards-report.py', 'icon-actions-evidence.py', 'reported-families-publish.py'):
        i.copy(ROOT / 'scripts' / script, 'tools/' + script)
    delta = subprocess.check_output(['git', '-C', str(repo), 'diff', '--binary', args.base_head, args.head], text=True)
    i.emit('implementation-diff.json', {'base': args.base_head, 'head': args.head, 'patch': delta,
                                      'rawPatchSha256': hashlib.sha256(delta.encode()).hexdigest()})
    changed = git(repo, 'diff', '--name-only', args.base_head, args.head).splitlines()
    for name in changed:
        file = repo / str(safe_relative(name))
        if file.is_file():
            blob = subprocess.check_output(['git', '-C', str(repo), 'show', args.head + ':' + name])
            require(i.hash(file) == hashlib.sha256(blob).hexdigest(), 'implementation working bytes differ')
            i.copy(file, 'implementation/' + name)
    receipt = {'schema': 'whalee-plugin-cards-evidence/1', **before, 'runtimeHead': args.head, 'runtimeTree': args.tree,
               'identityBefore': before, 'identityAfter': identity(repo, args.head, args.tree), 'allowedPostRuntimeChanges': [],
               'sourcePin': SOURCE, 'packageVersion': '0.2.1-rc.2', 'manifestSha256': mh,
               'productTrees': {n: git(repo, 'rev-parse', args.head + ':' + n) for n in ('apps', 'features', 'packages')},
               'builds': list(builds.values()), 'fullChecks': 13, 'releasePackages': 13, 'releaseFiles': 86, 'recipes': len(recipes),
               'gpu': gpu, 'android': android, 'visual': current, 'preservation': preserved,
               'sourceCoverage': coverage, 'legacyDebt': debt, 'remainingManagerMetrics': 31,
               'limitations': LIMITS, 'published': False, 'metricClassifierSha256': i.hash(metric_path),
               'metricVerification': {'aggregateScoresRecomputed': True, 'allRawRgbaRecomputed': True,
                                      'classifierReplayed': args.recompute_classifier,
                                      'vendorRgbAndNonTextRows': 'completed capture pipeline, bound by raw summary and capture identity hashes'}}
    i.emit('receipt.json', receipt)
    i.copy(ROOT / 'notes/plugin-card-delivery.md', 'README.md')
    i.emit('raw-inputs.json', [{'path': p, 'sha256': h} for p, h in sorted(i.raw.items())])
    with tempfile.TemporaryDirectory(prefix='.plugin-cards-evidence-', dir=out.parent) as temporary:
        prepared = Path(temporary) / out.name; prepared.mkdir()
        records = i.write(prepared)
        (prepared / 'files.json').write_text(json.dumps({'schema': 'whalee-sanitized-files/1', 'files': records}, indent=2) + '\n')
        i.recheck(); identity(repo, args.head, args.tree)
        require(not out.exists(), 'output appeared during validation'); prepared.rename(out)
    print(json.dumps({'head': args.head, 'tree': args.tree, 'files': len(records), 'stage': str(out), 'published': False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for name in ('repo', 'inputs', 'out'): parser.add_argument('--' + name, type=Path, required=True)
    for name in ('head', 'tree', 'base-head'): parser.add_argument('--' + name, required=True)
    parser.add_argument('--recompute-classifier', action='store_true', help='also replay the unchanged slow non-text classifier for every pair')
    stage(parser.parse_args())

if __name__ == '__main__': main()
