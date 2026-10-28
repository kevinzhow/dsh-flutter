#!/usr/bin/env python3
"""Prepare an unsent source-coverage Artifact from a completed strict Card stage.

Offline and read-only apart from a fresh output directory. No git, device,
service, publication or archive-download calls. --head/--tree bind the owner's
exact accepted candidate; --artifact/--base/--seen come from a fresh Artifact
read. This report verifies the staged reconstruction receipt and all retained
output hashes; it does not claim to reconstruct archives absent from the stage.
"""
from __future__ import annotations

import argparse
from collections import Counter
import copy
import hashlib
import html
import importlib.util
import json
from pathlib import Path
import re
import sys
import tempfile
from urllib.parse import urlsplit

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


visual = module('card_source_visual_contract', 'plugin-cards-report.py')
presentation = module('card_source_presentation', 'design-system-source-report.py')
contract, require = visual.contract, visual.require
TITLE = 'Whalee 设计系统来源覆盖与手写样式清理进度'
CARD_RECIPES = ('DshPluginCardListRecipe', 'DshPluginCardRecipe', 'DshPluginStatusTagRecipe')
SUMMARY = {'uiPackages': 57, 'uiPackagesWithCss': 48, 'uiPackagesWithoutCss': 9,
           'uiCssInputs': 209, 'uiPackagesWithRetainedSnapshots': 13,
           'uiCssRetainedInputs': 36, 'uiCssPendingInputs': 173,
           'supportStylePackages': 9, 'supportCssInputs': 10}
SHA256 = re.compile('[0-9a-f]{64}')
SHA1 = re.compile('[0-9a-f]{40}')
MANAGER = 'features/dsh_feature_plugins/lib/src/manager_page.dart'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON key: ' + key)
        result[key] = value
    return result


def decode(raw):
    def invalid(value):
        raise ValueError('nonfinite JSON number: ' + value)
    return json.loads(raw, object_pairs_hook=unique, parse_constant=invalid)


def safe_text(value):
    require(contract.common.clean_text(value) == value, 'private/credential-shaped report output')
    return value


class Evidence(visual.Evidence):
    """Keep the visual report's complete stage contract, with strict JSON/links."""
    def __init__(self, folder):
        require(folder.is_dir() and not folder.is_symlink(), 'completed Card stage required')
        require(not any(p.is_symlink() for p in folder.rglob('*')), 'linked staged file or directory')
        value = decode((folder / 'files.json').read_bytes())
        require(value.get('schema') == 'whalee-sanitized-files/1'
                and isinstance(value.get('files'), list) and value['files'], 'complete sanitized stage manifest required')
        for row in value['files']:
            contract.safe_relative(row['path'])
            require(row['path'] != 'files.json' and SHA256.fullmatch(str(row.get('sha256')))
                    and type(row.get('bytes')) is int and row['bytes'] >= 0, 'invalid staged hash/size')
            if row.get('rawSha256') is not None:
                require(SHA256.fullmatch(str(row['rawSha256'])) and isinstance(row.get('rawInput'), str),
                        'invalid raw/sanitized hash binding')
        super().__init__(folder)

    def json(self, name):
        require(name in self.files, 'required staged JSON missing: ' + name)
        return decode((self.folder / name).read_bytes())

    def recheck(self):
        require(not any(p.is_symlink() for p in self.folder.rglob('*')), 'linked evidence during report generation')
        super().recheck()


def verify_identity(receipt, head, tree):
    require(SHA1.fullmatch(head) and SHA1.fullmatch(tree), 'explicit full head/tree required')
    expected = {'head': head, 'tree': tree}
    require(receipt.get('schema') == 'whalee-plugin-cards-evidence/1'
            and {key: receipt.get(key) for key in expected} == expected
            and receipt.get('identityBefore') == receipt.get('identityAfter') == expected
            and receipt.get('runtimeHead') == head and receipt.get('runtimeTree') == tree
            and receipt.get('allowedPostRuntimeChanges') == []
            and receipt.get('sourcePin') == contract.SOURCE and receipt.get('packageVersion') == '0.2.1-rc.2',
            'source report requires this exact final/runtime/source identity')
    products = receipt.get('productTrees', {})
    require(set(products) == {'apps', 'features', 'packages'}
            and all(SHA1.fullmatch(str(v)) for v in products.values()), 'product tree identities missing')


