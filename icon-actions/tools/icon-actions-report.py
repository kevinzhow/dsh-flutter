#!/usr/bin/env python3
"""Render a verified local IconAction stage as standalone revision HTML.

No network, browser, product, git or device operations. Revision --base and
--seen must come from the owner's fresh Artifact read. The generated publish
payload is unsent; this script never calls a service.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import html
import importlib.util
import json
from pathlib import Path
import re
import sys
import tempfile
import uuid

from PIL import Image, ImageChops

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('icon_stage_contract', ROOT / 'scripts/icon-actions-evidence.py')
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)
require = contract.require
TITLE = 'Whalee IconAction：真实来源对照与未匹配状态'


def sha(data):
    return hashlib.sha256(data).hexdigest()


class Evidence:
    def __init__(self, folder):
        require(folder.is_dir() and not folder.is_symlink(), 'completed local evidence stage required')
        self.folder = folder
        manifest = folder / 'files.json'
        require(manifest.is_file() and not manifest.is_symlink(), 'staged hash manifest missing')
        self.manifest_sha256 = contract.digest(manifest)
        data = json.loads(manifest.read_text())
        require(data.get('schema') == 'whalee-sanitized-files/1', 'unsupported staged hash contract')
        rows = data['files']
        self.files = {row['path']: row for row in rows}
        require(len(rows) == len(self.files), 'duplicate staged file')
        actual = {str(p.relative_to(folder)) for p in folder.rglob('*') if p.is_file()}
        require(actual == set(self.files) | {'files.json'}, 'staged file set differs from manifest')
        for name, row in self.files.items():
            contract.safe_relative(name)
            file = folder / name
            require(contract.digest(file) == row['sha256'] and file.stat().st_size == row['bytes'], 'staged file hash/size differs: ' + name)
            if file.suffix == '.png':
                with Image.open(file) as picture:
                    require(picture.format == 'PNG', 'non-PNG image in stage')
                    for value in picture.info.values():
                        if isinstance(value, str):
                            require(contract.common.clean_text(value) == value, 'private PNG metadata')
                    picture.load()
            else:
                value = file.read_text()
                require(contract.common.clean_text(value) == value, 'private path or credential-shaped text in stage')
        raw = self.json('raw-inputs.json')
        input_hashes = {row['path']: row['sha256'] for row in raw}
        require(len(input_hashes) == len(raw), 'sanitized raw-input path collision')
        for row in rows:
            if row.get('rawSha256') is not None:
                require(input_hashes.get(row['rawInput']) == row['rawSha256'], 'raw/sanitized identity binding missing')

    def json(self, name):
        require(name in self.files, 'required staged JSON missing: ' + name)
        return json.loads((self.folder / name).read_text())

    def png(self, name):
        require(name in self.files and name.endswith('.png'), 'required staged PNG missing: ' + name)
        return 'data:image/png;base64,' + base64.b64encode((self.folder / name).read_bytes()).decode()

    def recheck(self):
        require(contract.digest(self.folder / 'files.json') == self.manifest_sha256
                and {str(p.relative_to(self.folder)) for p in self.folder.rglob('*') if p.is_file()}
                == set(self.files) | {'files.json'}
                and all(contract.digest(self.folder / name) == row['sha256'] for name, row in self.files.items()),
                'staged evidence changed during report rendering')


def validate(e):
    receipt, full = e.json('receipt.json'), e.json('preflight.json')
    expected = {'head': receipt.get('head'), 'tree': receipt.get('tree')}
    require(all(re.fullmatch('[0-9a-f]{40}', str(v)) for v in expected.values())
            and receipt.get('identityBefore') == receipt.get('identityAfter') == expected
            and receipt.get('runtimeHead') == expected['head'] and receipt.get('runtimeTree') == expected['tree']
            and receipt.get('allowedPostRuntimeChanges') == [] and receipt.get('sourcePin') == contract.SOURCE,
            'exact before/after final runtime identity missing')
    require(set(receipt.get('productTrees', {})) == {'apps', 'features', 'packages'}
            and all(re.fullmatch('[0-9a-f]{40}', v) for v in receipt['productTrees'].values()), 'current product subtrees missing')
    require(full.get('headTree') == expected['tree'] and full.get('fast') is False
            and set(full.get('results', {})) == contract.CHECKS
            and all(row.get('state') == 'ok' for row in full['results'].values()), 'thirteen final checks must be ok')
    scenes, checks, inputs = contract.android_contract(e.json('manifest.json'))
    expected_android = {'captures': len(scenes), 'inputs': len(inputs), 'checks': len(checks), 'cleanupPassed': True}
    require(receipt.get('fullChecks') == 13 and receipt.get('releasePackages') == 13 and receipt.get('releaseFiles') == 85
            and receipt.get('gpu') == {'assertions': 76, 'pngs': 76, 'hardware': True}
            and receipt.get('android') == expected_android, 'completed build/native/source scope differs')
    require({r['name'] for r in receipt.get('builds', [])} == {'android-fixture.apk', 'android-normal.apk',
            'linux-fixture/dsh_flutter', 'linux-normal/dsh_flutter'} and len(receipt['builds']) == 4, 'four exact builds missing')
    debt = receipt['legacyDebt']
    require(debt.get('manual-metric') == 892 and debt.get('duplicate-button', 0) == 0
            and debt.get('platform-control') == 11 and receipt.get('focusOwnershipMismatches') == 36,
            'actual inventory or pending focus count differs')
    manifest_record = e.files['manifest.json']
    require(manifest_record['rawSha256'] == receipt['manifestSha256'], 'manifest raw-byte identity differs')
    gpu = e.json('gpu/runtime.json')
    require(gpu['runtimeHead'] == expected['head'] and gpu['runtimeTree'] == expected['tree'] and gpu['status'] == 'passed'
            and gpu['binaryBefore'] == gpu['binaryAfter'] and gpu['binaryUnchanged'] is True
            and gpu['ownedPidsAbsent'] is True, 'GPU final runtime/cleanup differs')
    android, cleanup = e.json('android/receipt.json'), e.json('android/cleanup.json')
    for data in (android, cleanup):
        require(data.get('passed') is True and data.get('runtimeHead') == expected['head']
                and data.get('runtimeTree') == expected['tree'] and data.get('manifestSha256') == receipt['manifestSha256'], 'Android final runtime differs')
    require(android.get('scenes') == scenes and len(android.get('inputs', [])) == len(inputs)
            and len(android.get('checks', [])) == len(checks)
            and all(a.get('assertion') == label and a.get('passed') is True for a, label in zip(android['checks'], checks)),
            'Android executed literal capture/input/check scope differs')
    normal = next(r['sha256'] for r in receipt['builds'] if r['name'] == 'android-normal.apk')
    require(cleanup.get('normalApkLocalSha256') == cleanup.get('normalApkInstalledSha256') == normal
            and all(cleanup.get(k) is True for k in ('normalApkRestored', 'normalAppForceStopped', 'ownedEmulatorStopped', 'sharedAdbRetained')),
            'normal-app restoration/cleanup missing')
    trace = e.json('profiles/source/source-trace.json')
    require(trace.get('passed') is True and trace['provenance'] == e.json('profiles/source/provenance.json')
            and trace['provenance']['referenceCommit'] == contract.SOURCE, 'actual source proof missing')
    comparison = e.json('profiles/raster/comparison.json')
    raster = e.json('profiles/raster/receipt.json')
    require(comparison.get('head') == raster.get('head') == expected['head']
            and comparison.get('tree') == raster.get('tree') == expected['tree']
            and comparison.get('comparedFrames') == raster.get('comparedFrames') == 144
            and comparison.get('profiles') == contract.PROFILES and len(comparison.get('rows', [])) == 144
            and raster.get('noPixelFittingOrAcceptanceThreshold') is True, 'complete 144 profile-region mappings required')
    source_set = {s['file'] for t in trace['traces'] for s in t['snapshots']}
    require({r['sourceFile'] for r in comparison['rows']} == source_set and len(source_set) == 144, 'source/profile row set differs')
    for row in comparison['rows']:
        pair = 'profiles/raster/pairs/' + Path(row['sourceFile']).stem
        with Image.open(e.folder / pair / 'source.png') as a, Image.open(e.folder / pair / 'flutter.png') as b:
            delta = contract.raw_delta(a, b)
            require(all(row[k] == value for k, value in delta.items()), 'raw profile deltas differ from staged images')
        require(row.get('callbackCountsMatch') is True and row['sourceCalls'] == row['flutterCalls'], 'callback-effect comparison differs')
    require(sum(not r['focusOwnershipMatches'] for r in comparison['rows']) == 36
            and comparison['exactCrops'] == sum(r['changedPixels'] == 0 for r in comparison['rows']), 'raw profile/focus summary differs')
    manager = e.json('manager/summary.json')['cases']
    require(len(manager) == len({r['key'] for r in manager}) == 16, 'sixteen actual PluginManager pairs required')
    raw_manager = {r['key']: r for r in e.json('manager/raw-comparison.json')}
    require(set(raw_manager) == {r['key'] for r in manager}, 'Manager raw-delta identities differ')
    for row in manager:
        key = row['key']
        with Image.open(e.folder / 'manager/react' / (key + '.png')) as a, \
                Image.open(e.folder / 'manager/flutter' / (key + '.png')) as b:
            require(raw_manager[key]['dimensionsEqual'] == (a.size == b.size)
                    and raw_manager[key]['rawRgbaDelta'] == (contract.raw_delta(a, b) if a.size == b.size else None),
                    'Manager raw delta differs from actual pair')
    for name, count in (('preservation108', 108), ('preservation96', 96)):
        identity = e.json(name + '/capture-identity.json')
        require(identity.get('head') == expected['head'] and identity.get('tree') == expected['tree']
                and identity.get('captured') == count, 'fresh preservation capture identity differs')
        require(len(e.json(name + '/summary.json')['cases']) == count, 'preservation summary incomplete')
    return receipt, comparison, manager, e.json('score-history.json')


def esc(value):
    return html.escape(str(value), quote=True)


def render(e, receipt, comparison, manager, history):
    cards = []
    for row in comparison['rows']:
        pair = 'profiles/raster/pairs/' + Path(row['sourceFile']).stem
        pending = row['pending']
        images = ''.join(f'<figure><img loading="lazy" src="{e.png(pair + "/" + name + ".png")}" alt="{esc(label)}"><figcaption>{esc(label)}</figcaption></figure>'
                         for name, label in [('source', 'DSH 实际来源区域'), ('flutter', 'Flutter 区域'), ('rgb-difference-visible', '未放大 RGB 原始差值')])
        filters = ' '.join([row['profile'], row['theme'], f"{row['density']:g}", row['input'], 'pending' if pending else 'unflagged'])
        reasons = ''.join('<li>' + esc(reason) + '</li>' for reason in pending)
        cards.append(f'<article class="pair" data-filter="{esc(filters)}"><h3>{esc(row["profile"])} · {esc(row["state"])}</h3><p>{esc(row["theme"])} · DPR {row["density"]} · {esc(row["input"])}</p><div class="images">{images}</div><p>变化像素 {row["changedPixels"]}/{row["comparedPixels"]} · 最大通道差 {row["maxChannelError"]} · RGBA 平均绝对差 {row["meanAbsoluteRgbaError"]:.8f}</p><p>回调效果计数一致；聚焦归属{("一致" if row["focusOwnershipMatches"] else "不一致，待修复")}。</p>{("<ul class=pending>" + reasons + "</ul>") if pending else "<p>没有已登记的行为标签；原始像素差仍按实展示。</p>"}</article>')
    manager_cards = []
    raw_manager = {r['key']: r for r in e.json('manager/raw-comparison.json')}
    for row in manager:
        key = row['key']
        figures = ''.join(f'<figure><img loading="lazy" src="{e.png("manager/" + provider + "/" + key + ".png")}" alt="{esc(label)}"><figcaption>{esc(label)}</figcaption></figure>'
                          for provider, label in [('react', '实际 PluginManager 来源'), ('flutter', 'Flutter PluginManager')])
        raw = raw_manager[key]['rawRgbaDelta']
        raw_text = (f'原始 RGBA：变化像素 {raw["changedPixels"]}/{raw["comparedPixels"]}，最大通道差 {raw["maxChannelError"]}，平均绝对差 {raw["meanAbsoluteRgbaError"]:.8f}'
                    if raw is not None else '尺寸不相同；保留原图，不缩放或裁剪以计算假相同比较。')
        manager_cards.append(f'<article class="manager"><h3>{esc(key)}</h3><div class="images">{figures}</div><p>非文字 {row["nonTextPct"]:.6f}% · RGB {row["rgbPct"]:.6f}% · 完全像素 {row["pixelPerfectPct"]:.6f}% · 尺寸 {esc(row["sizeReact"])} / {esc(row["sizeFlutter"])}</p><p>{raw_text}</p></article>')
    old, current, regression = history['baseline108'], history['current108'], history['current96']
    limits = ''.join('<li>' + esc(value) + '</li>' for value in receipt['limitations'])
    return f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{TITLE}</title>
<style>:root{{color-scheme:light;font-family:system-ui,sans-serif}}body{{margin:0;background:light-dark(#f6f7f9,#14161b);color:light-dark(#20242c,#e1e4ea)}}main{{max-width:1280px;margin:auto;padding:clamp(12px,3vw,28px)}}h1{{font-size:30px}}h2{{margin-top:40px}}p,li{{line-height:1.6}}code{{overflow-wrap:anywhere}}.panel,.pair,.manager{{background:light-dark(white,#20242b);padding:20px;border-radius:12px;margin:16px 0;border:1px solid light-dark(#dce0e7,#3c424c)}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,330px),1fr));gap:16px}}.images{{display:flex;gap:12px;align-items:flex-start;flex-wrap:wrap}}figure{{margin:0;flex:1;min-width:80px}}img{{display:block;max-width:100%;height:auto;background:repeating-conic-gradient(#ddd 0% 25%,#fff 0% 50%) 0/12px 12px}}.pair img{{min-width:92px;image-rendering:pixelated;max-height:180px}}figcaption{{font-size:12px;margin-top:8px}}.pending{{color:light-dark(#8b3c10,#ffc89d);padding-left:20px}}select{{font:inherit;padding:8px;margin:4px}}[hidden]{{display:none!important}}.muted{{opacity:.75}}</style><main>
<h1>{TITLE}</h1><p>三个原生连接页面动作采用同一来源生成的 IconAction；旧包装已退役，三个调用点已迁移。全组件对齐仍未完成，触摸粘滞悬停、Header 浏览器默认聚焦轮廓及 36 处聚焦归属差异继续待修复。</p>
<section class="panel"><h2>本轮证据范围</h2><p>13/13 检查 · 4 个构建 · GPU 76 断言 / 76 PNG · Android {receipt['android']['captures']} 截图 / {receipt['android']['inputs']} 输入 / {receipt['android']['checks']} 检查。已恢复正常 APK 并核对安装字节，应用及自有模拟器已停止，共享 ADB 保留。</p><p>Android 使用已提交清单中的普通正向 Tab；反向按键注入在 API36 的诊断中却向前移动，仍为待修复／未认证行为。</p><p>真实来源 144 帧：IconAction 80、Header 64。下列是来源测量的控件区域，保留全部差异；不是完整 Web 页面或原生相机／网络复刻。回调效果相同不代表像素或聚焦行为相同。</p><p>库存：892 处数值模式匹配、0 处重复按钮匹配、11 处平台控件匹配。13 个发行包的 85 个保留输入已重新解包核对；来源覆盖不代表实现完成。</p></section>
<section class="panel"><h2>108 / 96 组保留对照</h2><p>108 组非文字均值：{old['meanNonTextPct']:.8f}% → {current['meanNonTextPct']:.8f}%，变化 {history['nonTextMeanDelta108']:+.8f} 个百分点；达到 99.5% 的组数 {current['nonTextAtLeast99_5']}/108。尺寸相同 {current['dimensionsEqual']}/108。</p><p>96 组非文字均值 {regression['meanNonTextPct']:.8f}%；本轮逐提供方 RGBA 相同 {history['current96ProviderRGBAEqual']}/192。108 组逐提供方相同 {history['current108ProviderRGBAEqual']}/216。历史 192 结果单独保留，未推断为本轮结果。</p></section>
<h2>144 组实际来源区域对照</h2><p>精确区域相同 {comparison['exactCrops']}/144；登记有待修复项的帧 {comparison['knownPendingFrames']}/144。差值图保留未放大 RGB，原始 RGBA 差值和统计保留于证据目录。</p>
<div id="filters"><select data-token><option value="">全部家族</option><option>iconAction</option><option>headerAction</option></select><select data-token><option value="">全部主题</option><option>light</option><option>dark</option></select><select data-token><option value="">全部 DPR</option><option>1</option><option>2.625</option></select><select data-token><option value="">全部输入</option><option>mouse</option><option>touch</option></select><select data-token><option value="">全部状态</option><option value="pending">有待修复项</option><option value="unflagged">无已登记标签</option></select></div><p id="visible">144 组</p><div class="grid">{''.join(cards)}</div>
<h2>16 组实际 PluginManager 页面</h2><p>这是现有生产 IconAction 调用入口的来源／Flutter 页面；与上面的控件区域矩阵分开列出。</p>{''.join(manager_cards)}
<section class="panel"><h2>限制与未完成项</h2><ul>{limits}</ul><h2>固定身份</h2><p>提交 <code>{receipt['head']}</code><br>树 <code>{receipt['tree']}</code><br>DSH 0.2.1-rc.2 <code>{receipt['sourcePin']}</code></p><p class="muted">全部图像来自已校验哈希的合成夹具；无真实用户截图、凭据或请求日志。此文件不执行发布操作。</p></section></main>
<script>document.querySelectorAll('[data-token]').forEach(s=>s.addEventListener('change',()=>{{const wanted=[...document.querySelectorAll('[data-token]')].map(s=>s.value).filter(Boolean);let n=0;document.querySelectorAll('.pair').forEach(p=>{{p.hidden=!wanted.every(w=>p.dataset.filter.split(' ').includes(w));if(!p.hidden)n++}});document.querySelector('#visible').textContent=n+' / 144 组'}}));</script></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage', 'out'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('artifact', 'base'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--seen', type=int, required=True)
    args = parser.parse_args()
    require(args.seen > 0 and str(uuid.UUID(args.base)) == args.base and re.fullmatch('pt_[0-9a-f-]{36}', args.artifact),
            'fresh revision base UUID, seen version and Artifact identity required')
    require(args.out.parent.is_dir() and not args.out.exists() and not args.out.is_symlink(), 'fresh report output required')
    e = Evidence(args.stage)
    data = validate(e)
    document = render(e, *data)
    stripped = re.sub('data:image/png;base64,[A-Za-z0-9+/=]+', '[verified-png]', document)
    require(contract.common.clean_text(stripped) == stripped, 'private data in report')
    require(not re.search(r'<(?:iframe|link|base|form)\b|\b(?:href|download|onclick)=|fetch\(|navigator\.clipboard', document, re.I), 'external action in standalone report')
    raw = document.encode()
    require(document.count('data:image/png;base64,') == 144 * 3 + 16 * 2 and len(raw) < 10 * 1024 * 1024,
            'all 144 region trios and 16 page pairs must be inline under10MiB')
    receipt = data[0]
    build = {'head': receipt['head'], 'tree': receipt['tree'], 'htmlSha256': sha(raw), 'htmlBytes': len(raw),
             'profilePairs': 144, 'managerPairs': 16, 'inlineImages': 464, 'published': False,
             'artifact': args.artifact, 'base': args.base, 'seen': args.seen,
             'stagedManifestSha256': e.manifest_sha256, 'stagedFilesVerified': len(e.files)}
    payload = {'artifact': args.artifact, 'base': args.base, 'seen': args.seen, 'entry': 'index.html', 'title': TITLE,
               'icon': 'report', 'description': 'IconAction 144组实际来源区域、16组PluginManager页面；保留粘滞悬停、UA轮廓与36处聚焦归属差异，全部组件对齐仍未完成。',
               'files': {'index.html': {'content': document}}}
    e.recheck()
    with tempfile.TemporaryDirectory(prefix='.icon-report-', dir=args.out.parent) as temporary:
        prepared = Path(temporary) / args.out.name
        prepared.mkdir()
        (prepared / 'index.html').write_bytes(raw)
        for name, value in [('publish.json', payload), ('build-receipt.json', build)]:
            (prepared / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
        require(not args.out.exists(), 'report output appeared during rendering')
        prepared.rename(args.out)
    print(json.dumps(build))


if __name__ == '__main__':
    main()
