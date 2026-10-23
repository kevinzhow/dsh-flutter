#!/usr/bin/env python3
"""Produce / verify the `expected` window snapshots of a dsh-session-vector fixture.

The expected values come from dsh's own TypeScript client model, replayed over
the fixture's recorded trace by tool/vectors/ts/run_vector.mjs (see its header
for which dsh classes run for real and which parts are glue).

    gen_expected.py --write FIXTURE   run the model, store `expectedBy` + `expected` in FIXTURE
    gen_expected.py --check FIXTURE   run the model, exit 1 if FIXTURE's `expected` differs

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

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUNNER = 'tool/vectors/ts/run_vector.mjs'

REAL_CLASSES = [
    'Session (session-controller/client/sessions/session.ts)',
    'SessionEventStream (session-controller/client/transport.ts)',
    'RemoteJournalStream (gateway/client/journal-stream.ts)',
    'RemoteStream (gateway/client/remote-stream.ts)',
    'RemoteStreamCarrierError (gateway/client/stream-client.ts)',
    'ClientAssistantStream (session-controller/client/sessions/assistant-stream.ts)',
    'MutableSessionEventSource (session-controller/client/contract/events.ts)',
    'expandAssistantStream (llm/assistant-stream.ts)',
]
GLUE = [
    'fake SessionRemotes: session.follow yields the fixture frames per connection generation, '
    'session.page answers recorded pages matched on (address, throughSeq, beforeSeq), '
    '$stream builds the real RemoteStream over a fake connection handle',
    'step driver, settle loop and snapshot encoder',
    'module resolution: dsh tsconfig paths via tsx, zustand/immer from the vector-node install',
]


def unavailable(message):
    print('gen_expected: tool unavailable: %s' % message, file=sys.stderr)
    sys.exit(2)


def locate():
    dsh_src = os.path.abspath(os.environ.get('DSH_SRC') or os.path.join(ROOT, '.local', 'dsh-src'))
    node_dir = os.path.abspath(os.environ.get('DSH_VECTOR_NODE_DIR') or os.path.join(ROOT, '.local', 'vector-node'))
    if not os.path.isfile(os.path.join(dsh_src, 'packages/api/session-controller/src/client/sessions/session.ts')):
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
    proc = subprocess.run(
        [node, os.path.join(ROOT, RUNNER), fixture_path],
        capture_output=True, text=True, env=env, cwd=ROOT)
    if proc.stderr.strip():
        sys.stderr.write(proc.stderr)
    if proc.returncode == 2:
        unavailable('runner reported a missing prerequisite')
    if proc.returncode != 0:
        print('gen_expected: runner failed (exit %d)' % proc.returncode, file=sys.stderr)
        sys.exit(1)
    return json.loads(proc.stdout)


def load(path):
    with open(path, encoding='utf-8') as handle:
        return json.load(handle)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--write', metavar='FIXTURE')
    group.add_argument('--check', metavar='FIXTURE')
    args = parser.parse_args()
    path = args.write or args.check
    fixture = load(path)
    expected = run_model(path)
    if args.write:
        fixture.pop('expected', None)
        fixture.pop('expectedBy', None)
        fixture['expectedBy'] = {
            'model': 'dsh TypeScript client (session-controller client + gateway journal)',
            'dshCommit': dsh_commit(),
            'runner': RUNNER,
            'realClasses': REAL_CLASSES,
            'glue': GLUE,
        }
        fixture['expected'] = expected
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(json.dumps(fixture, indent=1) + '\n')
        print('gen_expected: wrote %d snapshots to %s' % (len(expected), path))
        return 0
    if fixture.get('expected') == expected:
        print('gen_expected: OK, %d snapshots match %s' % (len(expected), path))
        return 0
    committed = fixture.get('expected') or []
    first = next((i for i, (a, b) in enumerate(zip(committed, expected)) if a != b), min(len(committed), len(expected)))
    print('gen_expected: MISMATCH in %s: committed %d snapshots, model produced %d, first difference at snapshot %d'
          % (path, len(committed), len(expected), first))
    return 1


if __name__ == '__main__':
    sys.exit(main())
