#!/usr/bin/env python3
"""Prepare source-coverage Artifact v2 from complete final evidence; never publish.

Use --check-ready to inspect missing inputs without creating output. Generation
requires a fresh output directory; publish.json is written only after --preview
passes and every source/evidence input is rechecked. No device or network writes.
"""
from __future__ import annotations

import argparse
from collections import Counter
import copy
import html
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REPO = ROOT / 'scratch/whalee-source-shadows'
DEFAULT_STAGE = ROOT / 'scratch/whalee-menu-sticky-evidence/header-shadows'
DEFAULT_OUT = ROOT / 'scratch/header-shadows-source-artifact'
BASE = '875ef6936bc5337afcc3a187b2de80ad22963ccb'
SOURCE = '687f282e8625c6b8d11ff58211a90524be2e4317'
ARTIFACT = 'pt_7e85a381-0b4e-49af-aac9-afe4b78a1f1f'
VISUAL_URL = 'https://raft-artifacts.com/p/myoland/whalee-reported-families-20261028/v/3'
STATE = ROOT / 'notes/source-coverage-artifact-current.json'
COMMENTS = ROOT / 'notes/source-coverage-artifact-comments.json'
CHECKS = {'check-deps', 'tool-tests', 'codegen', 'theme-pack', 'design-system',
          'i18n', 'icons', 'vector', 'parity', 'capability', 'format', 'analyze', 'tests'}
TITLE = 'Whalee 设计系统来源覆盖与手写样式清理进度'
HOME_PATH = re.compile(r'(?<![A-Za-z0-9_.])/(?:home|Users)/[^\s"\'<>]+|(?<![A-Za-z0-9_.])[home-path](?:/[^\s"\'<>]*)?(?=$|[\s"\'<>])')
spec = importlib.util.spec_from_file_location('historical_source_report', ROOT / 'scripts/design-system-source-report.py')
historical = importlib.util.module_from_spec(spec)
spec.loader.exec_module(historical)
require, digest, unique_object = historical.require, historical.digest, historical.unique_object


def safe_text(text):
    require(not historical.SENSITIVE.search(text) and not HOME_PATH.search(text),
            'private/credential-shaped report output')
    return text


def git(repo, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=repo).decode().strip()


def safe_relative(value):
    require(isinstance(value, str) and value and '\\' not in value and ':' not in value
            and not PurePosixPath(value).is_absolute()
            and all(part not in ('', '.', '..') for part in value.split('/')), 'unsafe evidence path')
    return value


class Inputs:
    def __init__(self, repo, head, source):
        self.repo, self.head, self.source = repo, head, source
        self.records, self.paths = {}, {}

    def read(self, path, role, committed=False, reference=False):
        require(path.is_file() and not path.is_symlink(), 'missing/linked report input: ' + path.name)
        raw = path.read_bytes()
        if reference:
            relative = path.relative_to(self.source).as_posix()
            name = 'reference/' + relative
            blob = subprocess.check_output(['git', 'show', SOURCE + ':' + relative], cwd=self.source)
            require(blob == raw, 'reference bytes differ from pinned Git input: ' + relative)
        elif path.is_relative_to(self.repo):
            relative = path.relative_to(self.repo).as_posix()
            name = 'repo/' + relative
            if committed:
                blob = subprocess.check_output(['git', 'show', self.head + ':' + relative], cwd=self.repo)
                require(blob == raw, 'report input differs from final Git blob: ' + relative)
        else:
            require(path.is_relative_to(ROOT), 'report input escaped the workspace')
            name = 'workspace/' + path.relative_to(ROOT).as_posix()
        row = {'path': name, 'sha256': digest(raw), 'bytes': len(raw), 'role': role}
        require(name not in self.records or self.records[name]['sha256'] == row['sha256'],
                'report input changed while reading: ' + name)
        self.records[name], self.paths[name] = row, path
        return raw

    def json(self, path, role, committed=False):
        return json.loads(self.read(path, role, committed), object_pairs_hook=unique_object)

    def module(self, relative, name):
        path = self.repo / relative
        self.read(path, 'verification code', committed=True)
        spec = importlib.util.spec_from_file_location('header_source_report_' + name, path)
        result = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(result)
        return result

    def recheck(self):
        for name, path in self.paths.items():
            require(not path.is_symlink() and digest(path.read_bytes()) == self.records[name]['sha256'],
                    'report input changed during generation: ' + name)


def validate_full(full, tree):
    require(full.get('headTree') == tree and full.get('fast') is False
            and set(full.get('results', {})) == CHECKS
            and all(row.get('state') == 'ok' for row in full['results'].values()),
            'all thirteen exact-final-tree checks must be ok; no skipped checks')


