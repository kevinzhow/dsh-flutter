#!/usr/bin/env python3
"""Capability parity table: what the pinned dsh web client can do, and how much of it Whalee has.

The source of truth is docs/capability-parity.json, one hand-reviewed row per upstream item:

  package   every packages/client/ui-* package of the pinned dsh (what the user can do with it)
  remote    every @Remote method a Host service exposes (`<namespace>/<method>`, the wire name)
  slot      every slot name in dsh's generated client slot catalog (`<domain>.<entry>.<hole>`)
  settings  every settings namespace the web client reads or writes through configForms / remote.settings

Each row carries a Whalee status: ported, partial, missing (nothing yet) or na (not applicable, with the reason), and a
platform: phone, desktop or both (where Whalee is meant to offer it; a desktop build replicates dsh's desktop app, so
"phone-first" is not a reason for na).
docs/capability-parity.md is generated from the table (counts per area and status, the missing and partial work by priority).

  capability_parity.py [--write]    regenerate docs/capability-parity.md
  capability_parity.py --check      offline: the table is well formed, every Whalee path exists, the markdown is fresh and the
                                    table was reviewed against the pinned dsh commit; with the dsh checkout also: every ui package,
                                    Remote method, slot and settings namespace of the pin has a row and no row is stale
  capability_parity.py --skeleton   print JSON stubs for the upstream items that have no row yet (status "missing", to be reviewed)

Exit codes: 0 ok, 1 a check failed, 2 the offline checks passed but the dsh checkout is missing (preflight reports a skip).
Stdlib only. Runs from any cwd. The dsh checkout is $DSH_SRC or <repo>/.local/dsh-src (see README).

When the pin moves (docs/upstream-sync.json), `--check` goes red until every new upstream item has a row, every removed one
is dropped and `dsh.commit` in the table is set to the new pin: that is the moment to look at what dsh gained.
"""
from __future__ import annotations

import sys
sys.dont_write_bytecode = True
import argparse
import json
import os
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TABLE = REPO / 'docs' / 'capability-parity.json'
MARKDOWN = REPO / 'docs' / 'capability-parity.md'
SYNC = REPO / 'docs' / 'upstream-sync.json'

KINDS = ('package', 'remote', 'slot', 'settings')
STATUSES = ('ported', 'partial', 'missing', 'na')
AREAS = (
    'sessions-chat',
    'input-commands',
    'tools-approvals',
    'plan-goal-jobs-schedule-workflows',
    'files-preview',
    'settings',
    'plugins-skills',
    'sidebar-browser',
    'misc',
)
AREA_TITLES = {
    'sessions-chat': 'Sessions and chat',
    'input-commands': 'Input and commands',
    'tools-approvals': 'Tools and approvals',
    'plan-goal-jobs-schedule-workflows': 'Plan, goal, jobs, schedule, workflows',
    'files-preview': 'Files and preview',
    'settings': 'Settings',
    'plugins-skills': 'Plugins and skills',
    'sidebar-browser': 'Sidebar and browser',
    'misc': 'Misc',
}
PRIORITIES = ('P1', 'P2', 'P3', 'P4')
PLATFORMS = ('phone', 'desktop', 'both')
ROW_FIELDS = {'id', 'kind', 'area', 'platform', 'dshSource', 'description', 'status', 'whalee', 'notes', 'reason', 'priority'}

# A na reason that only says the item needs a desktop (or that a phone cannot do it) is the reclassification this check prevents.
_PHONE_FIRST = re.compile(r'phone[- ]first|phone user cannot|not reachable from a phone|a phone cannot', re.I)

# Sources that are not part of the product surface: tests, build output, the generated cordis API catalog.
_SKIP_PARTS = ('node_modules', '/tests/', '/lib/')


def dsh_src() -> Path | None:
    p = Path(os.environ.get('DSH_SRC', str(REPO / '.local' / 'dsh-src')))
    return p if (p / 'packages' / 'client').is_dir() else None


# ---------------------------------------------------------------------------------------------- the upstream scanners

def _first_sentence(text: str) -> str:
    text = re.sub(r'\s+', ' ', text).strip()
    m = re.match(r'(.+?[.!?])(?:\s|$)', text)
    return (m.group(1) if m else text)[:300]


def scan_packages(src: Path) -> list[dict]:
    out = []
    for d in sorted((src / 'packages' / 'client').glob('ui-*')):
        pkg = d / 'package.json'
        if not pkg.is_file():
            continue
        desc = json.loads(pkg.read_text()).get('description') or ''
        out.append({'id': 'package:' + d.name, 'kind': 'package', 'dshSource': 'packages/client/' + d.name,
                    'description': _first_sentence(desc)})
    return out


