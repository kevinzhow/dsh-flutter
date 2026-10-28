#!/usr/bin/env python3
"""Build and optionally preview a source-coverage Artifact; never publish it."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import html
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REPO = ROOT / 'scratch/whalee-design-system-contract'
DEFAULT_OUT = ROOT / 'scratch/design-system-source-artifact'
HEAD = '9e885323416526664a510bf77d84b7b049aaa450'
BASE = 'ac8d066aa10802679e5e7c3c1d897c1bea613981'
SOURCE = '687f282e8625c6b8d11ff58211a90524be2e4317'
CHECKS = {'check-deps', 'tool-tests', 'codegen', 'theme-pack', 'design-system',
          'i18n', 'icons', 'vector', 'parity', 'capability', 'format', 'analyze', 'tests'}
TITLE = 'Whalee 设计系统来源覆盖与手写样式清理进度'
SENSITIVE = re.compile(
    r'-----BEGIN [^-\n]*PRIVATE KEY-----|'
    r'\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|'
    r'github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})\b|'
    r'\bBearer\s+[A-Za-z0-9._=-]{12,}|'
    r'(?:password|access_token|refresh_token|client_secret)\s*[=:]\s*["\'][^"\'\s]{16,}', re.I)
HOME_PATH = re.compile(r'/(?:home|Users)/[^\s"\'<>]+|/root(?:/[^\s"\'<>]*)?')


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def safe_text(value):
    require(not SENSITIVE.search(value) and not HOME_PATH.search(value),
            'private or credential-shaped text in report output')
    return value


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate input JSON key: ' + key)
        result[key] = value
    return result


def git(repo, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=repo).decode().strip()


class Inputs:
    def __init__(self, repo):
        self.repo, self.records, self.paths = repo, {}, {}

    def read(self, path, role, committed=False):
        require(path.is_file() and not path.is_symlink(), 'missing/linked report input: ' + path.name)
        raw = path.read_bytes()
        if path.is_relative_to(self.repo):
            relative = path.relative_to(self.repo).as_posix()
            name = 'repo/' + relative
            if committed:
                blob = subprocess.check_output(['git', 'show', HEAD + ':' + relative], cwd=self.repo)
                require(blob == raw, 'report input differs from exact final Git blob: ' + relative)
        else:
            require(path.is_relative_to(ROOT), 'report input escaped the workspace')
            name = 'workspace/' + path.relative_to(ROOT).as_posix()
        row = {'path': name, 'sha256': digest(raw), 'bytes': len(raw), 'role': role}
        require(name not in self.records or self.records[name]['sha256'] == row['sha256'],
                'report input changed while reading')
        self.records[name], self.paths[name] = row, path
        return raw

    def json(self, path, role, committed=False):
        return json.loads(self.read(path, role, committed), object_pairs_hook=unique_object)

    def module(self, relative, name):
        path = self.repo / relative
        self.read(path, 'verification code', committed=True)
        spec = importlib.util.spec_from_file_location('source_report_' + name, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def recheck(self):
        for name, path in self.paths.items():
            require(digest(path.read_bytes()) == self.records[name]['sha256'],
                    'report input changed during generation: ' + name)


def collect(repo):
    require(git(repo, 'rev-parse', 'HEAD') == HEAD and not git(repo, 'status', '--porcelain'),
            'report requires the exact clean final candidate')
    inputs = Inputs(repo)
    inputs.read(Path(__file__).resolve(), 'report builder')
    full = inputs.json(repo / '.local/source-contract-full.json', 'final required checks')
    tree = git(repo, 'rev-parse', 'HEAD^{tree}')
    require(full.get('headTree') == tree and full.get('fast') is False
            and set(full.get('results', {})) == CHECKS
            and all(row.get('state') == 'ok' for row in full['results'].values()),
            'all thirteen exact-final-tree checks must be ok; skips do not count as passed')
    ledger = inputs.json(repo / 'tool/design-system/source-inventory.generated.json', 'source input ledger', True)
    lock = inputs.json(repo / 'tool/design-system/sources.lock.json', 'published source lock', True)
    families = inputs.json(repo / 'tool/design-system/families.json', 'legacy debt policy', True)
    release = inputs.json(repo / '.local/preflight/release-inputs.json', 'completed release reconstruction')
    inventory = inputs.module('tool/design-system/source_inventory.py', 'inventory')
    guard = inputs.module('tool/design-system/check.py', 'guard')
    inputs.read(repo / 'tool/design-system/published.py', 'published decoder', True)
    inputs.read(repo / 'tool/design-system/verify_release_inputs.py', 'archive verifier', True)
    inputs.read(repo / 'tool/design-system/generate.py', 'recipe generator', True)
    inputs.read(repo / 'tool/preflight', 'preflight wiring', True)
    inventory.check_snapshots(ledger, repo)
    require(ledger['referenceCommit'] == lock['referenceCommit'] == SOURCE, 'wrong upstream source pin')
    require(release.get('allPassed') is True and release.get('verificationInputsUnchanged') is True
            and release.get('referenceCommit') == SOURCE, 'completed release-input verification required')
    bindings = {
        'sourceLockSha256': 'tool/design-system/sources.lock.json',
        'sourceInventorySha256': 'tool/design-system/source-inventory.generated.json',
        'verificationToolSha256': 'tool/design-system/verify_release_inputs.py',
        'publishedVerifierSha256': 'tool/design-system/published.py',
        'inventoryVerifierSha256': 'tool/design-system/source_inventory.py',
    }
    for field, relative in bindings.items():
        require(release.get(field) == inputs.records['repo/' + relative]['sha256'],
                'release receipt is stale: ' + field)
    packages = {p['name']: p for p in lock['packages']}
    verified = release.get('packages', [])
    require(len(verified) == len(packages) == release.get('packageCount') == 13
            and {p['name'] for p in verified} == set(packages), 'release package coverage differs')
    for row in verified:
        package = packages[row['name']]
        require(row.get('verified') is True and row.get('archiveUnchanged') is True
                and row.get('snapshotFiles') == len(package['files'])
                and all(row.get(field) == package[field] for field in ('version', 'integrity', 'tarball')),
                'incomplete archive reconstruction: ' + row['name'])
        for name, sha in package['files'].items():
            path = repo / 'tool/design-system/upstream' / package['snapshotFolder'] / name
            require(digest(inputs.read(path, 'retained released input', True)) == sha, 'retained source hash differs')
    require(sum(p['snapshotFiles'] for p in verified) == release.get('verifiedSnapshotFiles') == 83,
            'all 83 retained inputs must have completed reconstruction')
    guard.validate_contract(families)
    counts, failures = guard.inspect(repo, families)
    require(not failures, 'current guard rejected source: ' + '; '.join(failures))
    actual, budget = Counter(), Counter()
    for row in counts.values():
        actual.update(row)
    for row in families['baseline'].values():
        budget.update(row)
    for path in guard.sources(repo):
        inputs.read(path, 'source scanned for legacy debt', True)
    require(actual['manual-metric'] == budget['manual-metric'] == 899,
            'reported legacy metric count/budget differs from this final candidate')
    runtime_diff = git(repo, 'diff', '--name-only', BASE, HEAD, '--', 'apps', 'features', 'packages')
    require(not runtime_diff, 'report assumes unchanged product runtime')
    pr = inputs.read(ROOT / 'notes/source-contract-pr-created.txt', 'pull request URL').decode().strip()
    require(pr == 'https://github.com/kevinzhow/dsh-flutter/pull/59', 'unexpected pull request identity')
    summary = inventory.summary(ledger['packages'])
    require(summary == ledger['summary'] and summary['uiPackages'] == 57
            and summary['uiCssInputs'] == 209 and summary['uiCssPendingInputs'] == 173
            and summary['supportStylePackages'] == 9, 'source inventory cohort differs')
    data = {'head': HEAD, 'tree': tree, 'base': BASE, 'source': SOURCE, 'pr': pr,
            'full': full, 'release': release, 'ledger': ledger, 'families': families,
            'counts': dict(actual), 'budget': dict(budget), 'debtFiles': counts,
            'summary': summary, 'runtimeChangedPaths': [], 'runtimeDiffSha256': digest(runtime_diff.encode())}
    return inputs, data


CSS = '''
:root{color-scheme:light;font:16px/1.6 system-ui,-apple-system,"Segoe UI",sans-serif;color:#202927;background:#f4f6f3}*{box-sizing:border-box}body{margin:0}main{max-width:1160px;margin:auto;padding:42px 24px 72px}h1{font-size:clamp(29px,4vw,44px);line-height:1.22;letter-spacing:-.035em;margin:12px 0 18px}h2{font-size:22px;line-height:1.4;margin:0 0 12px}h3{font-size:17px;line-height:1.45;margin:0 0 8px}.eyebrow{font-size:12px;letter-spacing:.12em;color:#52685c;font-weight:750}.lead{max-width:860px;font-size:18px}.muted{color:#5b6961}.status{display:inline-block;border-radius:7px;background:#fff0d7;color:#74501a;padding:5px 10px;font-size:13px;font-weight:650}.metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin:25px 0}.metric,.panel,.package{background:white;border:1px solid #dce4dc;border-radius:14px}.metric{padding:18px}.metric strong{display:block;font-size:29px;line-height:1.3;font-variant-numeric:tabular-nums}.metric span{font-size:13px;color:#5b6961}.panel{padding:24px;margin-top:22px}p{margin:0 0 13px}p:last-child{margin-bottom:0}ul{margin:0;padding-left:22px}li+li{margin-top:8px}code{font:12px/1.6 ui-monospace,SFMono-Regular,Consolas,monospace;overflow-wrap:anywhere;word-break:break-word}details{margin-top:12px}summary{min-height:44px;padding:9px 0;cursor:pointer;font-size:14px;font-weight:650}summary:focus-visible,select:focus-visible,input:focus-visible,button:focus-visible{outline:3px solid #a9cdbb;outline-offset:3px}.filters{display:grid;grid-template-columns:1fr 1.5fr 1fr 1.5fr;gap:12px;margin:18px 0 12px}label{display:block;min-width:0;font-size:13px;font-weight:650}select,input,button{font:inherit;font-size:16px;min-height:44px;min-width:0;border:1px solid #aabbb0;border-radius:8px;color:#202927;background:#fff;padding:8px 10px}select,input{display:block;width:100%;margin-top:6px}button{cursor:pointer;padding:8px 15px}.filter-footer{display:flex;align-items:center;justify-content:space-between;gap:12px}.filter-footer p{margin:0;font-size:14px}.package-section{margin-top:28px}.section-intro{font-size:14px;margin-bottom:14px}.package{padding:20px;margin-top:12px;min-width:0}.package-header{display:flex;justify-content:space-between;gap:12px}.package-header h3{min-width:0;overflow-wrap:anywhere}.tag{flex:none;font-size:12px;align-self:start;border-radius:6px;background:#edf2ee;color:#385344;padding:3px 7px}.package-meta{display:flex;flex-wrap:wrap;gap:5px 18px;font-size:13px;color:#5b6961}.retention{font-size:14px;margin-top:9px}.css-list{list-style:none;padding:0;margin:8px 0 0}.css-row{border-top:1px solid #e4e9e4;padding:12px 0}.css-row p{font-size:13px;margin:4px 0 0}.pending{color:#8a5b14}.retained{color:#285d42}.hash{font-size:11px;color:#69756c}.path{display:block}.facts{display:grid;gap:10px;font-size:14px}.fact-row{padding-top:9px;border-top:1px solid #e4e9e4}.fact-row strong{display:block;font-size:13px}.checks{display:flex;flex-wrap:wrap;gap:7px}.check{background:#edf2ee;color:#31543f;padding:5px 9px;border-radius:5px;font-size:12px}.scope-note{padding-left:14px;border-left:3px solid #b5c6b7;margin-top:15px}.empty{padding:30px 10px;color:#69756c}.family{margin-top:14px;padding-top:12px;border-top:1px solid #e4e9e4;font-size:13px}.family p{font-size:13px}.input-hash{padding:10px 0;border-top:1px solid #e4e9e4}footer{font-size:12px;color:#69756c;margin-top:28px}[hidden]{display:none!important}@media(max-width:800px){.filters{grid-template-columns:repeat(2,minmax(0,1fr))}.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:450px){main{padding:28px 12px 48px}.panel,.package{padding:18px 15px}.lead{font-size:16px}.filters{grid-template-columns:minmax(0,1fr)}.metrics{gap:9px}.metric{padding:14px}.metric strong{font-size:25px}.package-header{display:block}.tag{display:inline-block;margin-bottom:6px}.filter-footer{align-items:flex-start;flex-direction:column}.filter-footer button{width:100%}}
'''

JS = '''
(() => {
  const scope=document.querySelector('[name=scope]'), pkg=document.querySelector('[name=package]');
  const retention=document.querySelector('[name=retention]'), search=document.querySelector('[name=search]');
  const cards=[...document.querySelectorAll('article.package')];
  function apply(){
    const query=search.value.trim().toLocaleLowerCase();let ui=0,support=0;
    for(const card of cards){
      const state=retention.value;
      const visible=(!scope.value||card.dataset.scope===scope.value)&&(!pkg.value||card.dataset.name===pkg.value)
        &&(!query||card.dataset.search.includes(query))
        &&(!state||(state==='pending'&&+card.dataset.pending>0)||(state==='retained'&&+card.dataset.retained>0)||(state==='no-css'&&+card.dataset.css===0));
      card.hidden=!visible;if(visible){if(card.dataset.scope==='ui')ui++;else support++;}
      if(visible&&(query||pkg.value)){const detail=card.querySelector('details');if(detail)detail.open=true;}
    }
    document.getElementById('ui-section').hidden=ui===0;document.getElementById('support-section').hidden=support===0;
    document.getElementById('shown-count').textContent=`当前显示 ${ui} / 57 个 UI 包，${support} / 9 个支持样式包`;
    document.getElementById('empty').hidden=ui+support>0;
  }
  [scope,pkg,retention].forEach(c=>c.addEventListener('change',apply));search.addEventListener('input',apply);
  document.getElementById('reset').addEventListener('click',()=>{scope.value=pkg.value=retention.value=search.value='';cards.forEach(c=>{const d=c.querySelector('details');if(d)d.open=false;});apply();});
  apply();
})();
'''


def render_package(package):
    esc = html.escape
    css = package['css']
    retained = sum(c['retention'] == 'retained-input' for c in css)
    pending = len(css) - retained
    scope = 'ui' if package['scope'] == 'ui-package' else 'support'
    name = package['name']
    search = ' '.join([name, *(c['path'] for c in css)]).lower()
    reach = {'runtime': '运行时依赖范围', 'build-only': '构建依赖范围',
             'outside-selected-closure': '所选依赖闭包之外，仍纳入清单'}[package['reachability']]
    lines = []
    for item in css:
        state = 'retained' if item['retention'] == 'retained-input' else 'pending'
        label = '已保留的来源输入' if state == 'retained' else '尚未保留'
        bound = ''.join('<p class="muted">对应保留文件：<code>' + esc(path) + '</code></p>'
                        for path in item['retainedInputs'])
        lines.append(f'<li class="css-row" data-state="{state}"><code class="path">{esc(item["path"])}</code>'
                     f'<p class="{state}">{label}</p><code class="hash">SHA-256 {item["sha256"]}</code>{bound}</li>')
    if css:
        details = (f'<p class="retention">{len(css)} 个 CSS 输入：<span class="retained">{retained} 已保留</span> · '
                   f'<span class="pending">{pending} 尚未保留</span></p><details><summary>展开 {len(css)} 个 CSS 输入</summary>'
                   '<ul class="css-list">' + ''.join(lines) + '</ul></details>')
    else:
        classification = package['noCssClassification']
        evidence = ''.join(f'<p><code>{esc(p["path"])}</code><br><code class="hash">SHA-256 {p["sha256"]}</code></p>'
                           for p in classification['sourceEvidence'])
        details = ('<p class="retention">没有独立 CSS 输入，已记录结构或委托关系；内联样式与组件实现仍需单独核对。</p>'
                   '<details><summary>查看无 CSS 分类证据</summary><p class="muted">'
                   + esc(classification['explanation']) + '</p>' + evidence + '</details>')
    snapshot = package['snapshot']
    info = (f'此包保留 {len(snapshot["files"])} 个发行文件，仅代表输入保留。' if snapshot else '此包尚未纳入发行文件保留子集。')
    return (f'<article class="package" data-scope="{scope}" data-name="{esc(name)}" data-search="{esc(search)}" '
            f'data-retained="{retained}" data-pending="{pending}" data-css="{len(css)}">'
            f'<div class="package-header"><h3>{esc(name)}</h3><span class="tag">{"UI 来源包" if scope == "ui" else "支持样式"}</span></div>'
            f'<div class="package-meta"><span>版本 {esc(package["version"])}</span><span>{reach}</span></div>'
            + details + '<p class="muted" style="font-size:13px;margin-top:10px">' + info + '</p></article>')


def render(data, input_rows):
    esc = html.escape
    summary, counts = data['summary'], data['counts']
    ui = [p for p in data['ledger']['packages'] if p['scope'] == 'ui-package']
    support = [p for p in data['ledger']['packages'] if p['scope'] == 'support-styles']
    options = ''.join(f'<option value="{esc(p["name"])}">{esc(p["name"])}</option>' for p in ui + support)
    check_names = ''.join('<span class="check">' + esc(k) + ' ✓</span>' for k in sorted(CHECKS))
    families = ''.join('<div class="family"><strong>' + esc(f['name']) + '</strong><p class="muted">'
                       + esc(f['migrationStatus']) + '</p></div>' for f in data['families']['families'])
    inputs = ''.join('<div class="input-hash"><code class="path">' + esc(row['path'])
                     + '</code><code>SHA-256 ' + row['sha256'] + '</code></div>' for row in input_rows)
    return f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; connect-src 'none'; font-src 'none'"><title>{TITLE}</title><style>{CSS}</style></head><body><main>
<header><div class="eyebrow">WHALEE · 设计系统来源核对 · 2026-10-28</div><h1>仍在清除手写样式</h1><p class="lead">现有规则仍记录 <strong>{counts['manual-metric']} 处既有数值匹配</strong>；{summary['uiCssPendingInputs']} 个 UI CSS 输入尚未保留。本轮建立了发行归档、源码清单和防退化检查，后续仍要逐项迁移组件与真实入口。</p><span class="status">来源保留 ≠ 组件实现完成</span></header>
<div class="metrics"><div class="metric"><strong>{counts['manual-metric']}</strong><span>现有规则检测到的数值匹配</span></div><div class="metric"><strong>{summary['uiCssPendingInputs']}</strong><span>尚未保留的 UI CSS 输入</span></div><div class="metric"><strong>13 / 83</strong><span>已复核的发行包 / 保留文件</span></div><div class="metric"><strong>13 / 13</strong><span>最终提交必需检查通过</span></div></div>
<section class="panel"><h2>已核验的范围</h2><p>已将 13 个锁定发行包的 83 个保留文件与真实 npm 归档重新比对；缺少映射、多报文件、输入被改写或类型错误都会使对应检查失败。源码清单覆盖 {summary['uiPackages']} 个 UI 包及另列的 {summary['supportStylePackages']} 个支持样式包。</p><p>UI 包共有 {summary['uiCssInputs']} 个 CSS 输入，其中 {summary['uiCssRetainedInputs']} 个已绑定保留文件，{summary['uiCssPendingInputs']} 个仍待保留。支持样式另有 {summary['supportCssInputs']} 个 CSS 输入。</p><p class="scope-note">保留只说明来源输入被记录和核对，组件实现、真实入口以及适用状态仍需逐项验收。总体视觉目标仍未完成。</p><div class="checks">{check_names}</div><p class="muted" style="font-size:13px;margin-top:12px">检查记录：{esc(data['full']['when'])}。本轮产品运行时代码改动为 0 个文件。</p></section>
<section class="panel"><h2>清理仍在继续</h2><ul><li>899 处既有数值匹配仍然保留；本轮只删除了 6 个未使用的额度，没有宣称已清除这些样式。扫描器尚不能覆盖所有 Dart 样式表达式。</li><li>现有检查另记录 {counts.get('platform-control', 0)} 处原生控件调用与 {counts.get('duplicate-button', 0)} 处已知按钮重复使用；后续需要对应来源和迁移。</li><li>清单中有 5 个仅完成登记、仍待迁移的家族：卡片、列表行、空状态、Toast 与横幅。其余家族也保留各自未完成的变体和交互。</li><li>没有源码的 CI 只能核对发行归档和已记录输入，不能独立证明上游源码范围完整；内联样式、SVG 和所有状态的视觉验收仍需继续。</li></ul><details><summary>查看 16 个家族的当前迁移说明</summary>{families}</details></section>
<section class="panel"><h2>查找来源包与 CSS 输入</h2><p class="muted">按包名、路径或保留状态筛选。UI 包与支持样式分开展示；展开后可核对每个输入的路径、哈希和保留映射。</p><div class="filters"><label>来源范围<select name="scope"><option value="">全部来源（66）</option><option value="ui">UI 包（57）</option><option value="support">支持样式（9）</option></select></label><label>指定包<select name="package"><option value="">全部包</option>{options}</select></label><label>CSS 保留状态<select name="retention"><option value="">全部状态</option><option value="pending">有尚未保留输入</option><option value="retained">有已保留输入</option><option value="no-css">没有独立 CSS</option></select></label><label>搜索包名或 CSS 路径<input type="search" name="search" placeholder="例如 StatsPills.module.css" autocomplete="off" spellcheck="false"></label></div><div class="filter-footer"><p id="shown-count" role="status" aria-live="polite">当前显示 57 / 57 个 UI 包，9 / 9 个支持样式包</p><button type="button" id="reset">重置筛选</button></div></section>
<section id="ui-section" class="package-section"><h2>UI 来源包 · 57</h2><p class="section-intro muted">209 个 CSS 输入中，36 个已保留、173 个尚未保留；无独立 CSS 的包另附分类证据。</p>{''.join(render_package(p) for p in ui)}</section>
<section id="support-section" class="package-section"><h2>支持样式包 · 9</h2><p class="section-intro muted">这部分含 10 个 CSS 输入，独立于上面的 UI 包统计；未计作组件迁移完成。</p>{''.join(render_package(p) for p in support)}</section><p id="empty" class="empty" hidden>没有匹配的来源包，请调整筛选条件。</p>
<section class="panel"><h2>版本与核验依据</h2><div class="facts"><div><strong>审查记录</strong><br><code>{esc(data['pr'])}</code></div><div class="fact-row"><strong>最终提交</strong><code>{data['head']}</code><br><strong>提交树</strong><code>{data['tree']}</code></div><div class="fact-row"><strong>上游 DSH 来源</strong><code>{data['source']}</code><br>锁定发行版本：0.2.1-rc.2</div><div class="fact-row"><strong>比较基线</strong><code>{data['base']}</code><br>apps / features / packages：没有运行时代码差异。</div></div><details><summary>查看所有报告输入的 SHA-256（{len(input_rows)} 个）</summary><p class="muted">包含原始检查回执、来源清单、锁文件、验证代码、保留文件与实际扫描的源码；每个输入都在生成结束前再次核对。</p>{inputs}</details></section>
<footer>本页为离线来源覆盖报告，无外部资源、真实用户截图、凭据或请求日志。报告生成不执行发布、部署或版本发行。</footer></main><script>{JS}</script></body></html>'''


PREVIEW = r'''
const fs=require('node:fs'),http=require('node:http'),path=require('node:path');
const out=process.argv[2],workspace=process.argv[3];
const {chromium}=require(path.join(workspace,'dsh-flutter/.local/parity-web/node_modules/playwright-core'));
const document=fs.readFileSync(path.join(out,'index.html'));
const server=http.createServer((req,res)=>{if(req.url==='/favicon.ico'){res.writeHead(204);res.end();return;}res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});res.end(document);});
(async()=>{await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));let browser;const results=[];
try{browser=await chromium.launch({headless:true,args:['--no-sandbox']});
for(const width of [300,1280]){const page=await browser.newPage({viewport:{width,height:960}});const errors=[],unexpectedRequests=[];
page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(!r.url().startsWith('http://127.0.0.1:'+server.address().port+'/'))unexpectedRequests.push(r.url());});
await page.goto('http://127.0.0.1:'+server.address().port+'/',{waitUntil:'networkidle'});
const visible=()=>page.locator('article.package:not([hidden])').count();
if(await visible()!==66||await page.locator('#ui-section article.package').count()!==57||await page.locator('#support-section article.package').count()!==9)throw Error('Package cohort differs');
if(await page.locator('#ui-section .css-row').count()!==209||await page.locator('#support-section .css-row').count()!==10)throw Error('CSS cohort differs');
await page.screenshot({path:path.join(out,`preview-${width}-overview.png`)});
await page.locator('[name=scope]').selectOption('ui');if(await visible()!==57)throw Error('UI filter failed');
await page.locator('[name=package]').selectOption('@deepseek-ai/dsh-client-ui-primitives');if(await visible()!==1)throw Error('Package filter failed');
await page.locator('[name=retention]').selectOption('pending');if(await visible()!==1)throw Error('Combined retention filter failed');
await page.locator('#reset').click();await page.locator('[name=scope]').selectOption('support');if(await visible()!==9)throw Error('Support filter failed');
await page.locator('#reset').click();await page.locator('[name=search]').fill('STATSPILLS.MODULE.CSS');if(await visible()!==1)throw Error('Case-insensitive path search failed');
const first=page.locator('article.package:not([hidden])');if(await first.getAttribute('data-name')!=='@deepseek-ai/dsh-client-ui-chat')throw Error('Search owner differs');
await first.locator('.css-row').filter({hasText:'StatsPills.module.css'}).scrollIntoViewIfNeeded();await page.screenshot({path:path.join(out,`preview-${width}-filtered.png`)});
const geometry=await page.evaluate(()=>({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,controls:[...document.querySelectorAll('select,input,button,summary')].filter(c=>c.getClientRects().length).map(c=>({tag:c.tagName,height:c.getBoundingClientRect().height,width:c.getBoundingClientRect().width}))}));
if(geometry.scrollWidth>width||geometry.controls.some(c=>c.height<44||c.width<44))throw Error('Overflow or undersized touch control');
await page.locator('[name=search]').fill('no-such-package-coverage-probe');if(await visible()!==0||!await page.locator('#empty').isVisible())throw Error('Empty search failed');
await page.locator('#reset').click();if(await visible()!==66)throw Error('Reset failed');
if(errors.length||unexpectedRequests.length)throw Error(JSON.stringify({errors,unexpectedRequests}));
results.push({width,initial:66,uiPackages:57,supportPackages:9,uiCssInputs:209,supportCssInputs:10,uiFilter:57,packageFilter:1,supportFilter:9,pathSearch:1,emptySearch:0,reset:66,geometry,errors,unexpectedRequests});await page.close();}
fs.writeFileSync(path.join(out,'preview.json'),JSON.stringify(results,null,2)+'\n');process.stdout.write(JSON.stringify(results)+'\n');
}finally{if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}})().catch(e=>{process.stderr.write(e.stack+'\n');process.exitCode=1;});
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=DEFAULT_REPO)
    parser.add_argument('--out', type=Path, default=DEFAULT_OUT)
    parser.add_argument('--preview', action='store_true', help='run the pinned headless Playwright report checks')
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.out.resolve()
    require(out.is_relative_to(ROOT / 'scratch') and not out.exists(),
            'fresh owned scratch output required; preserve any existing report')
    inputs, data = collect(repo)
    input_rows = [inputs.records[k] for k in sorted(inputs.records)]
    document = render(data, input_rows)
    safe_text(document)
    require(not re.search(r'<(?:iframe|a|link|base|form|img)\b|\b(?:href|download|onclick)=|navigator\.clipboard|fetch\(', document, re.I),
            'unexpected external resource, navigation or action in report')
    raw = document.encode()
    require(len(raw) < 10 * 1024 * 1024, 'report exceeds 10 MiB')
    require(document.count('<article class="package"') == 66
            and document.count('<li class="css-row"') == 219, 'report omitted source records')
    receipt = {'head': HEAD, 'tree': data['tree'], 'base': BASE, 'sourceCommit': SOURCE,
               'pr': data['pr'], 'checksPassed': 13, 'releasePackagesVerified': 13,
               'releaseFilesVerified': 83, 'sourceCoverage': data['summary'],
               'legacyDebt': data['counts'], 'legacyBudget': data['budget'],
               'runtimeChangedPaths': [], 'runtimeDiffSha256': data['runtimeDiffSha256'],
               'htmlBytes': len(raw), 'htmlSha256': digest(raw), 'inputHashes': input_rows,
               'previewPassed': False, 'published': False}
    payload = {'artifact': 'whalee-design-system-source-coverage', 'base': None,
               'entry': 'index.html', 'title': TITLE, 'icon': 'report',
               'description': '仍在清除手写样式：899 处既有数值匹配，173 个 UI CSS 输入尚未保留；展示 57 个 UI 包、9 个支持样式包及实际发行归档核验。来源保留不代表组件实现完成。',
               'files': {'index.html': {'content': document}}}
    inputs.recheck()
    require(git(repo, 'rev-parse', 'HEAD') == HEAD and not git(repo, 'status', '--porcelain'),
            'candidate changed while building report')
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.source-report-', dir=out.parent) as temporary:
        stage = Path(temporary) / out.name
        stage.mkdir()
        (stage / 'index.html').write_bytes(raw)
        for name, value in [('publish.json', payload), ('build-receipt.json', receipt)]:
            text = json.dumps(value, ensure_ascii=False, indent=2) + '\n'
            (stage / name).write_text(safe_text(text))
        (stage / 'preview.cjs').write_text(PREVIEW)
        require(not out.exists(), 'report output appeared during generation')
        stage.rename(out)
    if args.preview:
        node = ROOT / 'toolchains/node/bin/node'
        result = subprocess.run([str(node), str(out / 'preview.cjs'), str(out), str(ROOT)],
                                text=True, capture_output=True, timeout=120)
        require(result.returncode == 0, 'report preview failed; outputs preserved: ' + result.stderr)
        preview = json.loads(result.stdout)
        require(len(preview) == 2 and all(not p['errors'] and not p['unexpectedRequests'] for p in preview),
                'report preview receipt is incomplete')
        receipt['previewPassed'] = True
        receipt['preview'] = preview
        receipt['previewFiles'] = [{'path': p.name, 'sha256': digest(p.read_bytes())}
                                   for p in sorted(out.glob('preview-*.*'))]
        receipt['previewFiles'].append({'path': 'preview.json', 'sha256': digest((out / 'preview.json').read_bytes())})
        (out / 'build-receipt.json').write_text(safe_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n'))
    print(json.dumps({key: receipt[key] for key in ('head', 'tree', 'htmlBytes', 'htmlSha256', 'previewPassed', 'published')}))


if __name__ == '__main__':
    main()