def validate_manifest(inputs, stage):
    rows = inputs.json(stage / 'files.json', 'final runtime evidence manifest')
    require(isinstance(rows, list) and rows, 'empty evidence manifest')
    names = [safe_relative(row['path']) for row in rows]
    require(len(names) == len(set(names)) and 'files.json' not in names, 'duplicate/self-listed evidence path')
    actual = {p.relative_to(stage).as_posix() for p in stage.rglob('*') if p.is_file()}
    require(actual == set(names) | {'files.json'} and not any(p.is_symlink() for p in stage.rglob('*')),
            'missing/extra/linked final evidence file')
    for row in rows:
        raw = inputs.read(stage / row['path'], 'verified final runtime evidence')
        require(digest(raw) == row['sha256'] and len(raw) == row['bytes'], 'evidence hash/size differs: ' + row['path'])
    return rows


def validate_stage(receipt, head, tree, summary, counts):
    require(receipt.get('schema') == 'header-shadows-evidence/1'
            and receipt.get('head') == receipt.get('runtimeHead') == head
            and receipt.get('headTree') == receipt.get('runtimeTree') == tree
            and receipt.get('base') == BASE and receipt.get('referenceCommit') == SOURCE
            and receipt.get('allowedPostRuntimeChanges') == [],
            'runtime evidence must use the exact final candidate; historical/post-runtime carryover is not acceptance')
    require(receipt.get('fullChecks') == 13 and receipt.get('releasePackages') == 13
            and receipt.get('releaseFiles') == 85 and receipt.get('sourceCoverage') == summary
            and receipt.get('legacyDebt') == counts and receipt.get('modelSeatSemanticBoundary') is True,
            'runtime source/coverage/ModelSeat proof differs')
    require(receipt.get('androidScenes') == 23 and receipt.get('androidChecks') == 54
            and receipt.get('headerPairs') == 16 and receipt.get('headerPriorFlutterPreserved') == 16
            and receipt.get('preservedProviderImages') == 192, 'bounded native/Header/regression coverage incomplete')
    names = {b.get('name') for b in receipt.get('builds', [])}
    require(len(receipt.get('builds', [])) == 4 and names == {
        'android-fixture.apk', 'android-normal.apk', 'linux-fixture/dsh_flutter', 'linux-normal/dsh_flutter'},
        'four final candidate builds required')
    require(set(receipt.get('gpu', {})) == {'menu', 'header'}, 'both native replay families required')
    for name, assertions, cases in [('menu', 84, 2), ('header', 72, 4)]:
        row = receipt['gpu'][name]
        require(row.get('assertions') == assertions and len(row.get('cases', [])) == cases
                and sum(c['assertions'] for c in row['cases']) == assertions,
                'native replay assertion/case coverage differs: ' + name)
    proof = receipt.get('menuSourceProof', {})
    require(proof.get('sourceCommit') == SOURCE and proof.get('caseCount') == 2
            and proof.get('correctOneRowChangedPixels') == [0, 0]
            and len(proof.get('actualTwoRowChangedPixels', [])) == 2
            and all(value > 0 for value in proof['actualTwoRowChangedPixels'])
            and proof.get('historicalNativeIsAcceptance') is False, 'actual source menu controls incomplete')
    require(receipt.get('releaseOrDeployment') is False and receipt.get('limitations'), 'evidence scope limits missing')
    visual = receipt.get('visual', {})
    require(visual.get('allCaptures', {}).get('compared') == 108 and len(visual.get('cases', [])) == 108
            and receipt.get('scoreHistory', {}).get('previous', {}).get('compared') == 108,
            'complete current and historical 108-pair comparison required')


def artifact_state(inputs):
    state = inputs.json(STATE, 'observed source Artifact base/seen')['data']['result']
    comments = inputs.json(COMMENTS, 'source Artifact comments read before revision')['data']['result']
    artifact, version = state['artifact'], state['version']
    require(artifact.get('artifact_id') == ARTIFACT and version.get('id') == artifact.get('current_revision_id')
            and version.get('number') == state.get('seen') == 1, 'expected current source Artifact v1 observation')
    require(comments.get('items') == [] and comments.get('next_offset') is None,
            'source Artifact comments require review before this bounded revision')
    return {'artifact': ARTIFACT, 'base': version['id'], 'seen': state['seen'],
            'intendedVersion': 2, 'stableUrl': artifact['stable_url']}