def inventory_summary(packages):
    require(len({p['name'] for p in packages}) == len(packages), 'duplicate source package')
    require(all(p.get('scope') in ('ui-package', 'support-styles') for p in packages), 'unknown package scope')
    ui = [p for p in packages if p['scope'] == 'ui-package']
    support = [p for p in packages if p['scope'] == 'support-styles']
    css = [c for p in ui for c in p['css']]
    return {'uiPackages': len(ui), 'uiPackagesWithCss': sum(bool(p['css']) for p in ui),
            'uiPackagesWithoutCss': sum(not p['css'] for p in ui), 'uiCssInputs': len(css),
            'uiPackagesWithRetainedSnapshots': sum(p['snapshot'] is not None for p in ui),
            'uiCssRetainedInputs': sum(c['retention'] == 'retained-input' for c in css),
            'uiCssPendingInputs': sum(c['retention'] == 'pending' for c in css),
            'supportStylePackages': len(support), 'supportCssInputs': sum(len(p['css']) for p in support)}


def verify_debt(receipt, scan, policy):
    require(isinstance(scan.get('perFile'), dict) and scan['perFile'], 'actual per-file family scan missing')
    actual, budget = Counter(), Counter()
    for name, counts in scan['perFile'].items():
        contract.safe_relative(name)
        require(isinstance(counts, dict) and all(type(n) is int and n >= 0 for n in counts.values()),
                'invalid actual scan counts')
        actual.update(counts)
    for counts in policy['baseline'].values():
        require(all(type(n) is int and n >= 0 for n in counts.values()), 'invalid family baseline')
        budget.update(counts)
    actual['duplicate-button'] = actual['duplicate-button']
    require(dict(actual) == scan.get('totals') == receipt.get('legacyDebt'), 'per-file/receipt scan totals differ')
    require(actual['manual-metric'] == budget['manual-metric'] == 880
            and actual['platform-control'] == budget['platform-control'] == 11
            and actual['duplicate-button'] == budget['duplicate-button'] == 0, 'actual debt/budget differs from 880/11/0')
    require(scan['perFile'].get(MANAGER, {}).get('manual-metric') == scan.get('remainingManagerMetrics')
            == receipt.get('remainingManagerMetrics') == 31, 'actual Manager count differs from 31')
    families = policy.get('families', [])
    require(len({f['name'] for f in families}) == len(families) == 16
            and all(isinstance(f.get('migrationStatus'), str) and f['migrationStatus'] for f in families),
            'complete current family states required')
    return dict(actual), dict(budget)


def raw_hash(e, name):
    require(name in e.files and SHA256.fullmatch(str(e.files[name].get('rawSha256'))),
            'raw input hash missing: ' + name)
    return e.files[name]['rawSha256']


