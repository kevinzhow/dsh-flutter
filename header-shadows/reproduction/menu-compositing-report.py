#!/usr/bin/env python3
"""Build an offline, inline-image Artifact report from completed staged evidence.

No polling, network, publish, Git mutation, device operation or application run.
The source staging directory must already exist and pass its final receipt/hash
checks. Output is index.html plus an unsent publish_artifact JSON payload.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import html
import io
import json
import math
from pathlib import Path
import re
import tempfile

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / 'scratch/whalee-menu-sticky-evidence/menu-compositing'
OUT = ROOT / 'scratch/menu-compositing-artifact'
SOURCE = '687f282e8625c6b8d11ff58211a90524be2e4317'
CHECKS = {'check-deps', 'tool-tests', 'codegen', 'theme-pack', 'design-system', 'i18n',
          'icons', 'vector', 'parity', 'capability', 'format', 'analyze', 'tests'}
MAX_HTML = 10 * 1024 * 1024
SENSITIVE = re.compile(
    r'-----BEGIN [^-\n]*PRIVATE KEY-----|'
    r'\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|'
    r'github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})\b|\bBearer\s+[A-Za-z0-9._=-]{12,}', re.I)
HOME_PATH = re.compile(r'/(?:home|Users)/[^\s"\'<>]+|/(?:root)(?:/[^\s"\'<>]*)?')
TITLE = 'Whalee 菜单聚焦色修正：108 组对照与剩余差异'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def safe_text(value):
    require(not SENSITIVE.search(value) and not HOME_PATH.search(value), 'private or credential-shaped text in evidence')
    return value


def sha(data):
    return hashlib.sha256(data).hexdigest()


class Evidence:
    def __init__(self, folder):
        self.folder = folder.resolve()
        require(folder.is_dir() and not folder.is_symlink(), 'completed staged evidence is absent or linked')
        manifest = folder / 'files.json'
        require(manifest.is_file() and not manifest.is_symlink(), 'staged file hash manifest missing')
        raw = manifest.read_bytes()
        safe_text(raw.decode())
        rows = json.loads(raw)
        require(isinstance(rows, list) and rows, 'empty staged file manifest')
        self.data = {}
        for row in rows:
            value = row.get('path')
            relative = Path(value) if isinstance(value, str) else Path('..')
            require(value and not relative.is_absolute() and '..' not in relative.parts
                    and value not in self.data, 'unsafe or duplicate evidence manifest path')
            path = folder / relative
            require(path.is_file() and not path.is_symlink()
                    and path.resolve().is_relative_to(self.folder), 'missing, linked or escaped evidence file')
            content = path.read_bytes()
            require(len(content) == row.get('bytes') and sha(content) == row.get('sha256'),
                    'staged evidence hash/length mismatch: ' + value)
            if path.suffix == '.png':
                with Image.open(io.BytesIO(content)) as picture:
                    require(picture.format == 'PNG' and min(picture.size) > 0, 'invalid staged PNG')
                    for text in picture.info.values():
                        if isinstance(text, str):
                            safe_text(text)
                    picture.verify()
            else:
                safe_text(content.decode())
            self.data[value] = content
        require({str(path.relative_to(folder)) for path in folder.rglob('*') if path.is_file()}
                == set(self.data) | {'files.json'}, 'staging has unregistered files')

    def read(self, path):
        require(path in self.data, 'required registered evidence input missing: ' + path)
        return self.data[path]

    def json(self, path):
        return json.loads(self.read(path))

    def picture(self, path, expected_size):
        raw = self.read(path)
        with Image.open(io.BytesIO(raw)) as picture:
            require(list(picture.size) == expected_size and picture.format == 'PNG',
                    'PNG dimensions differ from measured summary')
        return 'data:image/png;base64,' + base64.b64encode(raw).decode('ascii')


def case_info(key):
    match = re.fullmatch(r'components\.reported-(sidebar|model|stats)\.(.+)\.(light|dark)', key)
    require(match is not None, 'unexpected report capture key')
    family, body, theme = match.groups()
    locale = 'zh' if re.search(r'(?:^|-)zh(?:-|$)', body) else 'en'
    layout = 'phone' if '-phone-' in '-' + body + '-' else 'desktop'
    if family == 'sidebar':
        device = 'macOS 桌面' if body.startswith('darwin-') else '手机侧栏内容' if layout == 'phone' else '普通桌面'
        title = device + ' · 工作区侧栏'
    elif family == 'stats':
        device = 'macOS 桌面' if body.startswith('mac-') else '手机' if layout == 'phone' else '普通桌面'
        title = device + ' · ' + ('用量浮层' if '-usage' in body else '活动浮层')
        if '-right-edge' in body:
            title += ' · 右边缘'
    else:
        pane, crop = body.split('-')[:2]
        title = ('手机' if layout == 'phone' else '桌面') + ' · ' + {
            'root': '模型入口菜单', 'model': '模型目录', 'effort': '推理等级',
        }[pane] + ' · ' + ('整页' if crop == 'viewport' else '菜单局部')
    return {'family': family, 'theme': theme, 'layout': layout, 'locale': locale,
            'title': title + ' · ' + ('中文' if locale == 'zh' else 'English') + ' · ' + ('深色' if theme == 'dark' else '浅色')}


def number(value):
    require(type(value) in (int, float) and math.isfinite(value) and 0 <= value <= 100,
            'missing or invalid measured percentage')
    return value


def validate(evidence, runtime_head, runtime_tree):
    receipt = evidence.json('receipt.json')
    full = evidence.json('preflight.json')
    require(receipt.get('runtimeHead') == runtime_head and receipt.get('runtimeTree') == runtime_tree
            and receipt.get('referenceCommit') == SOURCE, 'wrong runtime/source identity')
    require(re.fullmatch(r'[0-9a-f]{40}', receipt.get('head', ''))
            and receipt.get('headTree') == full.get('headTree') and full.get('fast') is False
            and set(full.get('results', {})) == CHECKS
            and all(row.get('state') == 'ok' for row in full['results'].values()),
            'completed final-tree thirteen-check receipt required')
    lock = evidence.json('provenance/sources.lock.json')
    require(lock.get('referenceCommit') == SOURCE and lock.get('packages')
            and all(p.get('version') == '0.2.1-rc.2' for p in lock['packages']
                    if p.get('snapshotFolder', '').startswith('ui-')), 'published package/source pin mismatch')
    summary = evidence.json('components/summary.json')
    cases = summary.get('cases', [])
    require(len(cases) == 108 and len({c['key'] for c in cases}) == 108, 'all 108 unique pairs are required')
    require(summary.get('thresholdPct') == 99.5, 'the visual threshold must remain 99.5%')
    manifest = evidence.json('components/cases.json')
    model_cases = [c for c in manifest.get('cases', []) if c['id'].startswith('components.reported-model.')]
    require(len(model_cases) == 48 and all(
        case.get('variants') and all(variant.get('interactions', [])[-1:] == [
            {'type': 'hover', 'target': 'reported-model-result'}] for variant in case['variants'])
        for case in model_cases), 'new matched-pointer model capture contract required')
    family_counts = {'sidebar': 0, 'stats': 0, 'model': 0}
    for case in cases:
        info = case_info(case['key'])
        family_counts[info['family']] += 1
        for field in ('nonTextPct', 'pixelPerfectPct', 'rgbPct'):
            number(case.get(field))
        for provider, field in (('react', 'sizeReact'), ('flutter', 'sizeFlutter')):
            require(len(case.get(field, [])) == 2 and all(type(n) is int and n > 0 for n in case[field]),
                    'missing pair dimensions')
            prefix = 'components/' + provider + '/' + case['key']
            meta = evidence.json(prefix + '.metadata.json')
            require(meta.get('provider') == provider and meta.get('captureKey') == case['key'],
                    'pair metadata identity mismatch')
            if provider == 'react':
                require(meta.get('react', {}).get('dshCommit') == SOURCE, 'reference PNG source pin mismatch')
            evidence.picture(prefix + '.png', case[field])
    require(family_counts == {'sidebar': 12, 'stats': 48, 'model': 48}, 'reported family coverage differs')
    measured = {'total': len(cases), 'strict': sum(c['nonTextPct'] >= 99.5 for c in cases),
                'dimensions': sum(c['sizeReact'] == c['sizeFlutter'] for c in cases),
                'meanNonText': sum(c['nonTextPct'] for c in cases) / len(cases),
                'meanRgb': sum(c['rgbPct'] for c in cases) / len(cases)}
    recorded = summary.get('allCaptures', {})
    require(recorded.get('compared') == measured['total']
            and recorded.get('dimensionsEqual') == measured['dimensions']
            and recorded.get('nonTextAtLeast99_5') == measured['strict']
            and abs(recorded.get('meanNonTextPct', -1) - measured['meanNonText']) < .000001,
            'computed metrics disagree with staged measured summary')
    builds = receipt.get('builds', [])
    require(len(builds) == 4 and {b['name'] for b in builds} == {
        'android-fixture.apk', 'android-normal.apk', 'linux-fixture/dsh_flutter', 'linux-normal/dsh_flutter'}
        and all(re.fullmatch(r'[0-9a-f]{64}', b.get('sha256', '')) and b.get('successLine') for b in builds),
        'four completed build receipts required')
    gpu_runtime = evidence.json('gpu/runtime.json')
    linux_fixture = next(b for b in builds if b['name'] == 'linux-fixture/dsh_flutter')
    require(gpu_runtime.get('runtimeHead') == runtime_head and gpu_runtime.get('runtimeTree') == runtime_tree
            and gpu_runtime.get('binaryUnchanged') is True
            and gpu_runtime.get('executableSha256') == linux_fixture['sha256']
            and gpu_runtime.get('applicationLibrarySha256') == linux_fixture.get('applicationLibrarySha256'),
            'GPU runtime identity proof missing')
    gpu = receipt.get('gpu', [])
    actual_gpu = []
    for row in gpu:
        env = evidence.json('gpu/' + row['case'] + '/environment.json')
        checks = env.get('captureAssertions', [])
        require(checks and all(c.get('passed') is True for c in checks)
                and len(checks) == row.get('assertions'), 'incomplete GPU assertion receipt')
        actual_gpu.extend(checks)
    require(len(actual_gpu) == 84, '84 completed GPU assertions required')
    android = evidence.json('android/receipt.json')
    require(android.get('passed') is True and len(android.get('scenes', [])) == 15
            and len(android.get('checks', [])) == 41
            and android.get('apkSha256') == next(b['sha256'] for b in builds if b['name'] == 'android-fixture.apk')
            and all(c.get('passed') is True for c in android['checks']), 'completed Android15/41 receipt required')
    cleanup = evidence.json('cleanup.json')
    for key in ('normalApkRestored', 'normalAppForceStopped', 'ownedEmulatorStopped', 'sharedAdbRetained'):
        require(cleanup.get(key) is True, 'runtime cleanup incomplete')
    normal_hash = next(b['sha256'] for b in builds if b['name'] == 'android-normal.apk')
    require(cleanup.get('normalApkLocalSha256') == normal_hash
            and cleanup.get('normalApkInstalledSha256') == normal_hash, 'normal Android restoration hash mismatch')
    preserved = evidence.json('preservation/rgba.json')
    require(len(preserved) == 192 and len({(r['provider'], r['key']) for r in preserved}) == 192
            and {r['provider'] for r in preserved} == {'react', 'flutter'}
            and all(row.get('rgbaByteEqual') is True for row in preserved),
            '192 completed RGBA preservation comparisons required')
    for row in preserved:
        images = []
        for direction in ('before', 'after'):
            path = f"preservation/{direction}/{row['provider']}/{row['key']}.png"
            raw = evidence.read(path)
            require(sha(raw) == row[direction + 'Sha256'], 'preserved PNG hash differs from receipt')
            with Image.open(io.BytesIO(raw)) as picture:
                images.append((picture.size, picture.convert('RGBA').tobytes()))
        require(images[0] == images[1], 'preservation RGBA comparison failed')
    return receipt, cases, measured, {'checks': len(CHECKS), 'builds': len(builds), 'gpu': len(actual_gpu),
                                     'androidScenes': len(android['scenes']), 'androidChecks': len(android['checks']),
                                     'preserved': len(preserved)}


CSS = """
:root{color-scheme:light;font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#20252b;background:#f4f6f8;font-synthesis:none}
*{box-sizing:border-box}body{margin:0;line-height:1.6}main{max-width:1240px;margin:auto;padding:36px 24px 72px}h1{font-size:clamp(25px,3vw,36px);line-height:1.3;margin:12px 0 16px;letter-spacing:-.03em}h2{font-size:21px;margin:0 0 14px}p{margin:0 0 14px}.eyebrow{font-size:13px;letter-spacing:.08em;color:#506272;font-weight:700}.lead{font-size:18px;max-width:920px}.muted{color:#59656f}.panel{background:white;border:1px solid #dfe5ea;border-radius:16px;padding:24px;margin-top:22px}.metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin:22px 0}.metric{background:#fff;border:1px solid #dfe5ea;border-radius:12px;padding:16px}.metric strong{display:block;font-size:26px;line-height:1.3;font-variant-numeric:tabular-nums}.metric span{font-size:13px;color:#59656f}.flag{display:inline-block;background:#fff1db;color:#784b0d;padding:5px 10px;border-radius:6px;font-size:13px;font-weight:650}code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:12px;overflow-wrap:anywhere}.identity{display:grid;gap:7px;font-size:13px;color:#59656f}.checks{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:12px}.check strong{display:block;font-size:20px;font-variant-numeric:tabular-nums}.check span{font-size:13px;color:#59656f}ul{padding-left:21px;margin:0}li+li{margin-top:10px}.filters{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin-top:18px}.filters label{font-size:13px;font-weight:600}.filters select{display:block;width:100%;min-width:0;min-height:44px;margin-top:5px;padding:8px 12px;font:inherit;font-size:16px;border:1px solid #bbc7d0;border-radius:8px;background:white;color:#20252b}.filters select:focus-visible{outline:3px solid #bed8ed;outline-offset:2px}.count{margin:16px 0 0;color:#59656f;font-size:14px}.case{background:white;border:1px solid #dfe5ea;border-radius:16px;margin-top:18px;overflow:hidden}.case-header{padding:18px 20px;border-bottom:1px solid #e6ebef}.case h3{margin:0 0 8px;font-size:17px;line-height:1.45}.case-id{color:#59656f;margin-top:8px;line-height:1.4}.case-metrics{display:flex;flex-wrap:wrap;gap:5px 16px;font-size:13px;color:#43525e;font-variant-numeric:tabular-nums}.dim-diff{color:#945c0c;font-weight:650}.pair{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px;padding:18px 20px;align-items:start}figure{min-width:0;margin:0}figcaption{font-size:13px;color:#43525e;margin-bottom:9px}.image-frame{background:#f7f8fa;border:1px solid #e6ebef;border-radius:8px;overflow:hidden;min-height:30px;display:flex;align-items:flex-start;justify-content:center}.image-frame img{display:block;max-width:100%;height:auto;object-fit:contain}article[hidden]{display:none}.empty{padding:30px 0;color:#59656f}footer{font-size:13px;color:#59656f;margin-top:24px}@media(max-width:760px){.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}.checks{grid-template-columns:repeat(2,minmax(0,1fr))}.filters{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:600px){main{padding:24px 12px 44px}.panel{padding:18px 16px}.pair{grid-template-columns:minmax(0,1fr);padding:16px;gap:20px}.case-header{padding:16px}.lead{font-size:16px}}@media(max-width:340px){.metrics,.filters{grid-template-columns:minmax(0,1fr)}.metric strong{font-size:25px}.checks{gap:14px 8px}.case-metrics{display:block}.case-metrics span{display:block}}
"""

JS = """
(() => {
  const filters = [...document.querySelectorAll('select[data-filter]')];
  const cards = [...document.querySelectorAll('article[data-family]')];
  function apply() {
    let shown = 0;
    for (const card of cards) {
      const visible = filters.every(control => !control.value || card.dataset[control.dataset.filter] === control.value);
      card.hidden = !visible;
      if (visible) shown++;
    }
    document.getElementById('shown-count').textContent = `当前显示 ${shown} / ${cards.length} 组`;
    document.getElementById('empty').hidden = shown > 0;
  }
  filters.forEach(control => control.addEventListener('change', apply));
  apply();
})();
"""


def render(evidence, receipt, cases, measured, validation):
    esc = html.escape
    runtime_head, runtime_tree = receipt['runtimeHead'], receipt['runtimeTree']
    cards = []
    order = {'sidebar': 0, 'stats': 1, 'model': 2}
    for case in sorted(cases, key=lambda c: (order[case_info(c['key'])['family']], c['key'])):
        info = case_info(case['key'])
        dims_equal = case['sizeReact'] == case['sizeFlutter']
        dimensions = ' × '.join(map(str, case['sizeReact'])) + ' / ' + ' × '.join(map(str, case['sizeFlutter']))
        figures = []
        for provider, field, label in (('react', 'sizeReact', '原版 DSH'), ('flutter', 'sizeFlutter', 'Whalee Flutter')):
            data = evidence.picture('components/' + provider + '/' + case['key'] + '.png', case[field])
            figures.append(f'<figure><figcaption>{label}</figcaption><div class="image-frame"><img loading="lazy" decoding="async" src="{data}" width="{case[field][0]}" height="{case[field][1]}" alt="{esc(info["title"] + '，' + label)}"></div></figure>')
        attributes = ' '.join(f'data-{key}="{info[key]}"' for key in ('family', 'theme', 'layout', 'locale'))
        cards.append(f'''<article class="case" {attributes}>
<div class="case-header"><h3>{esc(info['title'])}</h3><div class="case-metrics">
<span>非文字严格一致 {case['nonTextPct']:.3f}%</span><span>RGB 相近度 {case['rgbPct']:.3f}%</span><span>整图相同像素 {case['pixelPerfectPct']:.3f}%</span>
<span class="{'muted' if dims_equal else 'dim-diff'}">尺寸 {'一致' if dims_equal else '有差异'}：{dimensions} px</span></div>
<div class="case-id"><code>{esc(case['key'])}</code></div></div><div class="pair">{''.join(figures)}</div></article>''')
    def dimension(value):
        return str(round(value)) if abs(value - round(value)) < .0001 else f'{value:.5f}'

    directory_sizes = []
    directory_differs = False
    for device, label in (('desktop', '桌面'), ('phone', '手机')):
        key = f'components.reported-model.model-card-{device}-en.light'
        rects = [evidence.json(f'components/{provider}/{key}.metadata.json')['crop']['rect']
                 for provider in ('react', 'flutter')]
        directory_differs |= abs(rects[0]['height'] - rects[1]['height']) > .0001
        directory_sizes.append(label + '目录原版 ' + dimension(rects[0]['width']) + '×' + dimension(rects[0]['height'])
                               + '、Flutter ' + dimension(rects[1]['width']) + '×' + dimension(rects[1]['height']))
    input_residual = '自然输入行高仍有差异。' if directory_differs else '目录高度以当前配对图的实测尺寸为准。'
    input_residual += '；'.join(directory_sizes) + '。'
    final_identity = '' if receipt['head'] == runtime_head else f'<div>最终检查提交 <code>{esc(receipt["head"])}</code>；树 <code>{esc(receipt["headTree"])}</code>。后续允许的变化已由证据脚本核对，原生验证仍固定上述源码。</div>'
    return f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; connect-src 'none'; font-src 'none'"><title>{TITLE}</title><style>{CSS}</style></head><body><main>
<header><div class="eyebrow">WHALEE · 原版界面对照 · 2026-10-28</div><h1>菜单聚焦色已修正，视觉目标仍未完成</h1><p class="lead">侧栏、统计浮层和模型菜单的 {measured['total']} 组真实原版对照中，<strong>{measured['strict']} / {measured['total']} 组达到非文字严格一致 ≥99.5%</strong>；{measured['dimensions']} / {measured['total']} 组截图尺寸一致。</p><span class="flag">总体复刻目标未完成</span></header>
<div class="metrics"><div class="metric"><strong>{measured['strict']} / {measured['total']}</strong><span>非文字严格一致 ≥99.5%</span></div><div class="metric"><strong>{measured['dimensions']} / {measured['total']}</strong><span>两端截图尺寸一致</span></div><div class="metric"><strong>{measured['meanNonText']:.3f}%</strong><span>平均非文字严格一致</span></div><div class="metric"><strong>{measured['meanRgb']:.3f}%</strong><span>平均 RGB 相近度，单独报告</span></div></div>
<section class="panel"><h2>本轮修正与验证</h2><p>本轮由共享菜单声明实际底色，再按原版规则合成聚焦填充，修正暗色模型菜单的色阶误差；未知或半透明底色保持原有绘制。侧栏、统计浮层和模型菜单全部重新对照，统计滤镜试验未纳入本次实现。</p><div class="checks"><div class="check"><strong>{validation['checks']} / {validation['checks']}</strong><span>最终源码完整检查</span></div><div class="check"><strong>{validation['builds']}</strong><span>Linux／Android 两种入口构建</span></div><div class="check"><strong>{validation['gpu']}</strong><span>硬件 GPU 交互断言通过</span></div><div class="check"><strong>{validation['androidScenes']} 场景 · {validation['androidChecks']} 检查</strong><span>Android 触控／按键验证</span></div><div class="check"><strong>{validation['preserved']}</strong><span>既有图像 RGBA 比较完全相同</span></div></div><p class="muted" style="margin-top:16px;margin-bottom:0">既有 96 个案例在两种渲染端逐一比较，共 192 次 RGBA 验证。正常 Android 安装包已恢复并核对字节哈希，应用及自有模拟器已停止，共享 ADB 保留。</p></section>
<section class="panel"><h2>仍存在的差异</h2><ul><li>统计浮层的锐利背景文字透出已修正，但复杂背景上的 Chromium 与 Skia 合成采样仍有色阶差异。显式镜像模式的前后像素完全相同，不能宣称它提高了相似度。</li><li>菜单预合成仍有圆角抗锯齿差异，浅色手机推理菜单的局部探针净增加了 7 个不一致像素；内部填充与原版一致。</li><li>模型搜索的占位文字已改为只参与绘制，不再撑高输入框；{esc(input_residual)}</li><li>Linux 上模拟 macOS 几何和填充，不能证明 macOS 原生窗口半透明背景效果已完成。</li><li>模型触发图标随编辑器宽度收起、选择反馈 Toast、程序把焦点移出后的自动关闭仍未完成。侧栏账号操作、指针停留滚动条及收起动画仍有待办；手机侧栏内容截图不覆盖抽屉边缘手势。</li></ul><p class="muted" style="margin-top:14px;margin-bottom:0">严格非文字指标、RGB 相近度和截图尺寸分别报告；交互检查通过不代表视觉已达到 99.5%。本报告没有修改字体、阈值或截图裁切规则。</p></section>
<section class="panel"><h2>固定参照与源码</h2><div class="identity"><div>发布包版本 <strong>DSH 0.2.1-rc.2</strong>；全部数据为合成测试数据。</div><div>原版源码 <code>{SOURCE}</code></div><div>原生构建及交互源码 <code>{esc(runtime_head)}</code></div><div>原生源码树 <code>{esc(runtime_tree)}</code></div>{final_identity}</div></section>
<section class="panel"><h2>浏览全部 108 组对照</h2><p class="muted">按组件、主题、屏幕和语言筛选。两端在模型菜单截图前把鼠标移到相同结果区域，保持相同悬停状态。左侧为真实原版，右侧为 Flutter；窄屏按上下顺序排列。</p><div class="filters" role="group" aria-label="对照图筛选"><label>组件<select data-filter="family"><option value="">全部组件（108）</option><option value="sidebar">侧栏（12）</option><option value="stats">统计浮层（48）</option><option value="model">模型菜单（48）</option></select></label><label>主题<select data-filter="theme"><option value="">全部主题</option><option value="light">浅色</option><option value="dark">深色</option></select></label><label>屏幕<select data-filter="layout"><option value="">全部屏幕</option><option value="desktop">桌面</option><option value="phone">手机</option></select></label><label>语言<select data-filter="locale"><option value="">全部语言</option><option value="en">English</option><option value="zh">中文</option></select></label></div><p class="count" id="shown-count" role="status" aria-live="polite">当前显示 108 / 108 组</p></section>
<div id="cases">{''.join(cards)}</div><p id="empty" class="empty" hidden>该筛选组合没有对照图。</p><footer>本页包含全部 216 张原始 PNG，图片与指标都来自最终证据文件，并已按清单核对哈希。页面不依赖外部资源，不含真实用户截图、凭据或请求日志。</footer></main><script>{JS}</script></body></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-head', required=True, help='full source SHA of the completed current runtime builds and native replays')
    parser.add_argument('--runtime-tree', required=True, help='full Git tree SHA recorded for that current runtime')
    parser.add_argument('--stage', type=Path, default=STAGE)
    parser.add_argument('--out', type=Path, default=OUT)
    args = parser.parse_args()
    require(re.fullmatch(r'[0-9a-f]{40}', args.runtime_head)
            and re.fullmatch(r'[0-9a-f]{40}', args.runtime_tree), 'runtime head/tree must be full SHA values')
    require(not args.out.exists() and args.out.parent.is_dir(), 'new output directory required; previous report is preserved')
    evidence = Evidence(args.stage)
    receipt, cases, measured, validation = validate(evidence, args.runtime_head, args.runtime_tree)
    document = render(evidence, receipt, cases, measured, validation)
    safe_text(re.sub(r'data:image/png;base64,[A-Za-z0-9+/=]+', '[verified-png]', document))
    raw = document.encode()
    require(len(raw) < MAX_HTML, 'inline HTML exceeds 10 MiB; keep original images and review the report contract')
    require(document.count('data:image/png;base64,') == 216 and document.count('<article class="case"') == 108,
            'report lost a paired image or case')
    require(not re.search(r'<(?:iframe|a|base)\b|\b(?:href|download|onclick)=|navigator\.clipboard|fetch\(', document, re.I),
            'unexpected external navigation or action in report')
    description = (f"侧栏、统计浮层和模型菜单的真实原版对照；严格非文字99.5%达标{measured['strict']}/{measured['total']}，"
                   f"尺寸一致{measured['dimensions']}/{measured['total']}，展示交互验证与未完成视觉差异。")
    payload = {'artifact': 'whalee-reported-families-20261028', 'base': None, 'entry': 'index.html',
               'title': TITLE, 'description': description, 'icon': 'report',
               'files': {'index.html': {'content': document}}}
    with tempfile.TemporaryDirectory(prefix='.reported-report-', dir=args.out.parent) as temporary:
        stage = Path(temporary) / args.out.name
        stage.mkdir()
        (stage / 'index.html').write_bytes(raw)
        (stage / 'publish.json').write_text(json.dumps(payload, ensure_ascii=False) + '\n')
        (stage / 'build-receipt.json').write_text(json.dumps({
            'finalHead': receipt['head'], 'finalTree': receipt['headTree'], 'runtimeHead': receipt['runtimeHead'],
            'runtimeTree': receipt['runtimeTree'], 'sourceCommit': SOURCE, 'pairs': len(cases), 'inlineImages': 216,
            'htmlBytes': len(raw), 'htmlSha256': sha(raw), 'metrics': measured, 'validation': validation,
            'stagedFilesVerified': len(evidence.data), 'published': False,
        }, indent=2, ensure_ascii=False) + '\n')
        require(not args.out.exists(), 'output appeared during report generation')
        stage.rename(args.out)
    print(json.dumps({'pairs': len(cases), 'inlineImages': 216, 'htmlBytes': len(raw),
                      'htmlSha256': sha(raw), 'metrics': measured, 'published': False}))


if __name__ == '__main__':
    main()