def collect(repo, head, stage, source):
    require(re.fullmatch('[0-9a-f]{40}', head) and git(repo, 'rev-parse', 'HEAD') == head
            and not git(repo, 'status', '--porcelain'), 'exact clean final candidate required')
    tree = git(repo, 'rev-parse', 'HEAD^{tree}')
    inputs = Inputs(repo, head, source)
    inputs.read(Path(__file__).resolve(), 'source report v2 builder')
    inputs.read(ROOT / 'scripts/design-system-source-report.py', 'unchanged historical presentation helper')
    full = inputs.json(repo / '.local/header-shadows-final-full.json', 'final required checks')
    validate_full(full, tree)
    ledger = inputs.json(repo / 'tool/design-system/source-inventory.generated.json', 'complete source-input ledger', True)
    lock = inputs.json(repo / 'tool/design-system/sources.lock.json', 'published source lock', True)
    recipes = inputs.json(repo / 'tool/design-system/recipes.generated.json', 'generated family recipes', True)
    policy = inputs.json(repo / 'tool/design-system/families.json', 'current family debt policy', True)
    inventory = inputs.module('tool/design-system/source_inventory.py', 'inventory')
    guard = inputs.module('tool/design-system/check.py', 'guard')
    require(ledger['referenceCommit'] == lock['referenceCommit'] == SOURCE, 'reference pin differs')
    inventory.check_source(ledger, source, repo)
    summary = inventory.summary(ledger['packages'])
    require(summary == ledger['summary'] and summary['uiPackages'] == 57 and summary['uiCssInputs'] == 209
            and summary['uiCssRetainedInputs'] == 36 and summary['uiCssPendingInputs'] == 173
            and summary['supportStylePackages'] == 9 and summary['supportCssInputs'] == 10, 'source cohort differs')
    source_paths = {}
    def paths(value):
        if isinstance(value, dict):
            if 'path' in value and 'sha256' in value and not value['path'].startswith('tool/'):
                require(value['path'] not in source_paths or source_paths[value['path']] == value['sha256'], 'ambiguous source hash')
                source_paths[value['path']] = value['sha256']
            for child in value.values():
                paths(child)
        elif isinstance(value, list):
            for child in value:
                paths(child)
    paths(ledger)
    for package in lock['packages']:
        source_paths.update(package.get('referenceSourceSha256', {}))
    for path, expected in sorted(source_paths.items()):
        raw = inputs.read(source / safe_relative(path), 'actual pinned reference input', reference=True)
        require(digest(raw) == expected, 'source hash differs: ' + path)
    inputs.read(source / 'LICENSE', 'reference license', reference=True)
    release = inputs.json(repo / '.local/preflight/release-inputs.json', 'actual completed release reconstruction')
    bindings = {'sourceLockSha256': 'sources.lock.json', 'sourceInventorySha256': 'source-inventory.generated.json',
                'verificationToolSha256': 'verify_release_inputs.py', 'publishedVerifierSha256': 'published.py',
                'inventoryVerifierSha256': 'source_inventory.py'}
    require(release.get('allPassed') is True and release.get('verificationInputsUnchanged') is True
            and release.get('referenceCommit') == SOURCE, 'completed actual release verification required')
    for field, name in bindings.items():
        require(release.get(field) == digest(inputs.read(repo / 'tool/design-system' / name, 'release verification input', True)),
                'stale release receipt: ' + field)
    packages = {p['name']: p for p in lock['packages']}
    verified = release.get('packages', [])
    require(len(verified) == release.get('packageCount') == len(packages) == 13
            and {r['name'] for r in verified} == set(packages), 'release package coverage differs')
    for row in verified:
        p = packages[row['name']]
        require(row.get('verified') is True and row.get('archiveUnchanged') is True
                and row.get('snapshotFiles') == len(p['files'])
                and all(row[k] == p[k] for k in ('version', 'tarball', 'integrity')), 'incomplete released output reconstruction')
        for name, expected in p['files'].items():
            require(digest(inputs.read(repo / 'tool/design-system/upstream' / p['snapshotFolder'] / name,
                                       'actual retained released input', True)) == expected, 'retained release input differs')
    require(sum(r['snapshotFiles'] for r in verified) == release.get('verifiedSnapshotFiles') == 85,
            'all 85 actual released outputs required')
    guard.validate_contract(policy)
    counts_by_file, failures = guard.inspect(repo, policy)
    require(not failures, 'current source guard failed')
    counts, budget = Counter(), Counter()
    for row in counts_by_file.values():
        counts.update(row)
    for row in policy['baseline'].values():
        budget.update(row)
    require(counts['manual-metric'] == budget['manual-metric'] == 895, 'current metric matches/allowance differ')
    for path in guard.sources(repo):
        inputs.read(path, 'actual source scanned for existing metric matches', True)
    leading_path = 'features/dsh_feature_sidebar/lib/src/leading_controls.dart'
    old_leading = subprocess.check_output(['git', 'show', BASE + ':' + leading_path], cwd=repo).decode()
    removed = guard.scan(old_leading, policy['patterns']).get('manual-metric', 0) - counts_by_file.get(leading_path, {}).get('manual-metric', 0)
    require(removed == 4, 'Header real metric reduction differs')
    prior_recipes = json.loads(subprocess.check_output(['git', 'show', BASE + ':tool/design-system/recipes.generated.json'], cwd=repo))['metrics']
    require(len(prior_recipes) == 29 and len(recipes['metrics']) == 30
            and set(recipes['metrics']) - set(prior_recipes) == {'DshHeaderLeadingRecipe'}
            and all(recipes['metrics'][name] == value for name, value in prior_recipes.items()), 'existing recipe profile preservation differs')
    for path in ['tool/design-system/header_leading_recipes.py', 'tool/design-system/generate.py', 'tool/preflight',
                 'packages/dsh_ui/lib/src/dsh_recipes.g.dart', 'packages/dsh_ui/lib/src/dsh_shadow_box.dart',
                 'features/dsh_feature_model_selection/lib/src/model_select.dart',
                 'features/dsh_feature_model_selection/test/model_selection_test.dart',
                 'docs/design-system/header-leading.md', 'docs/design-system/source-shadows.md']:
        inputs.read(repo / path, 'changed source/semantic contract', True)
    changed = git(repo, 'diff', '--name-only', BASE, head, '--', 'apps', 'features', 'packages').splitlines()
    require(changed, 'bounded runtime component changes expected')
    for path in changed:
        inputs.read(repo / path, 'final changed runtime/test input', True)
    manifest = validate_manifest(inputs, stage)
    evidence = inputs.json(stage / 'receipt.json', 'final runtime evidence receipt')
    validate_stage(evidence, head, tree, summary, dict(counts))
    require(inputs.json(stage / 'preflight.json', 'staged final check receipt') == full, 'staged checks differ')
    require(inputs.json(stage / 'release-inputs.json', 'staged actual release receipt') == release, 'staged release receipt differs')
    artifact = artifact_state(inputs)
    data = {'head': head, 'tree': tree, 'full': full, 'ledger': ledger, 'recipes': recipes, 'policy': policy,
            'summary': summary, 'counts': dict(counts), 'budget': dict(budget), 'headerMetricReduction': removed,
            'runtimeChangedPaths': changed, 'stage': evidence, 'stageFiles': len(manifest) + 1,
            'stageManifestSha256': digest((stage / 'files.json').read_bytes()), 'artifact': artifact}
    return inputs, data


