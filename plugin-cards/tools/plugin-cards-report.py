#!/usr/bin/env python3
"""Build an unsent, lossless 224-pair PluginCard Artifact locally.

Reads every staged file and verifies its raw/sanitized hash domain. No network,
native, product or git operations. --artifact/--base/--seen must be supplied by
the owner after a fresh Artifact read. A fresh artifact uses --base null --seen 0.
PNG assets use the documented files[path].content_base64 transport. If the
actual UTF-8 request reaches 24 MiB or any inline file exceeds 10 MiB, publish
JSON is withheld and missing-blob-manifest.json records every required blob.
"""
from __future__ import annotations
import argparse
import base64
from collections import Counter
import hashlib
import html
import importlib.util
import io
import json
from pathlib import Path
import re
import sys
import tempfile
import uuid

import numpy as np
from PIL import Image

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('plugin_card_stage_contract', ROOT / 'scripts/plugin-cards-evidence.py')
contract = importlib.util.module_from_spec(spec); spec.loader.exec_module(contract)
require = contract.require
TITLE = 'Whalee 插件卡片：真实来源、交互验证与剩余差异'
MAX_REQUEST, MAX_INLINE, MAX_HTML = 24 * 1024**2, 10 * 1024**2, 16 * 1024**2


def sha(data): return hashlib.sha256(data).hexdigest()
def esc(value): return html.escape(str(value), quote=True)


class Evidence:
    def __init__(self, folder):
        require(folder.is_dir() and not folder.is_symlink(), 'completed local Card stage required')
        self.folder = folder
        manifest = folder / 'files.json'; self.manifest_sha256 = contract.digest(manifest)
        data = json.loads(manifest.read_text())
        require(data.get('schema') == 'whalee-sanitized-files/1', 'unsupported evidence hash domain')
        rows = data['files']; self.files = {r['path']: r for r in rows}
        require(len(rows) == len(self.files), 'duplicate staged path')
        actual = {p.relative_to(folder).as_posix() for p in folder.rglob('*') if p.is_file()}
        require(actual == set(self.files) | {'files.json'}, 'stage file set differs')
        for name, row in self.files.items():
            contract.safe_relative(name); file = folder / name
            require(contract.digest(file) == row['sha256'] and file.stat().st_size == row['bytes'], 'staged bytes differ: ' + name)
            if file.suffix == '.png':
                with Image.open(file) as picture:
                    require(picture.format == 'PNG', 'stage contains non-PNG image')
                    for value in picture.info.values():
                        if isinstance(value, str): require(contract.common.clean_text(value) == value, 'private PNG metadata')
                    picture.verify()
            else:
                value = file.read_text()
                require(contract.common.clean_text(value) == value, 'private text/credential signature in stage')
        raw = self.json('raw-inputs.json'); inputs = {r['path']: r['sha256'] for r in raw}
        require(len(inputs) == len(raw), 'sanitized raw-input path collision')
        for row in rows:
            if row.get('rawSha256') is not None:
                require(inputs.get(row['rawInput']) == row['rawSha256'], 'raw/sanitized source binding missing')

    def json(self, name):
        require(name in self.files, 'required staged JSON missing: ' + name)
        return json.loads((self.folder / name).read_text())

    def image(self, name):
        require(name in self.files and name.endswith('.png'), 'required original PNG missing')
        file = self.folder / name
        with Image.open(file) as picture:
            require(picture.format == 'PNG', 'original must be PNG'); picture.load()
            result = picture.convert('RGBA')
        return result

    def recheck(self):
        require(contract.digest(self.folder / 'files.json') == self.manifest_sha256
                and {p.relative_to(self.folder).as_posix() for p in self.folder.rglob('*') if p.is_file()}
                == set(self.files) | {'files.json'}
                and all(contract.digest(self.folder / n) == r['sha256'] for n, r in self.files.items()),
                'evidence changed during rendering')


