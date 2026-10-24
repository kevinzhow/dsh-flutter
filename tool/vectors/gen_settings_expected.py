#!/usr/bin/env python3
"""Produce / verify the expectations of a dsh-settings-vector fixture.

The expectations come from dsh's own TypeScript settings client code, run over
the fixture's inputs by tool/vectors/ts/run_settings_vector.mjs. A fixture's
`kind` selects the family:

  schema      per case `expect`: null when dsh's SettingsSchemaService (real
              schemastery resolver) accepts the value, otherwise its failure text
  form        `expected`: snapshots after every step of a scripted trace through
              dsh's real SettingsDescribeMirror, ConfigFormController and
              ConfigForms (mounted by the real ui-settings `apply`)
  form-model  `expected`: states after every step of dsh's real SettingsFormModel
              over a scripted scope

    gen_settings_expected.py --write FIXTURE   run the model, store the expectations
    gen_settings_expected.py --check FIXTURE   run the model, exit 1 if they differ

Exit status: 0 ok, 1 mismatch or runner failure, 2 tool unavailable (missing
dsh checkout, node, or the vector-node install).

Environment (defaults are relative to the repository root):
    DSH_SRC              dsh checkout, default <repo>/.local/dsh-src
    DSH_VECTOR_NODE_DIR  node install with tsx/zustand/immer, default <repo>/.local/vector-node
    NODE                 node executable (>= 22.19), default `node` from PATH
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUNNER = 'tool/vectors/ts/run_settings_vector.mjs'

REAL = {
    'schema': [
        'SettingsSchemaService.rehydrate/validate (ui-settings/client/schema.ts)',
        'Schema.resolve and every resolver (vendor/schemastery/src/index.ts), cosmokit deepEqual/clone/volatile',
    ],
    'form': [
        'ui-settings `apply` (client/index.ts): invalidation subscriptions, eager ensure, ConfigForms service',
        'SettingsDescribeMirror (client/settings-mirror.ts), ConfigFormController and ConfigForms (client/config-form.ts)',
        'SettingsSchemaService and schemastery (section validation), createSnapshotStore (client/store)',
        'cordis Context and fiber disposal (vendor/cordis)',
    ],
    'form-model': [
        'SettingsFormModel, settingsNumberField, settingsTextField (ui-primitives/settings-form/form-model.ts)',
        'createSnapshotStore (client/store)',
    ],
}
GLUE = {
    'schema': ['case driver: structuredClone per case, a throwing rehydrate counts as a failure'],
    'form': [
        'fake ctx.remote (TestRemote double of dsh test-support, `$on` + emit) whose settings.describe/mutate answer from the script',
        'step driver, settle loop and snapshot encoder',
    ],
    'form-model': ['scripted SettingsFormScope (snapshots and mutate outcomes from the script)', 'step driver and state encoder'],
}
MODEL = {
    'schema': 'dsh TypeScript settings schema service over the vendored schemastery resolver',
    'form': 'dsh TypeScript settings describe mirror and configuration forms (ui-settings)',
    'form-model': 'dsh TypeScript staged settings form model (ui-primitives)',
}
# Top-level keys written one entry per line, so a fixture diffs readably.
LINE_KEYS = ('schemas', 'cases', 'steps', 'expected')


def unavailable(message):
    print('gen_settings_expected: tool unavailable: %s' % message, file=sys.stderr)
    sys.exit(2)


def locate():
    dsh_src = os.path.abspath(os.environ.get('DSH_SRC') or os.path.join(ROOT, '.local', 'dsh-src'))
    node_dir = os.path.abspath(os.environ.get('DSH_VECTOR_NODE_DIR') or os.path.join(ROOT, '.local', 'vector-node'))
    if not os.path.isfile(os.path.join(dsh_src, 'packages/client/ui-settings/src/client/schema.ts')):
        unavailable('dsh checkout not found at %s (set DSH_SRC or link <repo>/.local/dsh-src)' % dsh_src)
    if not os.path.isfile(os.path.join(node_dir, 'node_modules/tsx/dist/esm/api/index.mjs')):
        unavailable(
            'vector-node install missing at %s; create it with: mkdir -p DIR && '
            'cp tool/vectors/ts/package.json tool/vectors/ts/pnpm-lock.yaml DIR && '
            'cd DIR && pnpm install --frozen-lockfile --ignore-workspace --config.strict-dep-builds=false '
            '(set DSH_VECTOR_NODE_DIR=DIR, or link it as <repo>/.local/vector-node)' % node_dir)
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
    out_file = tempfile.NamedTemporaryFile(prefix='dsh-settings-vector-', suffix='.json', delete=False)
    out_file.close()
    proc = subprocess.run(
        [node, os.path.join(ROOT, RUNNER), fixture_path, '--out', out_file.name],
        capture_output=True, text=True, env=env, cwd=ROOT)
    if proc.stderr.strip():
        sys.stderr.write(proc.stderr)
    if proc.returncode == 2:
        unavailable('runner reported a missing prerequisite')
    if proc.returncode != 0:
        print('gen_settings_expected: runner failed (exit %d)' % proc.returncode, file=sys.stderr)
        sys.exit(1)
    try:
        with open(out_file.name, encoding='utf-8') as handle:
            return json.load(handle)
    finally:
        os.unlink(out_file.name)


def compact(value):
    return json.dumps(value, separators=(',', ':'), allow_nan=False)


def dump(fixture):
    """Fixture JSON: top level indented, the bulky collections one entry per line."""
    lines = []
    for key, value in fixture.items():
        if key in LINE_KEYS and isinstance(value, list):
            body = ',\n'.join('  ' + compact(item) for item in value)
            lines.append(' %s: [\n%s\n ]' % (json.dumps(key), body))
        elif key in LINE_KEYS and isinstance(value, dict):
            body = ',\n'.join('  %s: %s' % (json.dumps(k), compact(v)) for k, v in value.items())
            lines.append(' %s: {\n%s\n }' % (json.dumps(key), body))
        else:
            text = json.dumps(value, indent=1, allow_nan=False).replace('\n', '\n ')
            lines.append(' %s: %s' % (json.dumps(key), text))
    return '{\n' + ',\n'.join(lines) + '\n}\n'


def load(path):
    with open(path, encoding='utf-8') as handle:
        return json.load(handle)


def with_expectations(case, expect):
    """The case with `expect` placed after `value`."""
    out = {}
    for key, value in case.items():
        if key == 'expect':
            continue
        out[key] = value
        if key == 'value':
            out['expect'] = expect
    out.setdefault('expect', expect)
    return out


def apply_expectations(fixture, produced):
    kind = fixture['kind']
    fixture.pop('expectedBy', None)
    fixture['expectedBy'] = {
        'model': MODEL[kind],
        'dshCommit': dsh_commit(),
        'runner': RUNNER,
        'realClasses': REAL[kind],
        'glue': GLUE[kind],
    }
    # Keep `expectedBy` right after the descriptive header keys.
    ordered = {k: v for k, v in fixture.items() if k != 'expectedBy'}
    head = {}
    for key in ('format', 'kind', 'description'):
        if key in ordered:
            head[key] = ordered.pop(key)
    head['expectedBy'] = fixture['expectedBy']
    head.update(ordered)
    if kind == 'schema':
        head['cases'] = [with_expectations(c, e) for c, e in zip(head['cases'], produced['expect'])]
    else:
        head.pop('expected', None)
        head['expected'] = produced['expected']
    return head


def summary(fixture):
    if fixture['kind'] == 'schema':
        return '%d cases' % len(fixture['cases'])
    return '%d steps' % len(fixture['steps'])


def first_difference(committed, produced):
    for index, (a, b) in enumerate(zip(committed, produced)):
        if a != b:
            return index
    return min(len(committed), len(produced))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--write', metavar='FIXTURE')
    group.add_argument('--check', metavar='FIXTURE')
    args = parser.parse_args()
    path = args.write or args.check
    fixture = load(path)
    if fixture.get('format') != 'dsh-settings-vector/1':
        print('gen_settings_expected: %s is not a dsh-settings-vector/1 fixture' % path, file=sys.stderr)
        return 1
    produced = run_model(path)
    kind = fixture['kind']
    if args.write:
        updated = apply_expectations(fixture, produced)
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(dump(updated))
        print('gen_settings_expected: wrote expectations for %s to %s' % (summary(fixture), path))
        return 0
    if kind == 'schema':
        committed = [case.get('expect', 'MISSING') for case in fixture['cases']]
        model = produced['expect']
    else:
        committed = fixture.get('expected') or []
        model = produced['expected']
    if committed == model:
        print('gen_settings_expected: OK, %s match %s' % (summary(fixture), path))
        return 0
    index = first_difference(committed, model)
    print('gen_settings_expected: MISMATCH in %s: committed %d, model produced %d, first difference at index %d'
          % (path, len(committed), len(model), index))
    return 1


if __name__ == '__main__':
    sys.exit(main())
