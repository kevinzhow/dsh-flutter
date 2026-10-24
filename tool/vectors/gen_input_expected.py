#!/usr/bin/env python3
"""Produce / verify the expectations of a dsh-input-vector fixture.

The expectations come from dsh's own TypeScript input code, run over the fixture's
cases by tool/vectors/ts/run_input_vector.mjs: `detectTrigger` and the menu reducer
(ui-input-trigger), the `@file` grammar (file-reference), `rankByName` and
`relativeTime` (ui-primitives). The Dart ports (packages/dsh_conversation input,
dsh_feature_commands, dsh_feature_reference) must answer every case the same.

    gen_input_expected.py --write FIXTURE   run the model, store the expectations
    gen_input_expected.py --check FIXTURE   run the model, exit 1 if they differ

Exit status: 0 ok, 1 mismatch or runner failure, 2 tool unavailable (missing dsh
checkout, node or the vector-node install). Environment as gen_settings_expected.py.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUNNER = 'tool/vectors/ts/run_input_vector.mjs'
REAL = [
    'detectTrigger (ui-input-trigger/src/core/detect.ts)',
    'menuReduce, seedGroups, exactMatch (ui-input-trigger/src/core/menu.ts)',
    'activeAtToken, formatFileMention (file-reference/src/grammar.ts)',
    'rankByName (ui-primitives/src/rank-by-name.ts), relativeTime (ui-primitives/src/relative-time.ts)',
]
GLUE = ['case driver and JSON encoders of hits, menu states and rankings; menu events are scripted per case']


def unavailable(message):
    print('gen_input_expected: tool unavailable: %s' % message, file=sys.stderr)
    sys.exit(2)


def locate():
    dsh_src = os.path.abspath(os.environ.get('DSH_SRC') or os.path.join(ROOT, '.local', 'dsh-src'))
    node_dir = os.path.abspath(os.environ.get('DSH_VECTOR_NODE_DIR') or os.path.join(ROOT, '.local', 'vector-node'))
    if not os.path.isfile(os.path.join(dsh_src, 'packages/client/ui-input-trigger/src/core/detect.ts')):
        unavailable('dsh checkout not found at %s (set DSH_SRC or link <repo>/.local/dsh-src)' % dsh_src)
    if not os.path.isfile(os.path.join(node_dir, 'node_modules/tsx/dist/esm/api/index.mjs')):
        unavailable('vector-node install missing at %s (see gen_settings_expected.py)' % node_dir)
    node = os.environ.get('NODE') or shutil.which('node')
    if not node:
        unavailable('node (>= 22.19) not found; set NODE or put it on PATH')
    return dsh_src, node_dir, node


def dsh_commit():
    with open(os.path.join(ROOT, 'docs', 'upstream-sync.json'), encoding='utf-8') as handle:
        return json.load(handle)['dsh']['commit']


def run_model(fixture_path):
    dsh_src, node_dir, node = locate()
    env = dict(os.environ, DSH_SRC=dsh_src, DSH_VECTOR_NODE_DIR=node_dir)
    out_file = tempfile.NamedTemporaryFile(prefix='dsh-input-vector-', suffix='.json', delete=False)
    out_file.close()
    proc = subprocess.run([node, os.path.join(ROOT, RUNNER), fixture_path, '--out', out_file.name],
                          capture_output=True, text=True, env=env, cwd=ROOT)
    if proc.stderr.strip():
        sys.stderr.write(proc.stderr)
    if proc.returncode == 2:
        unavailable('runner reported a missing prerequisite')
    if proc.returncode != 0:
        print('gen_input_expected: runner failed (exit %d)' % proc.returncode, file=sys.stderr)
        sys.exit(1)
    try:
        with open(out_file.name, encoding='utf-8') as handle:
            return json.load(handle)
    finally:
        os.unlink(out_file.name)


def compact(value):
    return json.dumps(value, separators=(',', ':'), allow_nan=False, ensure_ascii=False)


def dump(fixture):
    lines = []
    for key, value in fixture.items():
        if key == 'cases':
            body = ',\n'.join('  ' + compact(item) for item in value)
            lines.append(' %s: [\n%s\n ]' % (json.dumps(key), body))
        else:
            text = json.dumps(value, indent=1, allow_nan=False, ensure_ascii=False).replace('\n', '\n ')
            lines.append(' %s: %s' % (json.dumps(key), text))
    return '{\n' + ',\n'.join(lines) + '\n}\n'


def with_expect(case, expect):
    out = {k: v for k, v in case.items() if k != 'expect'}
    out['expect'] = expect
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--write', metavar='FIXTURE')
    group.add_argument('--check', metavar='FIXTURE')
    args = parser.parse_args()
    path = args.write or args.check
    with open(path, encoding='utf-8') as handle:
        fixture = json.load(handle)
    if fixture.get('format') != 'dsh-input-vector/1':
        print('gen_input_expected: %s is not a dsh-input-vector/1 fixture' % path, file=sys.stderr)
        return 1
    produced = run_model(path)['expect']
    if args.write:
        head = {k: fixture[k] for k in ('format', 'description') if k in fixture}
        head['expectedBy'] = {'dshCommit': dsh_commit(), 'runner': RUNNER, 'realClasses': REAL, 'glue': GLUE}
        head['cases'] = [with_expect(c, e) for c, e in zip(fixture['cases'], produced)]
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(dump(head))
        print('gen_input_expected: wrote expectations for %d cases to %s' % (len(produced), path))
        return 0
    committed = [c.get('expect', 'MISSING') for c in fixture['cases']]
    if committed == produced:
        print('gen_input_expected: OK, %d cases match %s' % (len(produced), path))
        return 0
    index = next((i for i, (a, b) in enumerate(zip(committed, produced)) if a != b), min(len(committed), len(produced)))
    print('gen_input_expected: MISMATCH in %s: first difference at case %d' % (path, index))
    return 1


if __name__ == '__main__':
    sys.exit(main())