def validate(e):
    r, full = e.json('receipt.json'), e.json('preflight.json')
    require(r.get('schema') == 'whalee-plugin-cards-evidence/1', 'completed Card evidence required')
    require(e.files['tools/plugin-cards-evidence.py']['rawSha256'] == contract.digest(ROOT / 'scripts/plugin-cards-evidence.py')
            and e.files['tools/plugin-cards-report.py']['rawSha256'] == contract.digest(Path(__file__)),
            'stage producer/report tool version differs; restage after script changes')
    require(e.files['tools/diffmetrics.py']['rawSha256'] == r.get('metricClassifierSha256'), 'unchanged classifier binding missing')
    identity = {key: r.get(key) for key in ('head', 'tree')}
    require(all(re.fullmatch('[0-9a-f]{40}', str(v)) for v in identity.values())
            and r.get('identityBefore') == r.get('identityAfter') == identity
            and r.get('runtimeHead') == identity['head'] and r.get('runtimeTree') == identity['tree']
            and r.get('allowedPostRuntimeChanges') == [] and r.get('sourcePin') == contract.SOURCE
            and r.get('packageVersion') == '0.2.1-rc.2', 'exact final/runtime/source identity required')
    require(full.get('headTree') == identity['tree'] and full.get('fast') is False
            and set(full.get('results', {})) == contract.CHECKS
            and all(row.get('state') == 'ok' for row in full['results'].values()), 'all thirteen final checks required')
    require(r.get('fullChecks') == 13 and r.get('releasePackages') == 13 and r.get('releaseFiles') == 86
            and r.get('recipes') == len(e.json('source/recipes.generated.json')['metrics']) == 33,
            '13archives/86outputs/33recipes contract differs')
    require(r.get('legacyDebt', {}).get('manual-metric') == 880 and r['legacyDebt'].get('duplicate-button') == 0
            and r['legacyDebt'].get('platform-control') == 11 and r.get('remainingManagerMetrics') == 31,
            'remaining debt is not actual880/31/0/11')
    builds = {b['name']: b for b in r['builds']}
    require(len(builds) == len(r['builds']) == 4 and set(builds) == {'android-fixture.apk', 'android-normal.apk',
                'linux-fixture/dsh_flutter', 'linux-normal/dsh_flutter'}, 'four builds required')
    manifest = e.json('manifest.json')
    require(e.files['manifest.json']['rawSha256'] == r.get('manifestSha256'), 'raw manifest binding differs')
    scenes, checks, inputs, proofs = contract.android_contract(manifest)
    gpu, android, cleanup = e.json('gpu/runtime.json'), e.json('android/receipt.json'), e.json('android/cleanup.json')
    expected = {'runtimeHead': identity['head'], 'runtimeTree': identity['tree'], 'manifestSha256': r['manifestSha256'],
                'executableSha256': builds['linux-fixture/dsh_flutter']['sha256'],
                'applicationLibrarySha256': builds['linux-fixture/dsh_flutter']['applicationLibrarySha256']}
    require(gpu.get('binaryBefore') == gpu.get('binaryAfter') == expected and gpu.get('status') == 'passed'
            and gpu.get('exitCode') == 0 and gpu.get('binaryUnchanged') is True and gpu.get('ownedPidsAbsent') is True
            and gpu.get('ownedFixturePidsRemaining') == [] and gpu.get('totalAssertions') == gpu.get('totalPassedAssertions') == 112
            and gpu.get('totalScreenshots') == 80 and r.get('gpu', {}).get('assertions') == 112
            and r['gpu']['pngs'] == 80, 'final GPU112/80/cleanup missing')
    require(e.json('gpu/cases.json') == manifest, 'staged replay manifest differs')
    for record in (android, cleanup):
        require(record.get('passed') is True and all(record.get(k) == expected[k] for k in ('runtimeHead', 'runtimeTree', 'manifestSha256')),
                'final Android runtime identity missing')
    require(android.get('scenes') == scenes and len(android.get('inputs', [])) == len(inputs) == 30
            and len(android.get('checks', [])) == len(checks) == 57
            and all(a.get('assertion') == label and a.get('passed') is True for a, label in zip(android['checks'], checks))
            and len(scenes) == 17 and len(android.get('geometryProofs', [])) == len(proofs)
            and all(p.get('passed') is True for p in android['geometryProofs']), 'Android literal17/57/30 proof differs')
    require(android.get('apkSha256') == android.get('installedFixtureSha256') == builds['android-fixture.apk']['sha256']
            and cleanup.get('normalApkLocalSha256') == cleanup.get('normalApkInstalledSha256') == builds['android-normal.apk']['sha256']
            and all(cleanup.get(k) is True for k in ('normalApkRestored', 'normalAppForceStopped', 'ownedEmulatorStopped', 'sharedAdbRetained')),
            'APK readback/restoration/cleanup missing')
    trace, provenance = e.json('cards/source/source-trace.json'), e.json('cards/source/provenance.json')
    require(trace.get('passed') is True and trace.get('provenance') == provenance and provenance.get('referenceCommit') == contract.SOURCE
            and trace.get('sourceBodiesUnchanged') is True and trace.get('stylesUnchanged') is True,
            'actual published-source proof missing')
    require(provenance.get('preparationRepository') == {**identity, 'sourceOnly': True}
            and e.json('cards/source/capture-tool.json').get('head') == identity['head']
            and e.json('cards/source/capture-tool.json').get('rawSha256') == provenance.get('captureToolSha256'),
            'source capture used preparation history instead of the final candidate')
    traces = {t['key']: t for t in trace['traces']}
    provider = e.json('cards/source/provider-receipt.json')
    require(provider.get('schema') == 'dsh-published-plugin-card-provider/1' and provider.get('reference') == 'native'
            and provider.get('kind') == 'plugin-cards.manager' and provider.get('genericCacheUsed') is False
            and provider.get('sourceBodiesOrStylesRewritten') is False
            and provider.get('selectedKeys') == [entry['key'] for entry in e.json('cards/source/flutter-plan.json')['entries']]
            and provider.get('sourceTraceSha256') == e.files['cards/source/source-trace.json']['rawSha256']
            and provider.get('planSha256') == e.files['cards/source/cases.json']['rawSha256'],
            'actual normal routed source provider binding missing')
    rows, summary = e.json('cards/raw-comparison.json'), e.json('cards/summary.json')['cases']
    require(len(rows) == len(traces) == len(summary) == 224 and len({r['key'] for r in rows}) == 224,
            'complete distinct224 pairs required')
    indexed = {r['key']: r for r in summary}
    require(set(indexed) == set(traces) == {r['key'] for r in rows}, 'summary/source/pair keys differ')
    for row in rows:
        key, t = row['key'], traces[row['key']]
        for provider, field in (('react', 'sourceSha256'), ('flutter', 'flutterSha256')):
            require(e.files[f'cards/{provider}/{key}.png']['sha256'] == row[field], 'original PNG hash differs')
        require(row['sourceSha256'] == t['sha256'] and row['sourceGeometry'] == t['actual']
                and row.get('flutterGeometry', {}).get('schema') == 'dsh-plugin-card-geometry/1'
                and row['metrics'] == {k: indexed[key][k] for k in ('nonTextPct', 'rgbPct', 'pixelPerfectPct')},
                'measured source/Flutter geometry or actual metric binding differs')
        contract.validate_component_geometry(row['flutterGeometry'])
        with e.image(f'cards/react/{key}.png') as a, e.image(f'cards/flutter/{key}.png') as b:
            require(list(a.size) == row['sizeReact'] and list(b.size) == row['sizeFlutter']
                    and row['dimensionsEqual'] == (a.size == b.size)
                    and row['rawRgbaDelta'] == (contract.raw_delta(a, b) if a.size == b.size else None),
                    'raw source/current delta differs')
    require(contract.metric_summary(summary) == r['visual'], 'computed224 metric totals differ')
    require(set(r['preservation']) == {'old108', 'old96', 'manager16', 'tag', 'switch'}, 'five preservation cohorts required')
    for name, value in r['preservation'].items():
        comparisons = e.json('preservation/' + name + '/before-after.json')
        count = value['after']['compared']
        require(len(comparisons) == count * 2 and value['providerImages'] == len(comparisons)
                and value['rgbaEqual'] == sum(row['rgbaEqual'] for row in comparisons)
                and value['changed'] == sum(not row['rgbaEqual'] for row in comparisons), 'actual preservation totals differ')
        for row in comparisons:
            rel = row['provider'] + '/' + row['key'] + '.png'
            require(e.files['history/' + name + '/' + rel]['sha256'] == row['beforeSha256']
                    and e.files['preservation/' + name + '/' + rel]['sha256'] == row['afterSha256'], 'preservation PNG binding differs')
        require(contract.metric_summary(e.json('preservation/' + name + '/summary.json')['cases']) == value['after']
                and contract.metric_summary(e.json('history/' + name + '/summary.json')['cases']) == value['before'],
                'preservation metrics differ')
    return r, rows, traces