def _is_source(rel: str) -> bool:
    return not (any(part in rel for part in _SKIP_PARTS) or rel.endswith('.d.ts') or '.spec.' in rel)


def scan_remotes(src: Path) -> list[dict]:
    """Every `@Remote` method of a class that extends TypertRemoteService, under its wire namespace and name.

    The namespace is the `namespace` option of the constructor's `super(ctx, key, { namespace })`, else the service key; the
    method name is the decorator's name argument, else the method's own name (what the codegen extractor does for the six
    namespaces Whalee generates)."""
    out = []
    for p in sorted(src.glob('packages/**/src/**/*.ts')):
        rel = p.relative_to(src).as_posix()
        if not _is_source(rel) or rel.startswith('packages/typert/') or rel.endswith('/api-catalog.ts'):
            continue
        text = p.read_text()
        if '@Remote' not in text:
            continue
        classes = [m.start() for m in re.finditer(r'\bclass\s+\w+[^{;]*\bextends\s+TypertRemoteService\b', text)]
        for m in re.finditer(r'@Remote\b(?:\(([^)]*)\))?\s*(?:(?:public|async|override)\s+)*\*?\s*(\w+)', text):
            before = [c for c in classes if c < m.start()]
            if not before:
                continue
            sm = re.search(r"super\(\s*ctx\s*,\s*'(\w+)'(?:\s*,\s*\{\s*namespace:\s*'(\w+)')?", text[before[-1]:])
            if not sm:
                continue
            ns = sm.group(2) or sm.group(1)
            arg = (m.group(1) or '').strip()
            nm = re.search(r"name:\s*'([\w.-]+)'", arg) or re.fullmatch(r"'([\w.-]+)'", arg)
            name = nm.group(1) if nm else m.group(2)
            stream = bool(re.search(r"mode:\s*'stream'", arg))
            doc = ''
            dm = re.search(r'/\*\*((?:(?!\*/).)*?)\*/\s*$', text[:m.start()], re.S)
            if dm:
                body = re.sub(r'^\s*\*\s?', '', dm.group(1), flags=re.M)
                doc = _first_sentence(body.split('@param')[0].split('@returns')[0].split('@throws')[0])
            out.append({'id': 'remote:%s/%s' % (ns, name), 'kind': 'remote', 'dshSource': rel,
                        'description': doc, 'stream': stream})
    seen = {}
    for r in out:  # the same wire name twice would make the table ambiguous
        seen.setdefault(r['id'], r)
    return sorted(seen.values(), key=lambda r: r['id'])


_SLOT_CATALOG = 'packages/extensions/cordis-client-runner/src/client/slot-catalog.ts'
_SLOT_ENTRY = re.compile(
    r"^    key: '([^']+)',\n    kind: '(\w+)',\n    scope: '([\w-]+)',\n    summary: '((?:[^'\\]|\\.)*)'.*?^    source: '([^':]+)",
    re.M | re.S)


def scan_slots(src: Path) -> list[dict]:
    """Every slot of dsh's generated client slot catalog (the SlotMap keys a browser half can register into)."""
    f = src / _SLOT_CATALOG
    if not f.is_file():
        return []
    out = []
    for m in _SLOT_ENTRY.finditer(f.read_text()):
        out.append({'id': 'slot:' + m.group(1), 'kind': 'slot', 'dshSource': m.group(5),
                    'description': _first_sentence(m.group(4).replace("\\'", "'")),
                    'cardinality': m.group(2), 'scope': m.group(3)})
    return sorted(out, key=lambda r: r['id'])


def scan_settings(src: Path) -> list[dict]:
    """Every settings namespace (a plugin entry id) the web client reads or writes: the argument of `configForms.get`,
    the list of `whileServed` and the namespace of `remote.settings.update|mutate|replace`, with named constants resolved."""
    files = []
    for p in sorted((src / 'packages' / 'client').glob('**/*.ts*')):
        rel = p.relative_to(src).as_posix()
        if _is_source(rel):
            files.append((rel, p.read_text()))
    consts: dict[str, tuple[str, str]] = {}
    for rel, text in files:
        for m in re.finditer(r"^(?:export\s+)?const\s+([A-Z][A-Z0-9_]+)\s*=\s*'([^']+)'", text, re.M):
            consts.setdefault(m.group(1), (m.group(2), rel))
    found: dict[str, str] = {}

    def add(arg: str, rel: str) -> None:
        for lit, name in re.findall(r"'([^']+)'|\b([A-Z][A-Z0-9_]+)\b", arg):
            if lit:
                found.setdefault(lit, rel)
            elif name in consts:
                found.setdefault(consts[name][0], consts[name][1])

    for rel, text in files:
        for m in re.finditer(r"configForms\.get(?:<[^>]*(?:<[^>]*>)?[^>]*>)?\(\s*([^)]*)\)", text):
            add(m.group(1), rel)
        for m in re.finditer(r"whileServed\(\s*\[([^\]]*)\]", text):
            add(m.group(1), rel)
        for m in re.finditer(r"remote\.settings\.(?:update|mutate|replace)\(\s*([^,)]*)", text):
            add(m.group(1), rel)
    return [{'id': 'settings:' + ns, 'kind': 'settings', 'dshSource': rel, 'description': ''}
            for ns, rel in sorted(found.items())]