def verify_sources(e, receipt):
    ledger = e.json('source/source-inventory.generated.json')
    lock = e.json('source/sources.lock.json')
    release = e.json('source/release-inputs.json')
    recipes = e.json('source/recipes.generated.json')
    policy = e.json('source/families.json')
    scan = e.json('source/actual-family-counts.json')
    require(ledger.get('referenceCommit') == lock.get('referenceCommit') == release.get('referenceCommit')
            == recipes.get('source', {}).get('referenceCommit') == contract.SOURCE, 'source pins differ')
    summary = inventory_summary(ledger['packages'])
    require(summary == SUMMARY == ledger.get('summary') == receipt.get('sourceCoverage'), 'actual source inventory differs')
    require(ledger.get('snapshotLockSha256') == raw_hash(e, 'source/sources.lock.json'), 'inventory/lock binding differs')
    bindings = {'sourceLockSha256': 'source/sources.lock.json',
                'sourceInventorySha256': 'source/source-inventory.generated.json',
                'verificationToolSha256': 'tools/verify_release_inputs.py',
                'publishedVerifierSha256': 'tools/published.py',
                'inventoryVerifierSha256': 'tools/source_inventory.py'}
    require(release.get('allPassed') is True and release.get('verificationInputsUnchanged') is True,
            'completed archive reconstruction required')
    for field, name in bindings.items():
        require(release.get(field) == raw_hash(e, name), 'stale release reconstruction binding: ' + field)
    packages = {p['name']: p for p in lock['packages']}
    verified = {p['name']: p for p in release['packages']}
    require(len(packages) == len(lock['packages']) == len(verified) == len(release['packages'])
            == release.get('packageCount') == receipt.get('releasePackages') == 13
            and set(packages) == set(verified), 'thirteen distinct archive rows required')
    require(recipes['source'].get('packages') == lock['packages'], 'recipe source package lock differs')
    retained, verified_files = {}, 0
    for name, package in packages.items():
        row = verified[name]
        require(row.get('verified') is True and row.get('archiveUnchanged') is True
                and all(row.get(field) == package[field] for field in ('version', 'tarball', 'integrity'))
                and row.get('snapshotFiles') == len(package['files'])
                and SHA256.fullmatch(str(row.get('archiveSha256'))), 'incomplete archive verification: ' + name)
        contract.safe_relative(row['archiveFile'])
        for filename, expected in package['files'].items():
            relative = package['snapshotFolder'] + '/' + filename
            contract.safe_relative(relative)
            require(relative not in retained and SHA256.fullmatch(expected), 'duplicate/invalid retained output')
            staged = 'source/upstream/' + relative
            require(raw_hash(e, staged) == expected, 'retained output raw hash differs: ' + relative)
            retained[relative] = expected
        verified_files += row['snapshotFiles']
    require(verified_files == len(retained) == release.get('verifiedSnapshotFiles') == receipt.get('releaseFiles') == 86,
            'all 86 reconstructed outputs required')
    actual_retained = {name.removeprefix('source/upstream/') for name in e.files if name.startswith('source/upstream/')}
    require(actual_retained == set(retained), 'retained source file set differs')
    source_paths, snapshot_paths, snapshot_packages = set(), set(), set()
    for package in ledger['packages']:
        for item in package['css']:
            contract.safe_relative(item['path'])
            require(item['path'] not in source_paths and SHA256.fullmatch(item['sha256']), 'duplicate/invalid source CSS input')
            source_paths.add(item['path'])
            require(item['retention'] == ('retained-input' if item['retainedInputs'] else 'pending'),
                    'CSS retention contradicts mapping')
        snapshot = package['snapshot']
        bound = [name for item in package['css'] for name in item['retainedInputs']]
        if snapshot is None:
            require(not bound and package['name'] not in packages, 'unbound retained package')
        else:
            require(package['name'] in packages and snapshot['sourceManifest'] == package['sourceManifest']['path']
                    and snapshot['version'] == package['version'] == packages[package['name']]['version'],
                    'retained package owner/version differs')
            snapshot_packages.add(package['name'])
            expected = {'tool/design-system/upstream/' + packages[package['name']]['snapshotFolder'] + '/' + filename: value
                        for filename, value in packages[package['name']]['files'].items()}
            require({r['path']: r['sha256'] for r in snapshot['files']} == expected
                    and len(snapshot['files']) == len(expected), 'inventory snapshot outputs differ')
            require(not snapshot_paths.intersection(expected), 'duplicate inventory snapshot output')
            snapshot_paths.update(expected)
            require(len(bound) == len(set(bound)) and set(bound) == {p for p in expected if p.endswith('.css')},
                    'missing/duplicate/foreign retained CSS binding')
        if not package['css'] and package['scope'] == 'ui-package':
            classification = package.get('noCssClassification')
            require(classification and classification.get('sourceEvidence') and classification.get('explanation'),
                    'CSS-free package classification missing')
    require(snapshot_packages == set(packages), 'inventory retained-package set differs')
    require(len(recipes['metrics']) == receipt.get('recipes') == 33 and set(CARD_RECIPES) <= set(recipes['metrics']),
            'all33 recipes including three loaded Card recipes required')
    require(all(isinstance(recipes['metrics'][name], dict) and recipes['metrics'][name] for name in CARD_RECIPES),
            'empty loaded Card recipe')
    require(any('loaded' in p and p.endswith('.json') for p in retained), 'actual loaded-card published behavior missing')
    debt, budget = verify_debt(receipt, scan, policy)
    return {'ledger': ledger, 'summary': summary, 'lock': lock, 'release': release,
            'recipes': recipes, 'policy': policy, 'scan': scan, 'debt': debt, 'budget': budget}


