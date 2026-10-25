#!/usr/bin/env python3
"""Produce / verify the expected snapshots of a dsh-session-vector fixture.

The expected values come from dsh's own TypeScript code, replayed over the
fixture's recorded trace by tool/vectors/ts/run_vector.mjs (see its header and
chat_glue.mjs for which dsh classes run for real and which parts are glue):

  expected      the Session event window after every snapshot step (client model)
  expectedChat  the chat target snapshot of dsh's conversation engine over each
                of those windows (nodes in order, timeline, open turn)

    gen_expected.py --write FIXTURE   run the model, store `expectedBy`, `expected`, `expectedChat`
    gen_expected.py --check FIXTURE   run the model, exit 1 if either differs

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
    'ConversationNodeAssembler, ConversationEventRegistry, ConversationViewRegistry, ConversationLocationIndex (ui-conversation)',
    'inbox, message, developer-message, system-message, request-prompt, assistant, tool, turn-error, turn-max-tokens, '
    'turn-tail, model-retry, command, compaction and turn-process Definitions, unknown-surface fallback and the chat snapshot builder (ui-chat)',
]
GLUE = [
    'fake SessionRemotes: session.follow yields the fixture frames per connection generation, '
    'session.page answers recorded pages matched on (address, throughSeq, beforeSeq), '
    '$stream builds the real RemoteStream over a fake connection handle',
    'step driver, settle loop and snapshot encoder',
    'conversation feed loop (copy of BoundConversation) and the chat projection (tool/vectors/ts/chat_glue.mjs); '
    'turn-process and process groups are not registered',
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
    out_file = tempfile.NamedTemporaryFile(prefix='dsh-vector-', suffix='.json', delete=False)
    out_file.close()
    proc = subprocess.run(
        [node, os.path.join(ROOT, RUNNER), fixture_path, '--out', out_file.name],
        capture_output=True, text=True, env=env, cwd=ROOT)
    if proc.stderr.strip():
        sys.stderr.write(proc.stderr)
    if proc.returncode == 2:
        unavailable('runner reported a missing prerequisite')
    if proc.returncode != 0:
        print('gen_expected: runner failed (exit %d)' % proc.returncode, file=sys.stderr)
        sys.exit(1)
    try:
        with open(out_file.name, encoding='utf-8') as handle:
            return json.load(handle)
    finally:
        os.unlink(out_file.name)


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
    produced = run_model(path)
    expected, expected_chat = produced['window'], produced['chat']
    if args.write:
        fixture.pop('expected', None)
        fixture.pop('expectedChat', None)
        fixture.pop('expectedBy', None)
        fixture['expectedBy'] = {
            'model': 'dsh TypeScript client (session-controller client + gateway journal) and conversation engine (ui-conversation + ui-chat)',
            'dshCommit': dsh_commit(),
            'runner': RUNNER,
            'realClasses': REAL_CLASSES,
            'glue': GLUE,
        }
        fixture['expected'] = expected
        fixture['expectedChat'] = expected_chat
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(json.dumps(fixture, indent=1) + '\n')
        print('gen_expected: wrote %d snapshots to %s' % (len(expected), path))
        return 0
    if fixture.get('expected') == expected and fixture.get('expectedChat') == expected_chat:
        print('gen_expected: OK, %d window and %d chat snapshots match %s' % (len(expected), len(expected_chat), path))
        return 0
    committed_chat = fixture.get('expectedChat') or []
    if fixture.get('expected') == expected:
        first = next((i for i, (a, b) in enumerate(zip(committed_chat, expected_chat)) if a != b),
                     min(len(committed_chat), len(expected_chat)))
        print('gen_expected: MISMATCH in %s: chat snapshots differ (committed %d, model produced %d), first difference at snapshot %d'
              % (path, len(committed_chat), len(expected_chat), first))
        return 1
    committed = fixture.get('expected') or []
    first = next((i for i, (a, b) in enumerate(zip(committed, expected)) if a != b), min(len(committed), len(expected)))
    print('gen_expected: MISMATCH in %s: committed %d snapshots, model produced %d, first difference at snapshot %d'
          % (path, len(committed), len(expected), first))
    return 1


if __name__ == '__main__':
    sys.exit(main())