def png_bytes(image):
    """Lossless encoding only; any RGB conversion is independently reversed."""
    result = io.BytesIO()
    encoded = image.convert('RGB') if image.getextrema()[3] == (255, 255) else image
    encoded.save(result, format='PNG', optimize=True, compress_level=9)
    data = result.getvalue()
    with Image.open(io.BytesIO(data)) as check:
        require(check.convert('RGBA').tobytes() == image.tobytes(), 'PNG optimization altered RGBA')
    return data


def composite(a, b):
    """No resizing/recoloring/fitting: two complete frames, exact paste positions."""
    candidates = []
    for arrangement in ('side-by-side', 'stacked'):
        if arrangement == 'side-by-side':
            size, rect_a, rect_b = (a.width + b.width, max(a.height, b.height)), [0, 0, a.width, a.height], [a.width, 0, b.width, b.height]
        else:
            size, rect_a, rect_b = (max(a.width, b.width), a.height + b.height), [0, 0, a.width, a.height], [0, a.height, b.width, b.height]
        image = Image.new('RGBA', size, (0, 0, 0, 0)); image.paste(a, (rect_a[0], rect_a[1])); image.paste(b, (rect_b[0], rect_b[1]))
        data = png_bytes(image)
        candidates.append((len(data), data, arrangement, rect_a, rect_b, size))
    _, data, arrangement, rect_a, rect_b, size = min(candidates, key=lambda c: c[0])
    with Image.open(io.BytesIO(data)) as check:
        check = check.convert('RGBA')
        for original, rect in ((a, rect_a), (b, rect_b)):
            x, y, w, h = rect
            require(check.crop((x, y, x + w, y + h)).tobytes() == original.tobytes(), 'composite rectangle altered original RGBA')
    return data, {'arrangement': arrangement, 'size': list(size), 'sourceRect': rect_a, 'flutterRect': rect_b,
                  'bothOriginalRectanglesRGBAIdentical': True, 'resized': False, 'recolored': False, 'croppedToFit': False}


