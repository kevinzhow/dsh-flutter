#!/usr/bin/env python3
"""Scrub a raw session trace into a committable behaviour-vector fixture.

The raw trace (written by tool/live_spike) holds the follow frames, page reads
and client actions of one real session, in observed order. It may contain real
prompts, replies, paths and ids, so it stays outside the repository. This
script keeps the structure that the session event window depends on (event
`type`, `seq`, `time`, `surfaceOp`, assistant-stream frame shape, record
contiguity, cursors, revisions, every enum-like field) and replaces content:

  * ids (attemptId, sessionId, callId, requestId, rpcId, id, ...) become
    stable pseudonyms (`attempt-1`, ...), consistent across the whole trace;
  * every other string becomes `s<length>` (so text deltas still fold to a
    string of the same length, but carry no words);
  * a tool call's complete `arguments` text (tool/call, assistant/message and
    block-end tool-call blocks) is parsed as JSON and scrubbed structurally:
    the keys stay, every string leaf becomes `s<length>` (`{"command":"s17"}`);
    text that does not parse as a JSON object becomes `s<length>`. Streamed
    `argumentsDelta` fragments stay `s<length>`;
  * long arrays inside event data (tool lists, skill catalogs) keep 2 members;
  * timestamps of the recording are dropped.

The output is refused if it still contains anything on the deny list.

    scrub_trace.py RAW.json OUT.json [--deny SUBSTRING ...]
"""
import argparse
import json
import re
import sys

# String values that are protocol enums or structure, kept verbatim.
KEEP_KEYS = {
    'type', 'kind', 'role', 'blockType', 'eventType', 'mode', 'target', 'surfaceOp',
    'op', 'name', 'format', 'formatStatus', 'origin', 'form', 'status', 'stopReason',
}
# Keys whose string value is an identity: pseudonymised consistently.
ID_KEYS = {
    'attemptId': 'attempt', 'sessionId': 'session', 'callId': 'call', 'requestId': 'request',
    'rpcId': 'rpc', 'id': 'id', 'receiptId': 'receipt', 'parentSessionId': 'session',
    'childSessionId': 'session', 'messageId': 'message', 'toolCallId': 'call',
}
# Arrays that must keep every member (they are the wire structure itself).
KEEP_WHOLE = {'records', 'stream', 'dt', 'texts', 'args', 'content', 'messageSeqs', 'steps'}
LONG = 6


class Scrubber:
    def __init__(self):
        self.ids = {}

    def pseudonym(self, prefix, value):
        key = (prefix, value)
        if key not in self.ids:
            self.ids[key] = '%s-%d' % (prefix, 1 + sum(1 for k in self.ids if k[0] == prefix))
        return self.ids[key]

    def scrub_arguments(self, text):
        try:
            parsed = json.loads(text)
        except ValueError:
            parsed = None
        if not isinstance(parsed, dict):
            return 's%d' % len(text)
        return json.dumps(self.scrub_leaves(parsed), separators=(',', ':'))

    def scrub_leaves(self, value):
        if isinstance(value, dict):
            return {k: self.scrub_leaves(v) for k, v in value.items()}
        if isinstance(value, list):
            return [self.scrub_leaves(v) for v in value]
        if isinstance(value, str):
            return 's%d' % len(value)
        return value

    def scrub(self, value, key=None, in_data=False):
        if isinstance(value, dict):
            out = {}
            for k, v in value.items():
                out[k] = self.scrub(v, k, in_data or k in ('data', 'values'))
            return out
        if isinstance(value, list):
            items = value
            if in_data and key not in KEEP_WHOLE and len(items) > LONG:
                items = items[:2]
            return [self.scrub(v, key, in_data) for v in items]
        if isinstance(value, str):
            if key in ID_KEYS:
                return self.pseudonym(ID_KEYS[key], value)
            if key in KEEP_KEYS:
                return value
            if key == 'arguments':
                return self.scrub_arguments(value)
            return 's%d' % len(value)
        return value  # numbers, bools, null


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('raw')
    ap.add_argument('out')
    ap.add_argument('--deny', action='append', default=[])
    args = ap.parse_args()
    raw = json.load(open(args.raw))
    s = Scrubber()
    steps = []
    for step in raw['steps']:
        step = {k: v for k, v in step.items() if k != 't'}
        if step['op'] == 'follow-open':
            continue  # the request is recorded once in openOptions
        steps.append(s.scrub(step))
    out = {
        'format': 'dsh-session-vector/1',
        'description': 'Scrubbed real session trace: follow frames, page reads and client actions in '
                       'observed order. `expected` is produced by dsh\'s own TypeScript client model.',
        'hostVersion': raw.get('hostVersion'),
        'openOptions': raw['openOptions'],
        'steps': steps,
    }
    text = json.dumps(out, indent=1, sort_keys=False) + '\n'
    deny = [re.escape(d) for d in args.deny if d] + [
        r'/home/', r'/mnt/', r'[?&]token=', r'cookie', r'sk-[A-Za-z0-9]{8}', r'[A-Za-z0-9._-]+@[A-Za-z0-9-]+\.[a-z]{2,}',
        r'https?://', r'127\.0\.0\.1']
    for d in deny:
        hit = re.search(d, text, re.I)
        if hit:
            print('scrub_trace: refusing to write, output still contains %r near %r' % (
                d, text[max(0, hit.start() - 30):hit.end() + 30]), file=sys.stderr)
            return 1
    open(args.out, 'w').write(text)
    print('scrub_trace: %d steps, %d bytes, %d ids pseudonymised' % (len(steps), len(text), len(s.ids)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