def render(data, rows):
    esc = html.escape
    s, debt, evidence = data['summary'], data['counts'], data['stage']
    ui = [p for p in data['ledger']['packages'] if p['scope'] == 'ui-package']
    support = [p for p in data['ledger']['packages'] if p['scope'] == 'support-styles']
    options = ''.join(f'<option value="{esc(p["name"])}">{esc(p["name"])}</option>' for p in ui + support)
    packages = lambda values: ''.join(historical.render_package(p) for p in values)
    families = ''.join(f'<div class="family"><strong>{esc(f["name"])}</strong><p class="muted">{esc(f["migrationStatus"])}</p></div>' for f in data['policy']['families'])
    checked = ''.join(f'<span class="check">{esc(k)} ✓</span>' for k in sorted(CHECKS))
    limits = ''.join('<li>' + esc(text) + '</li>' for text in [
        '895 是现有扫描器记录的数值匹配，并非逐项证明错误的 895 处样式；扫描器仍未覆盖全部 Dart 样式表达式。',
        '173 是尚未保留的 UI CSS 输入数，并非未实现组件数。来源保留、配方生成、真实入口与所有状态的验收是不同事项。',
        'Header 的原生 Chromium auto-outline 像素与几何仍未对齐；AppFrame 挂载、窗口交通灯位置、跨窗口及输入法组合状态仍有边界。',
        '本轮阴影转换只覆盖当前圆角透明面板。原始不透明背景、方形硬裁剪、一般变换与超椭圆轮廓尚未获完整验收。',
        '统计面板的组合背景采样、macOS 原生材质、模型自然输入行高与其他已有差异仍保留。总体 99.5% 视觉目标未完成。',
        '无源码环境可以重建已锁定发行输入，无法独立发现遗漏的上游源码范围；内联样式、SVG、委托控制与所有适用状态仍需逐项登记和迁移。'])
    hashes = ''.join(f'<div class="input-hash"><code class="path">{esc(row["path"])}</code><code>SHA-256 {row["sha256"]}</code></div>' for row in rows)
    metrics = evidence['visual']['allCaptures']
    previous = evidence['scoreHistory']['previous']
    current_mean = metrics['meanNonTextPct']
    prior_mean = previous['meanNonTextPct']
    return f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; connect-src 'none'; font-src 'none'"><title>{TITLE}</title><style>{historical.CSS}