def geometry_table(source, flutter):
    """Keep actual unrounded numbers; omit repeated font/style prose for size."""
    names = ['card', 'title', 'description', 'artworkFrame', 'artwork', 'metadataError', 'switch', 'innerCard', 'action']
    source_tags, flutter_tags = source.get('tags', []), flutter.get('tags', [])
    pairs = [(name, source.get(name), flutter.get(name)) for name in names]
    pairs += [('tag' + str(index + 1), source_tags[index] if index < len(source_tags) else None,
               flutter_tags[index] if index < len(flutter_tags) else None)
              for index in range(max(len(source_tags), len(flutter_tags)))]
    body = ''.join('<tr><th>' + esc(name) + '</th><td>' + esc(json.dumps(a['bounds']) if a is not None else '—') +
                   '</td><td>' + esc(json.dumps(b['bounds']) if b is not None else '—') + '</td></tr>'
                   for name, a, b in pairs)
    state = {name: {'source': source.get(name), 'flutter': flutter.get(name)}
             for name in ('hover', 'focusedTitle', 'titleFocusVisible')}
    return '<div class="table-scroll"><table><thead><tr><th>原始逻辑矩形 [x,y,w,h]</th><th>DSH DOM</th><th>Flutter</th></tr></thead><tbody>' + body + '</tbody></table></div><pre>' + esc(json.dumps(state, ensure_ascii=False)) + '</pre><p>title：原版文本按钮与 Flutter 可见文本外框分别测量；action：原生完整点击区域，来源对应整卡伪元素。innerCard 是实际 Stack 外框。未测量段落内部或字形墨迹边界；聚焦可见性的两端测量方法不同，不据此推断完全相同。</p>'


