#!/usr/bin/env python3
"""Page / component inventory of the dsh web client against the parity cases. Generated on demand, never committed.

  tool/parity-ext/inventory.py --write build/parity-ext/inventory.md [--out build/parity-ext]
  tool/parity-ext/inventory.py --stdout
  tool/parity-ext/inventory.py --check              validate the rows and their id globs only
  tool/parity-ext/inventory.py --check --discover   also list dsh ui-primitives files that have no row (needs DSH_SRC)

ROWS holds only web metadata: what the dsh surface is, where its source lives and the case-id glob that
covers it once a case exists. Every STATUS is computed from the case ids that exist (the committed core
manifest plus <out>/cases.json when an extension run built it) and the Flutter coverage map of the last
run (`<out>/visual-testing-results/flutter-case-map.json`):

  ok         a case exists and Flutter maps it
  untested   a case exists but no Flutter coverage map is available yet (run a suite first)
  web-only   a case exists (React renders it), Flutter has no widget / mapping
  MISSING    no case yet
  excluded   deliberately out of scope (reason in the row)

So a branch that adds cases for a listed surface edits nothing here. Only a NEW dsh surface needs a row.
"""
import argparse
import fnmatch
import json
import pathlib
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from parity_lib import env, manifest as mf  # noqa: E402

PRIM = 'packages/client/ui-primitives/src/'
# name, source, case glob, priority (P1 = next Flutter widgets), excluded reason
ROWS = [
    ('Button', PRIM + 'Button.tsx', 'components.button.*', 'P0', None),
    ('Input', PRIM + 'Input.tsx', 'components.input.*', 'P1', None),
    ('Tag', PRIM + 'Tag.tsx', 'components.tag.*', 'P1', None),
    ('Pill', PRIM + 'Pill.tsx', 'components.pill.*', 'P1', None),
    ('Switch', PRIM + 'Switch.tsx', 'components.switch.*', 'P1', None),
    ('Checkbox', PRIM + 'Checkbox.tsx', 'components.checkbox.*', 'P1', None),
    ('SegmentedControl', PRIM + 'SegmentedControl.tsx', 'components.segmented-control.*', 'P2', None),
    ('SegmentedTabs', PRIM + 'SegmentedTabs.tsx', 'components.segmented-tabs.*', 'P2', None),
    ('StateDot', PRIM + 'StateDot.tsx', 'components.state-dot.*', 'P2', None),
    ('ConnectionIndicator', PRIM + 'ConnectionIndicator.tsx', 'components.connection-indicator.*', 'P2', None),
    ('DisclosureRow', PRIM + 'DisclosureRow.tsx', 'components.disclosure-row.*', 'P2', None),
    ('ConfigField', PRIM + 'ConfigField.tsx', 'components.config-field.*', 'P2', None),
    ('Tooltip', PRIM + 'Tooltip.tsx', 'components.tooltip.*', 'P2', None),
    ('Toast', PRIM + 'Toast.tsx', 'components.toast.*', 'P2', None),
    ('Modal', PRIM + 'Modal.tsx', 'components.modal.*', 'P2', None),
    ('Menu', PRIM + 'Menu.tsx', 'components.menu.*', 'P2', None),
    ('CodeCard', PRIM + 'CodeToolbar.tsx', 'components.code-card.*', 'P2', None),
    ('Markdown', PRIM + 'markdown', 'components.markdown.*', 'P1', None),
    ('Chat message list', 'packages/client/ui-chat', 'screens.chat.*', 'P1', None),
    ('Tool call cards', 'packages/client/ui-tool', 'components.tool.*', 'P1', None),
    ('Approval cards', 'packages/client/ui-approval', 'components.approval.*', 'P1', None),
    ('Settings', 'packages/client/ui-settings', 'screens.settings.*', 'P3', None),
    ('Sidebar terminal', 'packages/client/ui-sidebar-terminal', 'components.terminal.*', None, 'no terminal surface planned'),
]
STATUSES = ('ok', 'web-only', 'untested', 'MISSING', 'excluded')


def check_rows():
    errors, seen = [], set()
    for name, source, glob, priority, excluded in ROWS:
        if name in seen:
            errors.append('duplicate row %s' % name)
        seen.add(name)
        if not re.match(r'^(components|screens)\.[a-z0-9*.-]+$', glob):
            errors.append('%s: malformed glob %r' % (name, glob))
        if priority not in (None, 'P0', 'P1', 'P2', 'P3'):
            errors.append('%s: bad priority %r' % (name, priority))
        if excluded is None and priority is None:
            errors.append('%s: needs a priority or an excluded reason' % name)
    return errors


def known_cases(outs):
    ids = {c['id'] for c in mf.load_manifest(env.SHARED / 'cases.json')['cases']}
    for out in outs:
        ext = pathlib.Path(out) / 'cases.json'
        if ext.is_file():
            try:
                ids |= {c['id'] for c in mf.load_manifest(ext)['cases']}
            except mf.ManifestError:
                pass
    return ids


def compute(outs):
    ids = known_cases(outs)
    coverage = {}
    for out in outs:
        path = pathlib.Path(out) / 'visual-testing-results' / 'flutter-case-map.json'
        if path.is_file():
            coverage.update(json.loads(path.read_text()))
    rows = []
    for name, source, glob, priority, excluded in ROWS:
        matching = sorted(i for i in ids if fnmatch.fnmatchcase(i, glob))
        if excluded:
            status = 'excluded'
        elif not matching:
            status = 'MISSING'
        elif not any(i in coverage for i in matching):
            status = 'untested'
        elif all(coverage[i]['status'] == 'mapped' for i in matching if i in coverage):  # sampled-out cases have no entry
            status = 'ok'
        else:
            status = 'web-only'
        rows.append((name, source, glob, priority or '-', status, len(matching), excluded or ''))
    return rows


def render(rows):
    lines = ['# dsh web surfaces vs parity cases', '', '| surface | source | case glob | priority | status | cases | note |', '|---|---|---|---|---|---:|---|']
    for name, source, glob, priority, status, n, note in rows:
        lines.append('| %s | `%s` | `%s` | %s | %s | %d | %s |' % (name, source, glob, priority, status, n, note))
    counts = {s: sum(r[4] == s for r in rows) for s in STATUSES}
    lines += ['', ', '.join('%s: %d' % kv for kv in counts.items())]
    return '\n'.join(lines) + '\n'


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', action='append', help='parity output directory (repeatable; default build/parity and build/parity-ext)')
    ap.add_argument('--write')
    ap.add_argument('--stdout', action='store_true')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--discover', action='store_true')
    args = ap.parse_args()
    errors = check_rows()
    if args.discover:
        src = env.dsh_src() / PRIM
        if not src.is_dir():
            errors.append('--discover needs the dsh checkout (DSH_SRC); %s not found' % src)
        else:
            listed = {pathlib.Path(r[1]).stem for r in ROWS}
            unlisted = sorted(p.stem for p in src.glob('[A-Z]*.tsx') if p.stem not in listed)
            print('ui-primitives files without a row: %s' % (', '.join(unlisted) or 'none'))
    if args.check:
        print('\n'.join(errors) or 'inventory rows: ok')
        return 1 if errors else 0
    if errors:
        sys.exit('\n'.join(errors))
    text = render(compute(args.out or [env.ROOT / 'build' / 'parity', env.ROOT / 'build' / 'parity-ext']))
    if args.write:
        pathlib.Path(args.write).parent.mkdir(parents=True, exist_ok=True)
        pathlib.Path(args.write).write_text(text)
    if args.stdout or not args.write:
        sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
