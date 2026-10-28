#!/usr/bin/env python3
"""Build a self-contained visual Artifact revision from completed Header evidence.

No staging, network, devices or publication. Artifact base/seen must be supplied
from a fresh root-owned read; incomplete or stale evidence is refused.
"""
from __future__ import annotations
import argparse
import ast
import base64
import hashlib
import html
import importlib.util
import io
import json
from pathlib import Path
import re
import sys
import tempfile

from PIL import Image, ImageChops

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SOURCE = '687f282e8625c6b8d11ff58211a90524be2e4317'
BASE = '875ef6936bc5337afcc3a187b2de80ad22963ccb'
MENU_SHA = '556f7d56fb867fdc09cd4f4fd18865a2b9947736c9e3fb14094679383da648cf'
HEADER_SHA = '3b06e28f95438aca1fad9ccb2c7f48857a2e05e78d8ea8699ad7ee21333e1a30'
FAILED_RUNTIME = '2293a830c1edecc18d5e488e67493fd2e90f2d10'
ANDROID_SHA = '9d72dd09cf82451798454143f19160aabbd4e732b61f5dbfd7daecfd1098553d'
spec = importlib.util.spec_from_file_location('header_report_common', ROOT / 'scripts/menu-compositing-report.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
require, sha = common.require, common.sha
TITLE = 'Whalee Header 与阴影来源迁移：实际差异和未完成项'


def metrics(cases):
    require(len(cases) == 108 and len({c['key'] for c in cases}) == 108, '108 unique component pairs required')
    for c in cases:
        for field in ('nonTextPct', 'pixelPerfectPct', 'rgbPct'):
            common.number(c[field])
    return {'compared': len(cases), 'dimensionsEqual': sum(c['sizeReact'] == c['sizeFlutter'] for c in cases),
            'nonTextAtLeast99_5': sum(c['nonTextPct'] >= 99.5 for c in cases),
            'meanNonTextPct': sum(c['nonTextPct'] for c in cases) / len(cases),
            'meanRgbPct': sum(c['rgbPct'] for c in cases) / len(cases)}


def validate(e):
    receipt, full = e.json('receipt.json'), e.json('preflight.json')
    require(receipt.get('schema') == 'header-shadows-evidence/1' and receipt.get('base') == BASE
            and receipt.get('referenceCommit') == SOURCE and receipt['headTree'] == full.get('headTree')
            and receipt['head'] == receipt['runtimeHead'] and receipt['headTree'] == receipt['runtimeTree']
            and receipt['head'] != FAILED_RUNTIME and receipt.get('allowedPostRuntimeChanges') == []
            and re.fullmatch('[0-9a-f]{40}', receipt['head']) and re.fullmatch('[0-9a-f]{40}', receipt['headTree']),
            'new exact final runtime/source identity required; carryover is not accepted')
    require(set(receipt.get('productTrees', {})) == {'apps', 'features', 'packages'}
        and all(row['runtime'] == row['final'] and re.fullmatch('[0-9a-f]{40}', row['runtime'])
                for row in receipt['productTrees'].values()), 'compiled source identity missing')
    require(full.get('fast') is False and set(full.get('results', {})) == common.CHECKS
            and all(r.get('state') == 'ok' for r in full['results'].values()), 'all thirteen checks must pass without skips')
    cases = e.json('components/summary.json')['cases']
    before_cases = e.json('previous-components/summary.json')['cases']
    for name, count in (('current', 108), ('regression', 96)):
        identity = e.json('capture-identities/' + name + '.json')
        require(identity.get('headAtCompletion') == receipt['head'] and identity.get('captured') == count,
                'component/preservation captures came from an older runtime')
    current, previous = metrics(cases), metrics(before_cases)
    for direction, rows in (('components', cases), ('previous-components', before_cases)):
        for c in rows:
            common.case_info(c['key'])
            for provider, size in (('react', 'sizeReact'), ('flutter', 'sizeFlutter')):
                e.picture(f'{direction}/{provider}/{c["key"]}.png', c[size])
                meta = e.json(f'{direction}/{provider}/{c["key"]}.metadata.json')
                require(meta.get('provider') == provider and meta.get('captureKey') == c['key'], 'capture identity differs')
                if provider == 'react':
                    require(meta.get('react', {}).get('dshCommit') == SOURCE, 'real reference pin differs')
    history = e.json('components/score-history.json')
    for key in ('compared', 'dimensionsEqual', 'nonTextAtLeast99_5', 'meanNonTextPct'):
        require(abs(history['current'][key] - current[key]) < 1e-8
                and abs(history['previous'][key] - previous[key]) < 1e-8, 'score history differs from raw measured cases')
    delta = current['meanNonTextPct'] - previous['meanNonTextPct']
    require(abs(history['nonTextMeanDelta'] - delta) < 1e-8, 'score delta differs')
    headers = e.json('header/comparison.json')
    require(len(headers) == 16 and len({r['id'] for r in headers}) == 16, 'sixteen Header states required')
    header_identity = e.json('header/capture-identity.json')
    require(header_identity.get('headAtCompletion') == receipt['head']
            and header_identity.get('treeAtCompletion') == receipt['headTree']
            and set(header_identity.get('flutterPngSha256', {})) == {r['id'] for r in headers},
            'fresh exact-final Header capture required')
    for r in headers:
        images = []
        for provider, field in (('source', 'sourceSha256'), ('flutter', 'flutterSha256')):
            raw = e.read('header/' + provider + '-' + r['id'] + '.png')
            require(sha(raw) == r[field], 'Header PNG hash differs')
            if provider == 'flutter':
                require(sha(raw) == header_identity['flutterPngSha256'][r['id']], 'Header final identity hash differs')
            with Image.open(io.BytesIO(raw)) as im:
                require(list(im.size) == r['size'], 'Header size differs')
                images.append(im.convert('RGBA'))
        difference = ImageChops.difference(*images)
        require(sum(any(p) for p in difference.getdata()) == r['sourceChangedPixels']
                and max(high for _, high in difference.getextrema()) == r['sourceMaxChannelDifference'],
                'Header pixel differences disagree')
        with Image.open(io.BytesIO(e.read('header/prior-flutter/' + r['id'] + '.png'))) as old:
            require(old.size == images[1].size and old.convert('RGBA').tobytes() == images[1].tobytes()
                    and r.get('priorFlutterRGBAIdentical') is True, 'Header prior pixels changed')
    require(e.json('header/source-receipt.json').get('passed') is True, 'Header real-source receipt failed')
    builds = receipt['builds']
    require(len(builds) == 4 and len({b['name'] for b in builds}) == 4
            and all(b.get('successLine') and re.fullmatch('[0-9a-f]{64}', b['sha256']) for b in builds), 'four completed builds required')
    fixture = next(b for b in builds if b['name'] == 'linux-fixture/dsh_flutter')
    native = {}
    for label in ('menu', 'header'):
        runtime = e.json('gpu/' + label + '/runtime.json')
        manifest_raw = e.read('gpu/' + label + '/manifest.json')
        manifest = json.loads(manifest_raw)
        require(runtime.get('status') == 'passed' and runtime.get('exitCode') == 0
                and runtime.get('binaryUnchanged') is True and runtime.get('binaryBefore') == runtime.get('binaryAfter')
                and runtime.get('ownedPidsAbsent') is True and runtime.get('ownedFixturePidsRemaining') == []
                and runtime.get('runtimeHead') == receipt['runtimeHead'] and runtime.get('runtimeTree') == receipt['runtimeTree']
                and runtime.get('executableSha256') == fixture['sha256']
                and runtime.get('applicationLibrarySha256') == fixture['applicationLibrarySha256'], 'GPU runtime/cleanup proof incomplete')
        # Staged JSON is sanitized/reformatted; bind its semantic manifest to the
        # staged source copy whose exact original SHA is in the runtime receipt.
        source_path = 'tool/parity-desktop/' + ('reported-families-cases.json' if label == 'menu' else 'header-leading-cases.json')
        original = e.read('reproduction/' + source_path)
        require(json.loads(original) == manifest and sha(original) == runtime['manifestSha256']
                == (MENU_SHA if label == 'menu' else HEADER_SHA)
                and runtime.get('replaySourceHead', runtime.get('manifestCommit', runtime.get('runtimeHead'))) == receipt['head'],
                'GPU exact final contract binding differs')
        assertions = 0
        for case in manifest['cases']:
            env = e.json('gpu/' + label + '/' + case['id'] + '/environment.json')
            actual = env['captureAssertions']
            expected = [s['expect'] for s in case['app'] if 'expect' in s]
            require(len(actual) == len(expected) and all(a.get('passed') is True
                    and all(a.get(k) == v for k, v in s.items()) for a, s in zip(actual, expected)), 'GPU assertions differ')
            assertions += len(actual)
        require(assertions == receipt['gpu'][label]['assertions'] and assertions > 0, 'GPU count differs')
        native[label] = assertions
    require(native['menu'] == 84, 'unchanged menu84 required')
    require(native['header'] == 72, 'all72 Header native assertions required')
    android, cleanup = e.json('android/receipt.json'), e.json('cleanup.json')
    fixture_apk = next(b['sha256'] for b in builds if b['name'] == 'android-fixture.apk')
    normal_apk = next(b['sha256'] for b in builds if b['name'] == 'android-normal.apk')
    require(android.get('passed') is True and android.get('apkSha256') == android.get('installedFixtureSha256') == fixture_apk
            and android.get('runtimeHead') == receipt['runtimeHead'] and android.get('runtimeTree') == receipt['runtimeTree']
            and android.get('driverSha256') == sha(e.read('reproduction/header-shadows-android.py')) == ANDROID_SHA
            and len(android['scenes']) == 23 and len(android['checks']) == 54 and len(android['inputs']) == 30
            and all(c.get('passed') is True for c in android['checks']), 'completed fresh Android23/54/30 required')
    count_proof, failed_count = e.json('android-history/scene-count-correction.json'), e.json('android-history/failed-receipt.json')
    old_driver = e.read('android-history/driver-before-scene-count.py')
    new_driver = e.read('reproduction/header-shadows-android.py')
    old_count, new_count = count_proof['onlyChange']
    require(count_proof.get('newDriverSha256') == sha(new_driver) == ANDROID_SHA
            and count_proof.get('oldDriverSha256') == sha(old_driver) == failed_count.get('driverSha256')
            and count_proof.get('literalCaptureCalls') == {'run_reported': 15, 'run_header': 8}
            and old_count == 'len(self.scenes) != 24 or len(self.checks) != 54'
            and new_count == 'len(self.scenes) != 23 or len(self.checks) != 54'
            and old_driver.decode().count(old_count) == 1
            and old_driver.decode().replace(old_count, new_count) == new_driver.decode()
            and failed_count.get('passed') is False and len(failed_count['scenes']) == 23
            and len(failed_count['checks']) == 54 and len(failed_count['inputs']) == 30,
            'Android count-only correction/history proof differs')
    replay = next(n for n in ast.parse(new_driver.decode()).body if isinstance(n, ast.ClassDef) and n.name == 'Replay')
    methods = {n.name: n for n in replay.body if isinstance(n, ast.FunctionDef)}
    literal_scenes = []
    for name, count in (('run_reported', 15), ('run_header', 8)):
        names = [n.args[0].value for n in ast.walk(methods[name]) if isinstance(n, ast.Call)
                 and isinstance(n.func, ast.Attribute) and n.func.attr == 'capture' and n.args
                 and isinstance(n.args[0], ast.Constant)]
        require(len(names) == count, 'Android literal scene branch contract differs')
        literal_scenes.extend(names)
    require(len(set(literal_scenes)) == 23 and set(literal_scenes) == set(android['scenes']),
            'actual Android scenes differ from exact driver capture calls')
    comparisons = {}
    for name in ('run_reported', 'run_header'):
        for node in ast.walk(methods[name]):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in ('changed', 'unchanged'):
                require(len(node.args) == 4 and all(isinstance(node.args[i], ast.Constant)
                        for i in (0, 1, 3)), 'Android pixel contract is not explicit')
                key = tuple(node.args[i].value for i in (0, 1, 3))
                require(key not in comparisons, 'duplicate Android pixel contract')
                comparisons[key] = node.func.attr == 'changed'
    pixels = e.json('android/pixel-proofs.json')
    native_pixels = {(p['before'], p['after'], p['assertion']): p for p in android['checks'] if 'rect' in p}
    require(len(pixels) == len(comparisons) == 6 and set(native_pixels) == set(comparisons)
            and {(p['before'], p['after'], p['assertion']) for p in pixels} == set(comparisons),
            'Android changed/unchanged pixel comparison coverage differs')
    for proof in pixels:
        key = (proof['before'], proof['after'], proof['assertion'])
        require(proof['rect'] == native_pixels[key]['rect'] and proof.get('expectsDifference') is comparisons[key]
                and proof.get('comparisonChannels') == 'RGB', 'Android pixel proof mode differs from exact driver')
        images = []
        for scene in key[:2]:
            with Image.open(io.BytesIO(e.read('android/' + scene + '.png'))) as im:
                rect = proof['rect']
                require(len(rect) == 4 and 0 <= rect[0] < rect[2] <= im.width
                        and 0 <= rect[1] < rect[3] <= im.height, 'Android pixel bounds invalid')
                images.append(im.convert('RGB').crop(rect))
        difference = ImageChops.difference(*images)
        count = sum(any(p) for p in difference.getdata())
        require((count > 0) == comparisons[key] and count == proof['changedPixels']
                and max(high for _, high in difference.getextrema()) == proof['maxChannelDifference'],
                'Android exact-mode pixel evidence differs from actual screenshots')
    require(cleanup.get('passed') is True and cleanup.get('runtimeHead') == receipt['runtimeHead']
        and cleanup.get('runtimeTree') == receipt['runtimeTree'] and all(cleanup.get(k) is True for k in (
        'normalApkRestored', 'normalAppForceStopped', 'ownedEmulatorStopped', 'sharedAdbRetained'))
        and cleanup.get('normalApkLocalSha256') == cleanup.get('normalApkInstalledSha256') == normal_apk,
        'normal Android restoration/owned cleanup incomplete')
    preserved = e.json('preservation/rgba.json')
    require(len(preserved) == 192 and len({(r['key'], r['provider']) for r in preserved}) == 192, '96 cases/both providers required')
    for row in preserved:
        images = []
        for side in ('before', 'after'):
            raw = e.read(f'preservation/{side}/{row["provider"]}/{row["key"]}.png')
            require(sha(raw) == row[side + 'Sha256'], 'preservation file hash differs')
            with Image.open(io.BytesIO(raw)) as im:
                images.append((im.size, im.convert('RGBA').tobytes()))
        require(images[0] == images[1] and row.get('rgbaByteEqual') is True, 'preservation RGBA changed')
    release = e.json('release-inputs.json')
    require(release.get('allPassed') is True and release.get('verificationInputsUnchanged') is True
            and release.get('packageCount') == 13 and release.get('verifiedSnapshotFiles') == 85, '13 actual releases/85 outputs required')
    for field, path in {
        'sourceLockSha256': 'provenance/sources.lock.json',
        'sourceInventorySha256': 'provenance/source-inventory.generated.json',
    }.items():
        # Sanitized JSON has a distinct hash. The raw receipt binding is retained
        # in input-hashes.json; semantic source and stage lock identity are checked.
        original_path = receipt['sourceInputPrefix'] + '/tool/design-system/' + Path(path).name
        original_hash = next((r['sha256'] for r in e.json('input-hashes.json') if r['path'] == original_path), None)
        require(original_hash == release[field], 'release raw-input binding differs')
    for field, filename in {'verificationToolSha256': 'verify_release_inputs.py',
                            'publishedVerifierSha256': 'published.py',
                            'inventoryVerifierSha256': 'source_inventory.py'}.items():
        require(sha(e.read('reproduction/tool/design-system/' + filename)) == release[field],
                'release verifier source binding differs')
    proof = e.json('native-menu-proof/source-controls/geometry.json')
    # The capture receipt records the original script, while the staged copy has
    # local runtime URLs sanitized. Bind the original bytes via the publisher's
    # input record; Evidence separately verifies the sanitized copy's file hash.
    proof_script_path = receipt['sourceInputPrefix'] + '/build/native-menu-proof/capture-source.mjs'
    proof_script_inputs = [row for row in e.json('input-hashes.json') if row.get('path') == proof_script_path]
    require(len(proof_script_inputs) == 1
            and re.fullmatch('[0-9a-f]{64}', proof_script_inputs[0].get('sha256', '')),
            'unique original menu proof script binding required')
    e.read('native-menu-proof/capture-source.mjs')
    require(proof.get('passed') is True and proof.get('referenceCommit') == SOURCE
            and proof.get('chromiumVersion') == '145.0.7632.6'
            and proof.get('scriptSha256') == proof_script_inputs[0]['sha256']
            and {c['id'] for c in proof['cases']} == {'desktop-light', 'phone-dark'}, 'actual source menu proof incomplete')
    for path, row in proof['sourceFiles'].items():
        require(sha(e.read('native-menu-proof/reference-source/' + path)) == row['sha256'], 'menu proof source hash differs')
    for case in proof['cases']:
        pixels = {}
        for name in ('closed', 'two-row-root', 'pro-selected', 'pro-root'):
            with Image.open(io.BytesIO(e.read('native-menu-proof/source-controls/' + case['id'] + '-' + name + '.png'))) as im:
                pixels[name] = im.convert('RGBA')
        rect = case['sourceDerivedRect']
        for first, second, field in (('pro-selected', 'pro-root', 'correctOneRow'), ('closed', 'two-row-root', 'actualTwoRowControl')):
            difference = ImageChops.difference(pixels[first].crop(rect), pixels[second].crop(rect))
            actual = {'changedPixels': sum(any(p) for p in difference.getdata()),
                      'maxChannelDifference': max(high for _, high in difference.getextrema())}
            require(actual == case[field], 'source menu control pixels disagree')
        require(case['correctOneRow']['changedPixels'] == 0 and case['actualTwoRowControl']['changedPixels'] > 0,
                'source controls do not distinguish the extra row')
    diagnostic = e.json('native-menu-proof/native-control-comparison.json')
    require(diagnostic.get('runtimeHead') == FAILED_RUNTIME and 'failed' in diagnostic.get('method', '').lower()
            and receipt.get('modelSeatSemanticBoundary') is True
            and receipt.get('menuSourceProof', {}).get('historicalNativeIsAcceptance') is False,
            'failed diagnostics must remain history; final semantic fix must be recorded')
    require(receipt['legacyDebt']['manual-metric'] == 895
            and receipt['sourceCoverage']['uiCssPendingInputs'] == 173 and receipt['toolTests'] >= 201,
            'current source/debt/tool-test coverage required')
    return receipt, cases, headers, current, previous, delta, native


def render(e, data):
    receipt, cases, headers, current, previous, delta, native = data
    esc = html.escape
    cards = []
    for c in sorted(cases, key=lambda c: c['key']):
        info = common.case_info(c['key'])
        attributes = ' '.join(f'data-{k}="{info[k]}"' for k in ('family', 'theme', 'layout', 'locale'))
        figures = ''
        for provider, field, label in (('react', 'sizeReact', '原版 DSH'), ('flutter', 'sizeFlutter', 'Whalee Flutter')):
            src = e.picture('components/' + provider + '/' + c['key'] + '.png', c[field])
            figures += f'<figure><figcaption>{label}</figcaption><div class="image-frame"><img loading="lazy" src="{src}" width="{c[field][0]}" height="{c[field][1]}" alt="{esc(info["title"])}，{label}"></div></figure>'
        cards.append(f'<article class="case" {attributes}><div class="case-header"><h3>{esc(info["title"])}</h3><div class="case-metrics"><span>非文字严格一致 {c["nonTextPct"]:.3f}%</span><span>RGB 相近度 {c["rgbPct"]:.3f}%</span><span>尺寸 {c["sizeReact"]} / {c["sizeFlutter"]}</span></div><code>{esc(c["key"])}</code></div><div class="pair">{figures}</div></article>')
    labels = {'idle': '静止', 'hover': '悬停', 'pressed': '按下', 'focus': '键盘聚焦'}
    for r in headers:
        theme, density, state = r['id'].split('-')
        title = 'Header · ' + ('深色' if theme == 'dark' else '浅色') + ' · ' + density.upper() + ' · ' + labels[state]
        figures = ''
        for provider, label in (('source', '原版 DSH'), ('flutter', 'Whalee Flutter')):
            src = e.picture('header/' + provider + '-' + r['id'] + '.png', r['size'])
            figures += f'<figure><figcaption>{label}</figcaption><div class="image-frame"><img loading="lazy" src="{src}" width="{r["size"][0]}" height="{r["size"][1]}" alt="{esc(title)}，{label}"></div></figure>'
        cards.append(f'<article class="case" data-family="header" data-theme="{theme}" data-layout="component" data-locale="none"><div class="case-header"><h3>{title}</h3><div class="case-metrics"><span>差异像素 {r["sourceChangedPixels"]}</span><span>最大通道差 {r["sourceMaxChannelDifference"]}</span><span>此前 Flutter RGBA 相同</span></div></div><div class="pair">{figures}</div></article>')
    nonfocus = max(r['sourceMaxChannelDifference'] for r in headers if not r['id'].endswith('-focus'))
    focus = max(r['sourceMaxChannelDifference'] for r in headers if r['id'].endswith('-focus'))
    proof_rows = ''.join('<li>' + ('桌面 / 浅色' if c['id'] == 'desktop-light' else '手机 / 深色')
                         + f'：正确一行菜单变化 {c["correctOneRow"]["changedPixels"]} 像素；'
                         + f'真实两行反例变化 {c["actualTwoRowControl"]["changedPixels"]} 像素。</li>'
                         for c in e.json('native-menu-proof/source-controls/geometry.json')['cases'])
    direction = '下降' if delta < 0 else '上升' if delta > 0 else '持平'
    return f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none';img-src data:;style-src 'unsafe-inline';script-src 'unsafe-inline';connect-src 'none';font-src 'none';base-uri 'none';form-action 'none'"><title>{TITLE}</title><style>{common.CSS}</style></head><body><main>
<header><div class="eyebrow">WHALEE · 来源迁移与真实对照</div><h1>移除阴影拟合，继续清理手写样式</h1><p class="lead">Header 已改用来源生成的共享控件，阴影恢复源码定义的模糊换算。108 组原版对照中仍只有 <strong>{current['nonTextAtLeast99_5']} / 108 组达到非文字严格一致 ≥99.5%</strong>；总体视觉目标未完成。</p><span class="flag">895 处既有数值匹配 · 173 个 UI CSS 输入尚未保留</span></header>
<div class="metrics"><div class="metric"><strong>{current['meanNonTextPct']:.3f}%</strong><span>当前平均非文字严格一致</span></div><div class="metric"><strong>{previous['meanNonTextPct']:.3f}%</strong><span>上一轮同组对照</span></div><div class="metric"><strong>{current['dimensionsEqual']} / 108</strong><span>截图尺寸一致</span></div><div class="metric"><strong>{current['meanRgbPct']:.3f}%</strong><span>RGB 相近度，单独报告</span></div></div>
<section class="panel"><h2>本轮结果与边界</h2><p>阴影按 Blink 的 CSS blur / 2 换算，移除此前截图拟合与固定外部裁切范围。当前非文字均值比上一轮{direction} {abs(delta):.6f} 个百分点；这项来源修正没有被包装成相似度提升，字体、阈值和分类规则保持不变。</p><p>16 组 Header 组件状态的此前 Flutter 像素全部保留。非聚焦状态的最大通道差为 {nonfocus}；聚焦状态为 {focus}，Chromium 的原生 outline:auto 仍未匹配。16 组属于组件状态对照，不是 16 个已通过的视觉验收。</p><p>96 个既有场景在两个提供方均保持 RGBA 相同，共 192 次比较。895 处数值匹配和 173 个尚未保留的 UI CSS 输入仍需继续核对；来源保留不代表组件已实现。</p><ul><li>阴影只覆盖当前圆角、透明作者背景分支；不证明不透明作者背景、方角硬裁切、变换或超椭圆轮廓一致。</li><li>统计背景采样、macOS 原生半透明效果、模型自然输入行高，以及若干模型和侧栏交互仍未完成。</li><li>Header 的完整 AppFrame 挂载、窗口交通灯位置、跨窗口失焦和独立编辑器组合输入不在本轮认证范围。</li></ul></section>
<section class="panel"><h2>已完成的验证</h2><div class="checks"><div class="check"><strong>13 / 13</strong><span>最终树必需检查</span></div><div class="check"><strong>4</strong><span>正常与夹具构建</span></div><div class="check"><strong>84 + {native['header']}</strong><span>菜单 / Header GPU 断言</span></div><div class="check"><strong>23 / 54</strong><span>Android 场景 / 检查</span></div><div class="check"><strong>13 / 85</strong><span>真实发行包 / 来源输出</span></div></div><p class="muted" style="margin-top:14px">{receipt['toolTests']} 个工具测试通过；正常 APK 已恢复并核对安装字节，应用和自有模拟器已停止，共享 ADB 保留。交互检查通过不代表视觉达到 99.5%。Android 驱动原有 15 个场景、新增 8 个 Header 场景；修正总数核对后已完整重跑，旧失败回执仍保留为历史。</p></section>
<section class="panel" data-menu-source-proof="verified"><h2>原版菜单反例与点击范围修复</h2><p>菜单回放保留 84 条断言，仅将两个检查矩形移到来源行高与阴影范围共同确定的空隙。真实 Chromium 原版控件的正反例确认，这个区域能识别错误多保留的一行；检查采用精确像素相等。</p><ul>{proof_rows}</ul><p style="margin-top:14px">模型入口按钮的无障碍点击范围已限制到按钮本身。此前它曾扩展到整页；新增回归检查核对点击范围与按钮一致，并实际点开菜单。此前失败的 Android 和菜单回执保留为诊断历史，本轮结果来自重新构建后的完整运行。</p></section>
<section class="panel"><h2>浏览 108 组页面与 16 组 Header 对照</h2><div class="filters"><label>组件<select data-filter="family"><option value="">全部（124）</option><option value="sidebar">侧栏（12）</option><option value="stats">统计（48）</option><option value="model">模型（48）</option><option value="header">Header（16）</option></select></label><label>主题<select data-filter="theme"><option value="">全部</option><option value="light">浅色</option><option value="dark">深色</option></select></label><label>范围<select data-filter="layout"><option value="">全部</option><option value="desktop">桌面</option><option value="phone">手机</option><option value="component">Header 组件</option></select></label><label>语言<select data-filter="locale"><option value="">全部</option><option value="en">English</option><option value="zh">中文</option><option value="none">Header 无语言变体</option></select></label></div><p class="count" id="shown-count" role="status" aria-live="polite">当前显示 124 组</p></section><div id="cases">{''.join(cards)}</div><p id="empty" class="empty" hidden>没有匹配的对照。</p>
<section class="panel"><h2>固定来源与提交</h2><div class="identity"><span>最终提交与构建运行时：<code>{receipt['head']}</code></span><span>最终树与运行时树：<code>{receipt['headTree']}</code></span><span>全部本轮截图、构建与原生回放绑定同一新提交；没有构建后差异豁免。</span><span>源码基线：<code>{BASE}</code></span><span>DSH：<code>{SOURCE}</code> · 发行包 0.2.1-rc.2</span></div></section><footer>全部 248 张对照 PNG 均内联自已校验哈希的合成数据证据。无外部资源、真实用户截图、凭据或请求日志。未执行发布或部署。</footer></main><script>{common.JS}</script></body></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path, default=ROOT / 'scratch/whalee-menu-sticky-evidence/header-shadows')
    parser.add_argument('--out', type=Path, default=ROOT / 'scratch/header-shadows-artifact')
    parser.add_argument('--artifact', default='pt_922e1521-0495-44b3-82f5-7ad057430f2c')
    parser.add_argument('--base', required=True, help='fresh current visual Artifact revision UUID')
    parser.add_argument('--seen', type=int, required=True, help='fresh current Artifact version number')
    args = parser.parse_args()
    require(re.fullmatch('[0-9a-f-]{36}', args.base) and args.seen > 0, 'explicit current base/seen required')
    require(not args.out.exists() and args.out.parent.is_dir(), 'fresh report output required; preserve prior runs')
    e = common.Evidence(args.stage)
    data = validate(e)
    document = render(e, data)
    common.safe_text(re.sub(r'data:image/png;base64,[A-Za-z0-9+/=]+', '[verified-png]', document))
    require(not re.search(r'<(?:iframe|a|link|base|form)\b|\b(?:href|download|onclick)=|navigator\.clipboard|fetch\(', document, re.I),
            'external action/resource in report')
    raw = document.encode()
    require(len(raw) < 10 * 1024 * 1024 and document.count('data:image/png;base64,') == 248,
            'self-contained report must retain all248 images under10MiB')
    receipt, _, _, current, previous, delta, native = data
    payload = {'artifact': args.artifact, 'base': args.base, 'seen': args.seen, 'entry': 'index.html',
               'title': TITLE, 'icon': 'report', 'description': f'来源生成 Header 与源码阴影换算；108组非文字均值{current["meanNonTextPct"]:.6f}%（此前{previous["meanNonTextPct"]:.6f}%），另列16组Header与未匹配UA聚焦轮廓；895处既有数值匹配仍待清理。',
               'files': {'index.html': {'content': document}}}
    build = {'head': receipt['head'], 'tree': receipt['headTree'], 'htmlBytes': len(raw), 'htmlSha256': sha(raw),
             'pairs': 108, 'headerPairs': 16, 'inlineImages': 248, 'currentMetrics': current,
             'previousMetrics': previous, 'nonTextMeanDelta': delta, 'gpuAssertions': native,
             'stagedFilesVerified': len(e.data), 'evidenceManifestSha256': sha((args.stage / 'files.json').read_bytes()),
             'artifact': args.artifact, 'base': args.base, 'seen': args.seen, 'published': False}
    with tempfile.TemporaryDirectory(prefix='.header-shadow-report-', dir=args.out.parent) as temporary:
        stage = Path(temporary) / args.out.name
        stage.mkdir()
        (stage / 'index.html').write_bytes(raw)
        for name, value in [('publish.json', payload), ('build-receipt.json', build)]:
            (stage / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
        require(not args.out.exists(), 'report output appeared during generation')
        stage.rename(args.out)
    print(json.dumps(build))


if __name__ == '__main__':
    main()