.evidence-link{{display:inline-flex;align-items:center;min-height:44px;max-width:100%;overflow-wrap:anywhere;color:#285d42}}.change{{margin-top:16px;padding-top:14px;border-top:1px solid #e4e9e4}}
</style></head><body><main data-head="{data['head']}">
<header><div class="eyebrow">WHALEE · 设计系统来源核对 · 修订 2</div><h1>从来源清单走向组件迁移</h1><p class="lead">Header 的 {data['headerMetricReduction']} 处实际数值匹配已移除，现有扫描器仍记录 <strong>{debt['manual-metric']} 处匹配</strong>；{s['uiCssPendingInputs']} 个 UI CSS 输入尚未保留。本轮也修正了阴影换算与模型按钮的原生点击边界，整体迁移仍在继续。</p><span class="status">来源保留 ≠ 组件与状态验收完成</span></header>
<div class="metrics"><div class="metric"><strong data-metric="legacy">{debt['manual-metric']}</strong><span>现有数值匹配；此前 899</span></div><div class="metric"><strong>{s['uiCssPendingInputs']}</strong><span>尚未保留的 UI CSS 输入</span></div><div class="metric"><strong>13 / 85</strong><span>真实发行归档 / 已重建文件</span></div><div class="metric"><strong data-metric="recipes">30</strong><span>生成配方；原有 29 个保持不变</span></div></div>
<section class="panel"><h2>本轮来源修正</h2><div class="change" data-claim="header"><h3>Header 回到规范按钮</h3><p>尺寸、间距、图标与提示延迟来自同版发布输入，统一由 Header 配方和规范按钮承载；四处实际手写数值匹配已删除。旧配方和其他未完成家族仍保留各自范围。</p></div><div class="change" data-claim="shadow"><h3>阴影恢复 CSS 转换</h3><p>移除截图拟合换算和固定外部裁剪，按原版规则把 blur 转换为 sigma，并逐层排除透明面板内部。没有调整来源颜色、字体、分类器或阈值。</p></div><div class="change" data-claim="model-boundary"><h3>模型按钮拥有自己的原生点击边界</h3><p>新增快捷键外层曾使按钮语义与整页合并，原生输入点落在空白区域。规范控件现在保留独立边界；先保留失败证据，再验证边界及实际点击流程。</p></div><div class="change" data-claim="source-guards"><h3>来源检查保留语义</h3><p>Header 指纹保留字符串与标识符里的空白，只翻译受支持的数值字段；不支持的整数写法、未知状态和未翻译的声明会使检查失败。</p></div></section>
<section class="panel"><h2>最终提交的验证</h2><div class="checks">{checked}</div><p style="margin-top:14px">同一提交完成四个构建、菜单与 Header 的硬件 GPU 回放（{evidence['gpu']['menu']['assertions']} / {evidence['gpu']['header']['assertions']} 项断言）、Android {evidence['androidScenes']} 场景 / {evidence['androidChecks']} 项检查，以及正常应用恢复和自有进程清理。</p><p>另保留 108 组原版对照、16 组 Header 对照与 192 张 RGBA 一致性图片。108 组非文字均值为 {current_mean:.6f}%（此前 {prior_mean:.6f}%）；来源正确的转换不等于分数上涨，原始下降也保留。所有运行证据绑定相同最终 head/tree。</p><a id="visual-evidence-link" class="evidence-link" href="{VISUAL_URL}" target="_blank" rel="noopener noreferrer">查看逐图视觉证据 v3</a><p class="muted" style="font-size:13px">此处准备同一来源报告的第二版；逐图报告 v3 的发布由负责人处理，生成器未核验其线上发布状态。</p></section>
<section class="panel"><h2>来源范围与尚待迁移项</h2><p>{s['uiPackages']} 个 UI 包共有 {s['uiCssInputs']} 个 CSS 输入：{s['uiCssRetainedInputs']} 已绑定保留输入、{s['uiCssPendingInputs']} 尚未保留。另列 {s['supportStylePackages']} 个支持样式包 / {s['supportCssInputs']} 个 CSS 输入。两份新增行为 JSON 使发行保留文件达到 85，未改变 CSS 保留数量。</p><ul>{limits}</ul><p style="margin-top:12px">现有规则另记录 {debt.get('platform-control',0)} 处原生控件调用和 {debt.get('duplicate-button',0)} 处已知按钮重复使用。</p><details><summary>查看 {len(data['policy']['families'])} 个家族的当前迁移说明</summary>{families}</details></section>
<section class="panel"><h2>查找来源包与 CSS 输入</h2><p class="muted">按包名、路径与输入保留状态筛选；无独立 CSS 的包保留结构与委托分类。</p><div class="filters"><label>来源范围<select name="scope"><option value="">全部来源（66）</option><option value="ui">UI 包（57）</option><option value="support">支持样式（9）</option></select></label><label>指定包<select name="package"><option value="">全部包</option>{options}</select></label><label>CSS 保留状态<select name="retention"><option value="">全部状态</option><option value="pending">有尚未保留输入</option><option value="retained">有已保留输入</option><option value="no-css">没有独立 CSS</option></select></label><label>搜索包名或 CSS 路径<input type="search" name="search" placeholder="例如 StatsPills.module.css" autocomplete="off" spellcheck="false"></label></div><div class="filter-footer"><p id="shown-count" role="status" aria-live="polite"></p><button type="button" id="reset">重置筛选</button></div></section>
<section id="ui-section" class="package-section"><h2>UI 来源包</h2><p class="section-intro">保留输入不代表整包已实现。所有路径与哈希来自同一固定来源。</p>{packages(ui)}</section><section id="support-section" class="package-section"><h2>支持样式包</h2><p class="section-intro">包含所选依赖闭包之外的可选实验来源，不由此声称支持其功能。</p>{packages(support)}</section><p id="empty" class="empty" hidden>没有匹配的来源包。</p>
<section class="panel"><h2>可复核的输入身份</h2><div class="facts"><div class="fact-row"><strong>最终提交 / tree</strong><code>{data['head']}<br>{data['tree']}</code></div><div class="fact-row"><strong>原版来源 / 发行版本</strong><code>{SOURCE} / 0.2.1-rc.2</code></div><div class="fact-row"><strong>运行时变更</strong><span>{len(data['runtimeChangedPaths'])} 个应用、功能或共享包源/测试文件改变；本轮含实际组件修正。</span></div><div class="fact-row"><strong>完整证据清单</strong><code>{data['stageManifestSha256']}</code></div></div><details><summary>展开全部生成输入哈希</summary>{hashes}</details></section>
<footer>本页使用合成测试数据，不包含真实用户截图、凭据或应用请求日志。生成器仅准备待发布文件，不执行发布、部署或版本发行。</footer></main><script>{historical.JS}</script></body></html>'''


def preview_script(head):
    code = historical.PREVIEW
    marker = 'await page.screenshot({path:path.join(out,`preview-${width}-overview.png`)});'
    require(code.count(marker) == 1, 'historical preview helper changed; review adaptation')
    extra = f'''if(await page.locator('main').getAttribute('data-head')!=={json.dumps(head)})throw Error('Report head differs');
if(await page.locator('[data-metric=legacy]').textContent()!=='895'||await page.locator('[data-metric=recipes]').textContent()!=='30')throw Error('Current debt/recipe labels differ');
if(await page.locator('#visual-evidence-link').getAttribute('href')!=={json.dumps(VISUAL_URL)})throw Error('Visual evidence link differs');
await page.locator('[name=retention]').selectOption('no-css');if(await visible()!==9)throw Error('Delegated/CSS-free filter failed');await page.locator('#reset').click();
'''
    return code.replace(marker, extra + marker)


def readiness(repo, head, stage):
    needed = [repo / '.local/header-shadows-final-full.json', repo / '.local/preflight/release-inputs.json',
              stage / 'files.json', stage / 'receipt.json', stage / 'preflight.json', stage / 'release-inputs.json', STATE, COMMENTS]
    missing = [str(path.relative_to(ROOT)) for path in needed if not path.is_file()]
    return {'head': head, 'missing': missing, 'readyForValidation': not missing, 'payloadWritten': False}


def self_test():
    tree, head = 'a' * 40, 'b' * 40
    full = {'headTree': tree, 'fast': False, 'results': {k: {'state': 'ok'} for k in CHECKS}}
    validate_full(full, tree)
    results = []
    for label, mutate in [('skipped-required-check', lambda d: d['results']['parity'].update(state='skipped')),
                          ('wrong-final-tree', lambda d: d.update(headTree='c' * 40))]:
        changed = copy.deepcopy(full)
        mutate(changed)
        try:
            validate_full(changed, tree)
        except ValueError:
            results.append({'control': label, 'rejected': True})
        else:
            raise AssertionError(label)
    receipt = {'schema': 'header-shadows-evidence/1', 'head': head, 'runtimeHead': head,
               'headTree': tree, 'runtimeTree': tree, 'base': BASE, 'referenceCommit': SOURCE,
               'allowedPostRuntimeChanges': [], 'fullChecks': 13, 'releasePackages': 13, 'releaseFiles': 85,
               'sourceCoverage': {}, 'legacyDebt': {}, 'modelSeatSemanticBoundary': True,
               'androidScenes': 23, 'androidChecks': 54, 'headerPairs': 16,
               'headerPriorFlutterPreserved': 16, 'preservedProviderImages': 192,
               'builds': [{'name': name} for name in ('android-fixture.apk', 'android-normal.apk',
                                                    'linux-fixture/dsh_flutter', 'linux-normal/dsh_flutter')],
               'gpu': {'menu': {'assertions': 84, 'cases': [{'assertions': 42}] * 2},
                       'header': {'assertions': 72, 'cases': [{'assertions': 18}] * 4}},
               'menuSourceProof': {'sourceCommit': SOURCE, 'caseCount': 2,
                                   'correctOneRowChangedPixels': [0, 0], 'actualTwoRowChangedPixels': [880, 880],
                                   'historicalNativeIsAcceptance': False},
               'releaseOrDeployment': False, 'limitations': ['Unfinished component states'],
               'visual': {'allCaptures': {'compared': 108}, 'cases': [{}] * 108},
               'scoreHistory': {'previous': {'compared': 108}}}
    validate_stage(receipt, head, tree, {}, {})
    for label, mutate in [
        ('historical-runtime-is-not-acceptance', lambda d: d.update(runtimeHead='c' * 40)),
        ('post-runtime-carryover', lambda d: d.update(allowedPostRuntimeChanges=['changed.dart'])),
        ('wrong-Android-scene-count', lambda d: d.update(androidScenes=24)),
        ('missing-model-boundary', lambda d: d.update(modelSeatSemanticBoundary=False)),
        ('incomplete-release-outputs', lambda d: d.update(releaseFiles=83)),
        ('missing-GPU-assertion', lambda d: d['gpu']['header'].update(assertions=71)),
        ('incomplete-source-comparison', lambda d: d['visual']['allCaptures'].update(compared=107)),
        ('failed-source-positive-control', lambda d: d['menuSourceProof'].update(correctOneRowChangedPixels=[1, 0])),
    ]:
        changed = copy.deepcopy(receipt)
        mutate(changed)
        try:
            validate_stage(changed, head, tree, {}, {})
        except ValueError:
            results.append({'control': label, 'rejected': True})
        else:
            raise AssertionError(label)
    with tempfile.TemporaryDirectory(prefix='.source-report-guards-', dir=ROOT / 'scratch') as temporary:
        stage = Path(temporary)
        sample = b'public source input\n'
        (stage / 'sample.txt').write_bytes(sample)
        row = {'path': 'sample.txt', 'sha256': digest(sample), 'bytes': len(sample)}
        def manifest(rows):
            (stage / 'files.json').write_text(json.dumps(rows))
            return Inputs(ROOT, head, ROOT)
        validate_manifest(manifest([row]), stage)
        for label, rows in [('duplicate-evidence-path', [row, row]),
                            ('corrupt-evidence-hash', [{**row, 'sha256': '0' * 64}]),
                            ('unsafe-evidence-path', [{**row, 'path': '../sample.txt'}])]:
            try:
                validate_manifest(manifest(rows), stage)
            except ValueError:
                results.append({'control': label, 'rejected': True})
            else:
                raise AssertionError(label)
    safe_text("import '.[home-path].js'")
    for label, text in [('private-path', '/home/' + 'example/private-file'), ('credential-signature', 'Bearer ' + 'x' * 24)]:
        try:
            safe_text(text)
        except ValueError:
            results.append({'control': label, 'rejected': True})
        else:
            raise AssertionError(label)
    print(json.dumps({'selfTest': 'passed', 'negativeControls': results}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--head', help='exact forty-character final candidate SHA')
    parser.add_argument('--repo', type=Path, default=DEFAULT_REPO)
    parser.add_argument('--stage', type=Path, default=DEFAULT_STAGE)
    parser.add_argument('--src', type=Path, default=Path(os.environ.get('DSH_SRC', ROOT / 'dsh-flutter/.local/dsh-src')))
    parser.add_argument('--out', type=Path, default=DEFAULT_OUT)
    parser.add_argument('--preview', action='store_true', help='required before an unsent publish.json may be written')
    parser.add_argument('--check-ready', action='store_true', help='list absent final inputs; write nothing')
    parser.add_argument('--self-test', action='store_true', help='run report guard negative controls; write nothing')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    require(args.head is not None and re.fullmatch('[0-9a-f]{40}', args.head), '--head must be the exact final SHA')
    repo, stage, out, source = args.repo.resolve(), args.stage.resolve(), args.out.resolve(), args.src.resolve()
    pending = readiness(repo, args.head, stage)
    if args.check_ready:
        print(json.dumps(pending))
        return
    require(pending['readyForValidation'], 'final report inputs incomplete: ' + ', '.join(pending['missing']))
    require(out.is_relative_to(ROOT / 'scratch') and not out.exists(), 'fresh owned scratch output required')
    inputs, data = collect(repo, args.head, stage, source)
    rows = [inputs.records[k] for k in sorted(inputs.records)]
    document = safe_text(render(data, rows))
    require(document.count('<article class="package"') == 66 and document.count('<li class="css-row"') == 219,
            'source package/CSS records omitted from report')
    require(not re.search(r'<(?:iframe|link|base|form|img)\b|\b(?:download|onclick)=|navigator\.clipboard|fetch\(', document, re.I),
            'unexpected report resource/action')
    links = re.findall(r'<a\b[^>]*\bhref="([^"]+)"', document)
    require(links == [VISUAL_URL] and len(document.encode()) < 10 * 1024 * 1024, 'unexpected report link/size')
    artifact = data['artifact']
    receipt = {'head': args.head, 'tree': data['tree'], 'base': BASE, 'sourceCommit': SOURCE,
               'artifact': artifact, 'visualArtifact': {'url': VISUAL_URL, 'publicationVerified': False},
               'checksPassed': 13, 'releasePackagesVerified': 13, 'releaseFilesVerified': 85,
               'sourceCoverage': data['summary'], 'legacyDebt': data['counts'], 'legacyBudget': data['budget'],
               'headerRealMetricReduction': 4, 'recipeClasses': 30, 'previousRecipeClassesUnchanged': 29,
               'runtimeChangedPaths': data['runtimeChangedPaths'], 'runtimeEvidence': data['stage'],
               'evidenceFilesVerified': data['stageFiles'], 'evidenceManifestSha256': data['stageManifestSha256'],
               'htmlBytes': len(document.encode()), 'htmlSha256': digest(document.encode()), 'inputHashes': rows,
               'previewPassed': False, 'payloadWritten': False, 'published': False}
    payload = {'artifact': artifact['artifact'], 'base': artifact['base'], 'seen': artifact['seen'],
               'entry': 'index.html', 'title': TITLE, 'icon': 'report',
               'description': 'Header 四处实际手写数值已移除；现有扫描器仍记录895处匹配，173个UI CSS输入尚未保留。新增规范Header、来源阴影转换、模型原生按钮边界和最终运行证据；来源保留不代表组件与状态验收完成。',
               'files': {'index.html': {'content': document}}}
    inputs.recheck()
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.header-source-report-', dir=out.parent) as temporary:
        prepared = Path(temporary) / out.name
        prepared.mkdir()
        (prepared / 'index.html').write_text(document)
        (prepared / 'preview.cjs').write_text(preview_script(args.head))
        try:
            if args.preview:
                result = subprocess.run([str(ROOT / 'toolchains/node/bin/node'), str(prepared / 'preview.cjs'), str(prepared), str(ROOT)],
                                        capture_output=True, text=True, timeout=120)
                require(result.returncode == 0, 'report preview failed: ' + result.stderr)
                preview = json.loads(result.stdout)
                require({row['width'] for row in preview} == {300, 1280}
                        and all(not row['errors'] and not row['unexpectedRequests'] for row in preview), 'incomplete preview')
                receipt['previewPassed'], receipt['preview'] = True, preview
                receipt['previewFiles'] = [{'path': p.name, 'sha256': digest(p.read_bytes())}
                                           for p in sorted(prepared.glob('preview-*.*'))]
                receipt['previewFiles'].append({'path': 'preview.json', 'sha256': digest((prepared / 'preview.json').read_bytes())})
            inputs.recheck()
            require(git(repo, 'rev-parse', 'HEAD') == args.head and not git(repo, 'status', '--porcelain'),
                    'candidate changed while preparing report')
            if receipt['previewPassed']:
                (prepared / 'publish.json').write_text(safe_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n'))
                receipt['payloadWritten'] = True
        finally:
            (prepared / 'build-receipt.json').write_text(safe_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n'))
            require(not out.exists(), 'report output appeared during generation')
            prepared.rename(out)
    print(json.dumps({k: receipt[k] for k in ('head', 'tree', 'htmlBytes', 'htmlSha256', 'previewPassed', 'payloadWritten', 'published')}))


if __name__ == '__main__':
    main()