def render(receipt, data, manifest_sha, visual_url):
    esc = lambda x: html.escape(str(x), quote=True)
    packages = data['ledger']['packages']
    ui = [p for p in packages if p['scope'] == 'ui-package']
    support = [p for p in packages if p['scope'] == 'support-styles']
    options = ''.join(f'<option value="{esc(p["name"])}">{esc(p["name"])}</option>' for p in ui + support)
    families = ''.join('<div class="family"><h3>' + esc(f['name']) + '</h3><p>' + esc(f['migrationStatus']) +
                       '</p><p class="muted">规范实现：<code>' + esc(' · '.join(f.get('canonical', [])) or '尚未登记') +
                       '</code></p>' + (('<ul>' + ''.join('<li>' + esc(p) + '</li>' for p in f['pendingDuplicates']) + '</ul>')
                                        if f.get('pendingDuplicates') else '') + '</div>' for f in data['policy']['families'])
    recipes = ''.join('<details class="card-recipe"><summary>' + esc(name) + '</summary><pre>' +
                      esc(json.dumps(data['recipes']['metrics'][name], ensure_ascii=False, indent=2)) + '</pre></details>'
                      for name in CARD_RECIPES)
    archives = ''.join('<div class="fact-row"><strong>' + esc(p['name']) + '</strong><p>' + str(p['snapshotFiles']) +
                       ' 个已重建输出 · ' + esc(p['version']) + '</p><code>归档 SHA-256 ' + esc(p['archiveSha256']) + '</code></div>'
                       for p in data['release']['packages'])
    scan = ''.join('<div class="input-hash"><code>' + esc(path) + '</code><pre>' +
                   esc(json.dumps(counts, ensure_ascii=False, sort_keys=True)) + '</pre></div>'
                   for path, counts in sorted(data['scan']['perFile'].items()))
    checks = ''.join('<span class="check">' + esc(k) + ' ✓</span>' for k in sorted(contract.CHECKS))
    limits = ''.join('<li>' + esc(text) + '</li>' for text in receipt['limitations'])
    visual_link = ('<p><a id="visual-evidence-link" href="' + esc(visual_url) +
                   '" target="_blank" rel="noopener noreferrer">查看逐图卡片证据</a></p><p class="muted">链接由负责人提供；本离线生成器不检查线上发布状态。</p>') if visual_url else (
                   '<p class="muted">本页未提供线上逐图报告链接；不据此推断已发布。</p>')
    preserve = ''.join('<div class="fact-row"><strong>' + esc(name) + '</strong><p>' +
                       esc(f"{row['providerImages']} 张原始提供方图片：RGBA 相同 {row['rgbaEqual']}，改变 {row['changed']}") +
                       '</p></div>' for name, row in receipt['preservation'].items())
    return f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; connect-src 'none'; font-src 'none'"><title>{TITLE}</title>