def render(receipt, rows, traces, composites):
    v = receipt['visual']; cards = []
    for row in rows:
        key = row['key']; t = traces[key]; c = composites[key]
        density = t['viewport']['density']; layout = 'phone' if t['viewport']['width'] < 600 else 'desktop'
        values = {'scenario': t['scenarioId'], 'state': t['state'], 'theme': t['theme'], 'locale': t['locale'],
                  'layout': layout, 'dpr': f'{density:g}'}
        attrs = ' '.join(f'data-{k}="{esc(value)}"' for k, value in values.items())
        delta = row['rawRgbaDelta']
        raw = (f"RGBA 变化 {delta['changedPixels']}/{delta['comparedPixels']} 像素；最大通道差 {delta['maxChannelError']}；平均绝对差 {delta['meanAbsoluteRgbaError']:.8f}"
               if delta is not None else '尺寸不同，不缩放或裁剪来制造相同的比较区域。')
        geometry = geometry_table(row['sourceGeometry'], row['flutterGeometry'])
        # The asset is unchanged. CSS presents the two complete frames at their
        # logical viewport density; overflow scrolls, never fits a crop.
        width = c['size'][0] / density
        cards.append(f'''<article class="pair" {attrs}><h3>{esc(t['scenarioId'])} · {esc(t['state'])}</h3>
<p>{esc(t['theme'])} · {esc(t['locale'])} · {layout} · DPR {density:g}</p>
<p>原版 {row['sizeReact'][0]}×{row['sizeReact'][1]}；Flutter {row['sizeFlutter'][0]}×{row['sizeFlutter'][1]}。{'左：原版；右：Flutter' if c['arrangement']=='side-by-side' else '上：原版；下：Flutter'}。</p>
<div class="image-scroll" tabindex="0" role="region" aria-label="{esc(key)}完整图像，可滚动"><img loading="lazy" decoding="async" src="{c['path']}" width="{c['size'][0]}" height="{c['size'][1]}" style="width:{width:g}px;height:auto" alt="{esc(key)}，两个原始帧的无损拼接"></div>
<p>非文字 {row['metrics']['nonTextPct']:.6f}% · RGB {row['metrics']['rgbPct']:.6f}% · 完全像素 {row['metrics']['pixelPerfectPct']:.6f}%</p><p>{raw}</p>
<details><summary>原始身份与实际几何测量</summary><p>原版 SHA-256 <code>{row['sourceSha256']}</code><br>Flutter SHA-256 <code>{row['flutterSha256']}</code><br>拼接 SHA-256 <code>{c['sha256']}</code></p>{geometry}</details></article>''')
    filters = []
    values = {'scenario': sorted({t['scenarioId'] for t in traces.values()}), 'state': ['idle', 'hover', 'press', 'focus'],
              'theme': ['light', 'dark'], 'locale': ['en', 'zh-CN'], 'layout': ['desktop', 'phone'], 'dpr': ['1', '2.625']}
    labels = {'scenario': '场景', 'state': '状态', 'theme': '主题', 'locale': '语言', 'layout': '布局', 'dpr': 'DPR'}
    for name, options in values.items():
        filters.append('<label>' + labels[name] + f'<select data-filter="{name}"><option value="">全部</option>' +
                       ''.join('<option value="' + esc(o) + '">' + esc(o) + '</option>' for o in options) + '</select></label>')
    preservation = ''.join(f"<tr><th>{esc(name)}</th><td>{value['after']['compared']}</td><td>{value['rgbaEqual']}/{value['providerImages']}</td><td>{value['changed']}</td><td>{value['before']['meanNonTextPct']:.6f}% → {value['after']['meanNonTextPct']:.6f}% ({value['nonTextMeanDelta']:+.6f})</td></tr>"
                           for name, value in receipt['preservation'].items())
    limits = ''.join('<li>' + esc(value) + '</li>' for value in receipt['limitations'])
    return f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{TITLE}</title>