def scan_all(src: Path) -> list[dict]:
    return scan_packages(src) + scan_remotes(src) + scan_slots(src) + scan_settings(src)


# ---------------------------------------------------------------------------------------------- the table

def load_table(path: Path = TABLE) -> dict:
    return json.loads(path.read_text())


def pinned_commit() -> str | None:
    try:
        return json.loads(SYNC.read_text())['dsh']['commit']
    except (OSError, KeyError, ValueError):
        return None


def validate(table: dict, root: Path = REPO) -> list[str]:
    """Problems of the table on its own (no dsh checkout): schema, vocabulary, Whalee paths."""
    errors: list[str] = []
    if table.get('schemaVersion') != 1:
        errors.append('schemaVersion must be 1')
    commit = (table.get('dsh') or {}).get('commit')
    if not isinstance(commit, str) or not re.fullmatch(r'[0-9a-f]{40}', commit):
        errors.append('dsh.commit must be a full commit hash')
    if not str((table.get('whalee') or {}).get('reviewedAt', '')).strip():
        errors.append('whalee.reviewedAt must name the Whalee commit the statuses were read at')
    rows = table.get('rows')
    if not isinstance(rows, list):
        return errors + ['rows must be a list']
    seen: set[str] = set()
    for i, row in enumerate(rows):
        rid = row.get('id') if isinstance(row, dict) else None
        where = 'row %d (%s)' % (i, rid)
        if not isinstance(row, dict) or not isinstance(rid, str):
            errors.append('row %d: not an object with an id' % i)
            continue
        if rid in seen:
            errors.append('%s: duplicate id' % where)
        seen.add(rid)
        for extra in sorted(set(row) - ROW_FIELDS):
            errors.append('%s: unknown field %r' % (where, extra))
        kind = row.get('kind')
        if kind not in KINDS:
            errors.append('%s: kind must be one of %s' % (where, ', '.join(KINDS)))
        elif not rid.startswith(kind + ':'):
            errors.append('%s: id must start with "%s:"' % (where, kind))
        if row.get('area') not in AREAS:
            errors.append('%s: area must be one of %s' % (where, ', '.join(AREAS)))
        if row.get('platform') not in PLATFORMS:
            errors.append('%s: platform must be one of %s' % (where, ', '.join(PLATFORMS)))
        for field in ('dshSource', 'description'):
            if not isinstance(row.get(field), str) or not row[field].strip():
                errors.append('%s: %s is required' % (where, field))
        status = row.get('status')
        if status not in STATUSES:
            errors.append('%s: status must be one of %s' % (where, ', '.join(STATUSES)))
            continue
        paths = row.get('whalee', [])
        if not isinstance(paths, list) or not all(isinstance(p, str) for p in paths):
            errors.append('%s: whalee must be a list of paths' % where)
            paths = []
        if status in ('ported', 'partial') and not paths:
            errors.append('%s: %s needs the Whalee location (whalee)' % (where, status))
        if status in ('missing', 'na') and paths:
            errors.append('%s: %s must not name a Whalee location' % (where, status))
        for p in paths:
            if p.startswith('/') or '..' in p.split('/') or not (root / p).exists():
                errors.append('%s: whalee path does not exist: %s' % (where, p))
        if status == 'partial' and not str(row.get('notes', '')).strip():
            errors.append('%s: partial needs notes saying what is missing' % where)
        if status == 'na' and not str(row.get('reason', '')).strip():
            errors.append('%s: na needs a reason' % where)
        if status == 'na' and _PHONE_FIRST.search(str(row.get('reason', ''))):
            errors.append('%s: "phone-first" is not a reason for na: a desktop build exists, mark it missing for platform desktop' % where)
        if status != 'na' and 'reason' in row:
            errors.append('%s: reason is only for na' % where)
        if 'priority' in row and row['priority'] not in PRIORITIES:
            errors.append('%s: priority must be one of %s' % (where, ', '.join(PRIORITIES)))
        if 'priority' in row and status not in ('missing', 'partial'):
            errors.append('%s: priority is only for missing and partial rows' % where)
        if kind == 'package' and status in ('missing', 'partial') and 'priority' not in row:
            errors.append('%s: a missing or partial package needs a priority' % where)
    return errors