<style>{presentation.CSS}pre{{font:12px/1.6 ui-monospace,monospace;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-word}}a{{display:inline-flex;align-items:center;min-height:44px;color:#285d42;overflow-wrap:anywhere}}.card-recipe{{border-top:1px solid #e4e9e4;padding-top:8px}}</style></head>
<body><main data-head="{receipt['head']}" data-tree="{receipt['tree']}"><header><div class="eyebrow">WHALEE · 设计系统来源覆盖 · 已加载插件卡片批次</div><h1>来源已记录，组件迁移仍在继续</h1>
<p class="lead">本批次把已加载插件卡片、列表及状态标签接到三份真实发行配方。现有扫描器仍记录 <strong>880 处数值匹配</strong>，其中 Manager 页面还剩 31 处；173 个 UI CSS 输入尚未保留。</p><span class="status">来源保留 ≠ 配方实现 ≠ 真实入口及全部状态验收完成</span></header>
<div class="metrics"><div class="metric"><strong data-metric="legacy">880</strong><span>扫描器实际数值匹配；不是已逐项认定的错误数</span></div><div class="metric"><strong data-metric="css-pending">173</strong><span>尚未保留的 UI CSS 输入</span></div><div class="metric"><strong data-metric="release">13 / 86</strong><span>已验证发行归档 / 已重建输出</span></div><div class="metric"><strong data-metric="recipes">33</strong><span>生成配方；本批次新增三份加载卡片配方</span></div></div>
<section class="panel"><h2>本批次实际迁移</h2><p>仅覆盖已加载 PluginManager 列表、包卡片和卡内状态标签：标题打开入口与受控 Switch 各自拥有点击及键盘行为。一般卡片、官方配置 ItemCard、高亮效果和其他 Manager 消费方仍待迁移；三份配方不能代表整个卡片家族完成。</p>{recipes}<p class="scope-note">配方字段原样来自证据中的 recipes.generated.json；没有在报告中重写颜色、间距、字体或阈值。</p></section>
<section class="panel"><h2>来源范围与保留状态</h2><p>固定来源的 57 个 UI 包共有 209 个 CSS 输入：36 个绑定了保留文件，173 个尚未保留。另列 9 个支持样式包 / 10 个 CSS 输入，不计入 209。</p><p>13 个真实发行归档重建了 86 个锁定输出，包含加载卡片发布行为区域；33 份生成配方只表示已翻译的特定输入。内联样式、SVG、结构委托、全部变体和真实入口仍需单独审查。</p><p class="scope-note">本报告复核严格证据包的重建回执、原始输入哈希、保留输出以及文件清单；没有重新下载或执行归档。没有上游源码的环境仍不能独立发现清单漏项。</p><details><summary>查看 13 个归档及重建输出数量</summary>{archives}</details></section>
<section class="panel"><h2>剩余样式与家族状态</h2><p>实际扫描总数：<strong>880 数值匹配 / 31 Manager 数值匹配 / 11 原生控件调用 / 0 已知重复按钮调用</strong>。零重复按钮调用只反映当前规则命中的旧构造方式；不证明所有自定义控件已统一。扫描器尚未覆盖全部 Dart 样式表达式。</p><details><summary>查看 {len(data['policy']['families'])} 个家族的当前迁移与待办说明</summary>{families}</details><details><summary>查看逐文件实际扫描结果</summary>{scan}</details></section>
<section class="panel"><h2>同一最终提交的验证与限制</h2><div class="checks">{checks}</div><p style="margin-top:14px">四个构建与原生 GPU、Android 的交互及正常应用恢复记录均绑定下方同一提交和树。完整保留 224 组实际发布来源 / Flutter 对照及组件内部原始几何；固定非文字 99.5% 目标、逐图差异与工具通用通过状态分别记录。</p>{visual_link}<ul>{limits}</ul><details><summary>查看本批次历史对照的实际前后结果</summary>{preserve}</details><p class="scope-note">总体视觉目标仍未完成。来源捕获、覆盖数量、配方生成与运行检查通过，都不能代替全部组件和状态的视觉验收。其他未来批次的证据不自动覆盖本报告。</p></section>
<section class="panel"><h2>查找来源包与 CSS 输入</h2><p class="muted">按包名、路径和保留状态筛选；每条来源保留原始路径、SHA-256 及映射。无独立 CSS 的包仍显示结构或委托分类。</p><div class="filters"><label>来源范围<select name="scope"><option value="">全部来源（66）</option><option value="ui">UI 包（57）</option><option value="support">支持样式（9）</option></select></label><label>指定包<select name="package"><option value="">全部包</option>{options}</select></label><label>CSS 保留状态<select name="retention"><option value="">全部状态</option><option value="pending">有尚未保留输入</option><option value="retained">有已保留输入</option><option value="no-css">没有独立 CSS</option></select></label><label>搜索包名或 CSS 路径<input type="search" name="search" placeholder="例如 PluginManagerPage.module.css" autocomplete="off" spellcheck="false"></label></div><div class="filter-footer"><p id="shown-count" role="status" aria-live="polite"></p><button type="button" id="reset">重置筛选</button></div></section>
<section id="ui-section" class="package-section"><h2>UI 来源包 · 57</h2><p class="section-intro">209 个 CSS 输入：36 已保留 / 173 尚未保留。保留输入不是实现完成标记。</p>{''.join(presentation.render_package(p) for p in ui)}</section><section id="support-section" class="package-section"><h2>支持样式包 · 9</h2><p class="section-intro">另有 10 个 CSS 输入；不将支持包登记视为已支持其功能。</p>{''.join(presentation.render_package(p) for p in support)}</section><p id="empty" class="empty" hidden>没有匹配的来源包。</p>
<section class="panel"><h2>版本与核验依据</h2><div class="facts"><div class="fact-row"><strong>最终提交 / 提交树</strong><code>{receipt['head']}<br>{receipt['tree']}</code></div><div class="fact-row"><strong>固定来源 / 发行版本</strong><code>{contract.SOURCE} / 0.2.1-rc.2</code></div><div class="fact-row"><strong>完整严格证据清单 SHA-256</strong><code>{manifest_sha}</code></div><div class="fact-row"><strong>应用 / 功能 / 共享包 Git 子树</strong><pre>{esc(json.dumps(receipt['productTrees'], indent=2))}</pre></div></div><p class="muted">同目录的 coverage.json、input-hashes.json 与 build-receipt.json 保留结构化统计、原始 / 脱敏双哈希和报告输出身份；publish.json 只是未发送的请求。</p></section>
<footer>离线来源覆盖报告，仅使用合成测试与固定发布输入。没有真实用户截图、凭据、请求日志、外部资源或发送操作；不执行发布、部署或版本发行。</footer></main><script>{presentation.JS}</script></body></html>'''


def validate_document(document, visual_url):
    safe_text(document)
    require(document.count('<article class="package"') == 66 and document.count('<li class="css-row"') == 219
            and document.count('class="card-recipe"') == 3, 'render omitted package/CSS/loaded recipe rows')
    require(not re.search(r'<(?:iframe|link|base|form|img)\b|\b(?:download|onclick)=|navigator\.clipboard|fetch\(', document, re.I),
            'unexpected external resource or action in report')
    links = re.findall(r'<a\b[^>]*\bhref="([^"]+)"', document)
    require(links == ([html.escape(visual_url, quote=True)] if visual_url else [])
            and len(document.encode()) < 10 * 1024**2, 'unexpected report links/size')


def self_test():
    """Mutate real pinned inventory/policy inputs; never fabricate final readiness."""
    repo = ROOT / 'scratch/whalee-plugin-cards/tool/design-system'
    ledger = decode((repo / 'source-inventory.generated.json').read_bytes())
    require(inventory_summary(ledger['packages']) == SUMMARY, 'self-test inventory fixture differs')
    rejected = []
    def reject(label, action):
        try:
            action()
        except (ValueError, KeyError):
            rejected.append(label)
            return
        raise ValueError('negative control accepted: ' + label)
    reject('duplicate-json-key', lambda: decode('{"a":1,"a":2}'))
    reject('nonfinite-json', lambda: decode('{"a":NaN}'))
    duplicate = copy.deepcopy(ledger['packages']); duplicate.append(copy.deepcopy(duplicate[0]))
    reject('duplicate-package', lambda: inventory_summary(duplicate))
    head, tree = '1' * 40, '2' * 40
    receipt = {'schema': 'whalee-plugin-cards-evidence/1', 'head': head, 'tree': tree,
               'runtimeHead': head, 'runtimeTree': tree, 'identityBefore': {'head': head, 'tree': tree},
               'identityAfter': {'head': head, 'tree': tree}, 'allowedPostRuntimeChanges': [],
               'sourcePin': contract.SOURCE, 'packageVersion': '0.2.1-rc.2',
               'productTrees': {'apps': '3' * 40, 'features': '4' * 40, 'packages': '5' * 40}}
    verify_identity(receipt, head, tree)
    for field, value in [('runtimeHead', '9' * 40), ('allowedPostRuntimeChanges', ['tool/change']),
                         ('identityAfter', {'head': '9' * 40, 'tree': tree}), ('productTrees', {})]:
        bad = copy.deepcopy(receipt); bad[field] = value
        reject('identity-' + field, lambda bad=bad: verify_identity(bad, head, tree))
    policy = decode((repo / 'families.json').read_bytes())
    counts = copy.deepcopy(policy['baseline'])
    totals = Counter()
    for row in counts.values(): totals.update(row)
    totals['duplicate-button'] = totals['duplicate-button']
    scan = {'perFile': counts, 'totals': dict(totals), 'remainingManagerMetrics': 31}
    summary_receipt = {'legacyDebt': dict(totals), 'remainingManagerMetrics': 31}
    verify_debt(summary_receipt, scan, policy)
    for label, change in [('false-total', lambda s: s['totals'].update({'manual-metric': 877})),
                          ('false-manager', lambda s: s.update({'remainingManagerMetrics': 30})),
                          ('stale-scan-file', lambda s: s['perFile'][MANAGER].update({'manual-metric': 30}))]:
        bad = copy.deepcopy(scan); change(bad)
        reject(label, lambda bad=bad: verify_debt(summary_receipt, bad, policy))
    print(json.dumps({'schema': 'whalee-card-source-report-self-test/1', 'passed': True,
                      'negativeControls': rejected, 'realInventoryCounts': inventory_summary(ledger['packages']),
                      'syntheticFinalEvidenceUsedForPublication': False}))


def build(args):
    require(args.out.parent.is_dir() and not args.out.exists() and not args.out.is_symlink(), 'fresh output under existing parent required')
    stage = args.stage.absolute()
    require(not args.out.absolute().is_relative_to(stage), 'output must be outside completed stage')
    require(re.fullmatch(r'pt_[0-9a-f-]{36}', args.artifact), 'explicit source Artifact ID required')
    if args.base == 'null':
        require(args.seen == 0, 'new Artifact base=null requires seen=0')
    else:
        require(re.fullmatch(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', args.base)
                and args.seen > 0, 'fresh observed Artifact revision/seen required')
    if args.visual_url:
        url = urlsplit(args.visual_url)
        require(url.scheme == 'https' and url.netloc == 'raft-artifacts.com' and url.path.startswith('/p/')
                and not url.query and not url.fragment, 'explicit public Artifact URL without credentials/query required')
    # The helper code is local, reviewed report code, not sanitized staged code.
    scripts = ('plugin-cards-source-report.py', 'plugin-cards-report.py', 'plugin-cards-evidence.py',
               'icon-actions-evidence.py', 'reported-families-publish.py', 'design-system-source-report.py')
    builders = {name: digest((ROOT / 'scripts' / name).read_bytes()) for name in scripts}
    evidence = Evidence(stage)
    receipt, _, _ = visual.validate(evidence)
    verify_identity(receipt, args.head, args.tree)
    data = verify_sources(evidence, receipt)
    document = render(receipt, data, evidence.manifest_sha256, args.visual_url)
    validate_document(document, args.visual_url)
    coverage = {'schema': 'whalee-plugin-cards-source-coverage/1', 'head': args.head, 'tree': args.tree,
                'sourcePin': contract.SOURCE, 'packageVersion': '0.2.1-rc.2',
                'sourceCoverage': data['summary'], 'legacyDebt': data['debt'], 'legacyBudget': data['budget'],
                'remainingManagerMetrics': 31, 'releasePackages': 13, 'releaseFiles': 86, 'recipes': 33,
                'loadedCardRecipes': {name: data['recipes']['metrics'][name] for name in CARD_RECIPES},
                'packages': data['ledger']['packages'], 'families': data['policy']['families'],
                'actualPerFileScan': data['scan']['perFile'], 'sourceRetentionIsImplementationCompletion': False,
                'stageManifestSha256': evidence.manifest_sha256, 'limitations': receipt['limitations']}
    hashes = {'schema': 'whalee-card-source-report-inputs/1', 'stageManifestSha256': evidence.manifest_sha256,
              'files': [evidence.files[name] for name in sorted(evidence.files)], 'reportTools': builders}
    output = {'index.html': document, 'coverage.json': json.dumps(coverage, ensure_ascii=False, indent=2, allow_nan=False) + '\n',
              'input-hashes.json': json.dumps(hashes, ensure_ascii=False, indent=2, allow_nan=False) + '\n'}
    for value in output.values(): safe_text(value)
    payload = {'artifact': args.artifact, 'base': None if args.base == 'null' else args.base, 'seen': args.seen,
               'entry': 'index.html', 'title': TITLE, 'icon': 'report',
               'description': '已加载卡片新增三份发行配方；实际扫描仍有880处数值匹配（Manager31）、11处原生控件调用、0个已知重复按钮调用；57包209个CSS中36保留、173待保留。来源保留不等于实现或视觉完成。',
               'files': {name: {'content': value} for name, value in output.items()}}
    output['publish.json'] = safe_text(json.dumps(payload, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n')
    require(len(output['publish.json'].encode()) < 24 * 1024**2
            and all(len(v.encode()) < 10 * 1024**2 for v in output.values()), 'unsent Artifact request exceeds inline limit')
    report = {'schema': 'whalee-plugin-cards-source-report/1', 'head': args.head, 'tree': args.tree,
              'sourcePin': contract.SOURCE, 'stageManifestSha256': evidence.manifest_sha256,
              'evidenceFilesVerified': len(evidence.files), 'sourceCoverage': data['summary'],
              'legacyDebt': data['debt'], 'remainingManagerMetrics': 31, 'releasePackages': 13, 'releaseFiles': 86,
              'recipes': 33, 'loadedCardRecipes': list(CARD_RECIPES), 'fullChecks': 13,
              'sourceRetentionIsImplementationCompletion': False,
              'archiveReconstruction': 'completed strict-stage receipt and retained output bindings verified; archives not rerun by report',
              'visualArtifact': {'url': args.visual_url, 'publicationVerified': False},
              'artifact': {'id': args.artifact, 'base': payload['base'], 'seen': args.seen},
              'reportTools': builders, 'files': [{'path': name, 'sha256': digest(value.encode()), 'bytes': len(value.encode())}
                                               for name, value in output.items()],
              'payloadWritten': True, 'published': False}
    output['build-receipt.json'] = safe_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    with tempfile.TemporaryDirectory(prefix='.plugin-cards-source-report-', dir=args.out.parent) as temporary:
        prepared = Path(temporary) / args.out.name; prepared.mkdir()
        for name, value in output.items(): (prepared / name).write_text(value)
        require(all((prepared / name).read_bytes() == value.encode() for name, value in output.items()), 'written report bytes differ')
        evidence.recheck()
        require(all(digest((ROOT / 'scripts' / name).read_bytes()) == value for name, value in builders.items()), 'report tools changed during generation')
        require(not args.out.exists(), 'output appeared during validation'); prepared.rename(args.out)
    print(json.dumps({'head': args.head, 'tree': args.tree, 'stageManifestSha256': evidence.manifest_sha256,
                      'htmlBytes': len(document.encode()), 'payloadWritten': True, 'published': False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--self-test', action='store_true', help='real inventory/count and malformed identity negative controls; no output files')
    for name in ('stage', 'out'): parser.add_argument('--' + name, type=Path)
    for name in ('head', 'tree', 'artifact', 'base'): parser.add_argument('--' + name)
    parser.add_argument('--seen', type=int)
    parser.add_argument('--visual-url', help='optional explicit public visual Artifact link; no network read')
    args = parser.parse_args()
    if args.self_test:
        self_test(); return
    for name in ('stage', 'out', 'head', 'tree', 'artifact', 'base', 'seen'):
        require(getattr(args, name) is not None, '--' + name + ' is required')
    build(args)


if __name__ == '__main__':
    main()