<style>*{{box-sizing:border-box}}:root{{font-family:system-ui,sans-serif;color-scheme:light}}body{{margin:0;color:#1e2530;background:#f5f6f8}}main{{max-width:1280px;padding:clamp(12px,3vw,28px);margin:auto;min-width:0}}h1{{font-size:clamp(24px,4vw,34px);line-height:1.25}}h2{{font-size:22px;margin:30px 0 12px}}p,li{{line-height:1.65;overflow-wrap:anywhere}}.panel,.pair{{background:white;border:1px solid #dce0e6;border-radius:12px;padding:clamp(12px,2vw,20px);margin:16px 0;min-width:0}}.pending{{color:#794007}}#filters{{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:10px}}label{{display:block;font-size:14px}}select,input,button{{display:block;width:100%;min-height:44px;font:inherit;border:1px solid #a8afba;border-radius:6px;background:white;color:#18202b;padding:8px;margin-top:4px}}.image-scroll{{max-width:100%;overflow:auto;border:1px solid #dae0e7;background:repeating-conic-gradient(#e1e4e9 0% 25%,white 0% 50%) 0/12px 12px}}img{{display:block;max-width:none}}summary{{min-height:44px;padding:12px 0;cursor:pointer}}code,pre{{font-size:12px;overflow-wrap:anywhere;white-space:pre-wrap;word-break:break-word}}.table-scroll{{overflow:auto}}table{{border-collapse:collapse;min-width:600px;width:100%}}th,td{{border-bottom:1px solid #dce0e6;text-align:left;padding:10px}}[hidden]{{display:none!important}}.muted{{color:#576172}}</style><main>
<h1>{TITLE}</h1><p>正在按原版设计系统迁移已加载插件卡片。224 组真实来源对照中，非文字达到固定 99.5% 目标的有 <strong>{v['nonTextAtLeast99_5']}/224</strong>，尺寸一致 {v['dimensionsEqual']}/224，非文字均值 {v['meanNonTextPct']:.8f}%。RGB 均值 {v['meanRgbPct']:.8f}% 单独列出。完整覆盖不代表复刻完成。</p>
<section class="panel"><h2>已验证范围</h2><p>真实发布包的 PluginManagerPage 与原始样式保持不变，仅导出工厂内的组件供合成数据调用。11 个场景，明暗两主题、中英两种语言、桌面与手机、DPR 1 和 2.625；默认场景另含悬停、按住、键盘聚焦。</p><p>13/13 最终检查；13 个归档重新核验 86 个实际输出；33 个生成配方；4 个构建。GPU {receipt['gpu']['assertions']} 个断言 / {receipt['gpu']['pngs']} 张 PNG；Android {receipt['android']['scenes']} 个场景 / {receipt['android']['checks']} 项检查 / {receipt['android']['inputs']} 次输入。正常 APK 已恢复并核对安装字节，自有模拟器已停止，共享 ADB 保留。</p><p>本轮只迁移已加载卡片的 12 处数值匹配：892 → 880。插件管理器还剩 31 处数值匹配，全局仍有 11 处平台控件匹配；没有把来源保留等同于组件实现。</p></section>
<section class="panel"><h2>既有入口与基础组件保留对照</h2><p>每个提供方都重新比较原始 RGBA；卡片改变导致的 Manager 差异按实展示，没有强制全部相同。</p><div class="table-scroll"><table><thead><tr><th>组</th><th>对数</th><th>RGBA 相同</th><th>变化</th><th>非文字均值变化</th></tr></thead><tbody>{preservation}</tbody></table></div></section>
<h2>224 组完整原图</h2><p>每张资产无损拼接两个完整原始帧，未缩放、重着色或裁剪来拟合。每个矩形已逐字节核验 RGBA；页面按原始 DPR 显示逻辑尺寸，较宽图像在内部滚动。图像的来源与 Flutter 大小分别显示，几何详情保留两端实际测量。</p><div id="filters">{''.join(filters)}</div><label>搜索场景或身份<input id="query" type="search" placeholder="例如 metadata-error"></label><button id="reset" type="button">重置筛选</button><p id="visible" aria-live="polite">224 / 224 组</p><div id="gallery">{''.join(cards)}</div>
<section class="panel"><h2>限制与待修复项</h2><ul class="pending">{limits}</ul><h2>固定来源与最终身份</h2><p>DSH 0.2.1-rc.2：<code>{receipt['sourcePin']}</code><br>最终提交／运行提交：<code>{receipt['head']}</code><br>树：<code>{receipt['tree']}</code><br>输入清单 SHA-256：<code>{receipt['manifestSha256']}</code></p><p class="muted">图像均为离线合成数据，不包含真实用户截图或请求日志。整体 99.5% 目标仍未完成。</p></section></main>
<script>const filters=[...document.querySelectorAll('[data-filter]')],query=document.querySelector('#query'),pairs=[...document.querySelectorAll('.pair')];function apply(){{let n=0;const q=query.value.trim().toLowerCase();for(const p of pairs){{p.hidden=filters.some(s=>s.value&&p.dataset[s.dataset.filter]!==s.value)||(q&&!p.textContent.toLowerCase().includes(q));if(!p.hidden)n++}}document.querySelector('#visible').textContent=n+' / 224 组'}}filters.forEach(s=>s.addEventListener('change',apply));query.addEventListener('input',apply);document.querySelector('#reset').addEventListener('click',()=>{{filters.forEach(s=>s.value='');query.value='';apply()}});</script></html>'''


def build(args):
    require(args.out.parent.is_dir() and not args.out.exists() and not args.out.is_symlink(), 'fresh report output required')
    require(re.fullmatch(r'(?:pt_[0-9a-f-]{36}|[a-z][a-z0-9-]{2,100})', args.artifact), 'explicit Artifact identity/name required')
    if args.base == 'null': require(args.seen == 0, 'new Artifact base null requires seen0')
    else: require(str(uuid.UUID(args.base)) == args.base and args.seen > 0, 'fresh existing Artifact revision/seen required')
    e = Evidence(args.stage); receipt, rows, traces = validate(e)
    assets, composites = {}, {}
    for index, row in enumerate(sorted(rows, key=lambda r: r['key'])):
        key = row['key']
        with e.image(f'cards/react/{key}.png') as a, e.image(f'cards/flutter/{key}.png') as b:
            data, proof = composite(a, b)
        name = f'assets/pair-{index:03d}.png'; assets[name] = data
        composites[key] = {'path': name, 'bytes': len(data), 'sha256': sha(data), **proof,
                           'sourceSha256': row['sourceSha256'], 'flutterSha256': row['flutterSha256']}
    require(len(assets) == len(composites) == 224, '224 complete composite assets required')
    document = render(receipt, rows, traces, composites)
    require(contract.common.clean_text(document) == document, 'private paths/credential signature in HTML')
    require(not re.search(r'(?:src|href)\s*=\s*[\"\'](?:https?:|//|data:)|<(?:iframe|link)\b|fetch\(|XMLHttpRequest|navigator\.clipboard', document, re.I),
            'external/inline binary/navigation/network/clipboard not permitted')
    raw = document.encode()
    require(len(raw) < MAX_HTML and document.count('<article class="pair"') == 224, 'HTML/count limit exceeded')
    files = {'index.html': raw, **assets}
    require(len(files) == 225 and len(files) <= 255, 'request file count exceeds cap')
    payload = {'artifact': args.artifact, 'base': None if args.base == 'null' else args.base,
               'seen': args.seen, 'entry': 'index.html', 'title': TITLE,
               'description': f"224组真实来源与Flutter插件卡片对照，非文字99.5%达标{receipt['visual']['nonTextAtLeast99_5']}/224；覆盖不代表完成。",
               'files': {'index.html': {'content': document}, **{name: {'content_base64': base64.b64encode(data).decode('ascii')} for name, data in assets.items()}}}
    payload_bytes = (json.dumps(payload, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode()
    inline_possible = len(payload_bytes) < MAX_REQUEST and all(len(data) <= MAX_INLINE for data in files.values())
    output_manifest = [{'path': name, 'sha256': sha(data), 'bytes': len(data)} for name, data in files.items()]
    build_receipt = {'schema': 'whalee-plugin-cards-report/1', 'head': receipt['head'], 'tree': receipt['tree'],
                     'stageManifestSha256': e.manifest_sha256, 'builderSha256': contract.digest(Path(__file__)),
                     'originalFrames': 448, 'compositeAssets': len(assets), 'requestFiles': len(files),
                     'originalPNGBytes': sum(e.files[f'cards/{p}/{r["key"]}.png']['bytes'] for r in rows for p in ('react', 'flutter')),
                     'assetBytes': sum(len(data) for data in assets.values()), 'htmlBytes': len(raw),
                     'rawVersionBytes': sum(len(data) for data in files.values()), 'inlineJSONBytes': len(payload_bytes),
                     'inlinePayloadReady': inline_possible, 'publishRequestByteCap': MAX_REQUEST, 'perInlineFileByteCap': MAX_INLINE,
                     'files': output_manifest, 'composites': composites, 'visual': receipt['visual'],
                     'published': False, 'planQuotaUnknown': True,
                     'transport': 'files[path].content_base64 for PNG, content for UTF-8 HTML'}
    with tempfile.TemporaryDirectory(prefix='.plugin-cards-report-', dir=args.out.parent) as tmp:
        prepared = Path(tmp) / args.out.name; prepared.mkdir()
        for name, data in files.items():
            path = prepared / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
        if inline_possible:
            (prepared / 'publish.json').write_bytes(payload_bytes)
        else:
            (prepared / 'missing-blob-manifest.json').write_text(json.dumps({'artifact': args.artifact, 'base': payload['base'], 'seen': args.seen,
                'entry': 'index.html', 'files': output_manifest, 'requiredRequestBytes': len(payload_bytes),
                'reason': 'inline request/file byte limit exceeded; no transport guessed and no publication attempted'}, ensure_ascii=False, indent=2) + '\n')
        (prepared / 'build-receipt.json').write_text(json.dumps(build_receipt, ensure_ascii=False, indent=2) + '\n')
        # Read the files actually written and prove rectangles a second time.
        for row in rows:
            c = composites[row['key']]
            with Image.open(prepared / c['path']) as image:
                image = image.convert('RGBA')
                for provider, rect in (('react', c['sourceRect']), ('flutter', c['flutterRect'])):
                    with e.image(f'cards/{provider}/{row["key"]}.png') as original:
                        x, y, w, h = rect
                        require(image.crop((x, y, x + w, y + h)).tobytes() == original.tobytes(), 'written asset RGBA changed')
        require(all(contract.digest(prepared / row['path']) == row['sha256'] for row in output_manifest), 'written report file differs')
        e.recheck(); require(not args.out.exists(), 'output appeared during report generation'); prepared.rename(args.out)
    print(json.dumps({k: build_receipt[k] for k in ('head', 'tree', 'htmlBytes', 'assetBytes', 'rawVersionBytes', 'inlineJSONBytes', 'requestFiles', 'inlinePayloadReady', 'published')}))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for name in ('stage', 'out'): parser.add_argument('--' + name, type=Path, required=True)
    for name in ('artifact', 'base'): parser.add_argument('--' + name, required=True)
    parser.add_argument('--seen', type=int, required=True)
    build(parser.parse_args())

if __name__ == '__main__': main()