def coverage(table: dict, upstream: list[dict]) -> tuple[list[dict], list[str]]:
    """(upstream items without a row, ids of rows whose upstream item is gone)."""
    have = {r['id'] for r in table.get('rows', []) if isinstance(r, dict)}
    want = {u['id'] for u in upstream}
    return [u for u in upstream if u['id'] not in have], sorted(have - want)


def stub(item: dict) -> dict:
    return {'id': item['id'], 'kind': item['kind'], 'area': 'misc', 'platform': 'both', 'dshSource': item['dshSource'],
            'description': item['description'] or 'TODO: what the user can do with this',
            'status': 'missing'}


# ---------------------------------------------------------------------------------------------- the markdown

def counts(rows: list[dict]) -> dict[str, int]:
    c = {s: 0 for s in STATUSES}
    for r in rows:
        c[r['status']] += 1
    return c


def _cell(text: str) -> str:
    return str(text).replace('|', '\\|').replace('\n', ' ').strip()


def _name(row: dict) -> str:
    return row['id'].split(':', 1)[1]


def render(table: dict) -> str:
    rows = table['rows']
    out = [
        '# Capability parity: dsh web client vs Whalee',
        '',
        '<!-- Generated by tool/capability_parity.py from docs/capability-parity.json. Do not edit by hand. -->',
        '',
        'One row per upstream item of the pinned dsh (`%s`, npm `%s`): every `packages/client/ui-*` package, every `@Remote`'
        % (table['dsh']['commit'][:9], table['dsh'].get('npmVersion', '?')),
        'method, every slot name and every settings namespace, each marked **ported**, **partial**, **missing** or **na** (not',
        'applicable, with the reason) and with the **platform** it is meant for (`phone`, `desktop` or `both`).',
        'The source of truth is [`capability-parity.json`](capability-parity.json); the status of a',
        'row comes from reading the Whalee code at the path in its `whalee` field. `tool/capability_parity.py --check` (part of',
        '`tool/preflight`) is red when the pin has an item without a row.',
        '',
        '## Counts',
        '',
        '| area | ported | partial | missing | na | total |',
        '|---|---:|---:|---:|---:|---:|',
    ]
    total = {s: 0 for s in STATUSES}
    for area in AREAS:
        c = counts([r for r in rows if r['area'] == area])
        out.append('| %s | %d | %d | %d | %d | %d |' % (AREA_TITLES[area], c['ported'], c['partial'], c['missing'], c['na'], sum(c.values())))
        for s in STATUSES:
            total[s] += c[s]
    out.append('| **all** | %d | %d | %d | %d | %d |' % (total['ported'], total['partial'], total['missing'], total['na'], sum(total.values())))
    out += ['', '| kind | ported | partial | missing | na | total |', '|---|---:|---:|---:|---:|---:|']
    for kind in KINDS:
        c = counts([r for r in rows if r['kind'] == kind])
        out.append('| %s | %d | %d | %d | %d | %d |' % (kind, c['ported'], c['partial'], c['missing'], c['na'], sum(c.values())))
    out += ['', 'By platform (where Whalee is meant to offer the item: `phone`, `desktop`, or `both`):', '',
            '| platform | ported | partial | missing | na | total |', '|---|---:|---:|---:|---:|---:|']
    for plat in PLATFORMS:
        c = counts([r for r in rows if r['platform'] == plat])
        out.append('| %s | %d | %d | %d | %d | %d |' % (plat, c['ported'], c['partial'], c['missing'], c['na'], sum(c.values())))
    todo = [r for r in rows if r['kind'] == 'package' and r['status'] in ('missing', 'partial') and 'priority' in r]
    if todo:
        out += ['', '## Packages still to do, by priority', '']
        for pr in PRIORITIES:
            group = [r for r in todo if r['priority'] == pr]
            if not group:
                continue
            out += ['**%s**' % pr, '']
            for r in sorted(group, key=lambda r: r['id']):
                out.append('- `%s` (%s, %s): %s%s' % (_name(r), r['status'], r['platform'], r['description'].rstrip('.') + '.',
                                                   (' ' + r['notes']) if r.get('notes') else ''))
            out.append('')
        out.pop()
    for area in AREAS:
        group = [r for r in rows if r['area'] == area]
        if not group:
            continue
        c = counts(group)
        out += ['', '## %s' % AREA_TITLES[area], '',
                '%d ported, %d partial, %d missing, %d na.' % (c['ported'], c['partial'], c['missing'], c['na']), '']
        for kind in KINDS:
            part = [r for r in group if r['kind'] == kind]
            if not part:
                continue
            out += ['### %s (%d)' % (kind, len(part)), '', '| item | status | platform | what the user can do | Whalee |', '|---|---|---|---|---|']
            for r in sorted(part, key=lambda r: r['id']):
                where = ', '.join('`%s`' % p for p in r.get('whalee', []))
                extra = r.get('notes') or r.get('reason') or ''
                tail = '; '.join(x for x in (where, extra) if x)
                out.append('| `%s` | %s | %s | %s | %s |' % (_name(r), r['status'], r['platform'], _cell(r['description']), _cell(tail)))
            out.append('')
        out.pop()
    return '\n'.join(out) + '\n'


# ---------------------------------------------------------------------------------------------- the commands

def check(root: Path = REPO, src: Path | None = None) -> tuple[int, str]:
    lines: list[str] = []
    try:
        table = load_table(root / 'docs' / 'capability-parity.json')
    except (OSError, ValueError) as e:
        return 1, 'capability-parity: cannot read docs/capability-parity.json: %s' % e
    errors = validate(table, root)
    md = root / 'docs' / 'capability-parity.md'
    if not errors:
        if not md.is_file() or md.read_text() != render(table):
            errors.append('docs/capability-parity.md is stale: run tool/capability_parity.py --write')
        pin = pinned_commit() if root == REPO else None
        if pin and table['dsh']['commit'] != pin:
            errors.append('the table was reviewed against dsh %s but docs/upstream-sync.json pins %s: review the new pin, '
                          'then set dsh.commit (and dsh.npmVersion) in docs/capability-parity.json'
                          % (table['dsh']['commit'][:9], pin[:9]))
    c = counts(table['rows']) if not errors and table.get('rows') else None
    if errors:
        return 1, 'capability-parity: FAILED\n' + '\n'.join('  ' + e for e in errors)
    summary = 'capability-parity: %d rows (%d ported, %d partial, %d missing, %d na)' % (
        len(table['rows']), c['ported'], c['partial'], c['missing'], c['na'])
    if src is None:
        return 2, summary + '; the dsh checkout was not found (set DSH_SRC or link .local/dsh-src), so upstream coverage was not checked'
    upstream = scan_all(src)
    new, stale = coverage(table, upstream)
    for kind in KINDS:  # a scanner that silently finds nothing would pass the check for the wrong reason
        if not any(u['kind'] == kind for u in upstream):
            lines.append('the scanner found no %s rows in %s: the dsh source layout changed, fix tool/capability_parity.py' % (kind, src))
    for u in new:
        lines.append('no row for %s (%s)' % (u['id'], u['dshSource']))
    for rid in stale:
        lines.append('row %s: the pinned dsh no longer has it, drop the row' % rid)
    if lines:
        extra = ''
        if new:
            extra = '\nstubs for the new items (set area, status and notes after reading the Whalee code):\n' + \
                json.dumps([stub(u) for u in new], indent=1)
        return 1, 'capability-parity: FAILED\n' + '\n'.join('  ' + l for l in lines) + extra
    return 0, summary + '; every upstream ui package, Remote method, slot and settings namespace of the pin has a row (%d items)' % len(upstream)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group()
    g.add_argument('--write', action='store_true', help='regenerate docs/capability-parity.md (default)')
    g.add_argument('--check', action='store_true', help='fail when the table, the markdown or the upstream coverage is not right')
    g.add_argument('--skeleton', action='store_true', help='print stubs for upstream items without a row')
    args = ap.parse_args(argv)
    if args.check:
        code, text = check(REPO, dsh_src())
        print(text)
        return code
    if args.skeleton:
        src = dsh_src()
        if src is None:
            print('dsh checkout not found (set DSH_SRC or link .local/dsh-src)', file=sys.stderr)
            return 2
        new, _ = coverage(load_table(), scan_all(src))
        print(json.dumps([stub(u) for u in new], indent=1))
        return 0
    table = load_table()
    errors = validate(table)
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    MARKDOWN.write_text(render(table))
    print('wrote %s' % MARKDOWN.relative_to(REPO))
    return 0


if __name__ == '__main__':
    sys.exit(main())
