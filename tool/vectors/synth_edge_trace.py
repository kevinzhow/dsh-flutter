#!/usr/bin/env python3
"""Write the synthetic `conversation_edge_vector.json` behaviour-vector fixture.

A hand-authored trace (no recorded content: every string is generic) that
exercises what the recorded traces rarely contain: live reasoning and tool-call
streaming, an interrupted turn with no settled message, a steering message
admitted into a running turn, a failed turn, a max-tokens turn, a non-human
turn trigger, a model retry and a system message. The expected snapshots are NOT
written here: run `gen_expected.py --write` on the output so dsh's own
TypeScript engine produces them.

    synth_edge_trace.py OUT.json
"""
import json
import sys

steps = []
seq = [0]
revision = [0]
time = [1_000_000]


def tick():
    time[0] += 7
    return time[0]


def frame(f):
    steps.append({'op': 'frame', 'generation': 1, 'frame': f})


def event(type_, data, surface=None, extra=None):
    seq[0] += 1
    ev = {'type': type_, 'seq': seq[0], 'time': tick(), 'data': data}
    if surface:
        ev['surfaceOp'] = surface
    if extra:
        ev.update(extra)
    frame({'type': 'event', 'event': ev})
    return ev


def text(t):
    return [{'type': 'text', 'text': t}]


def user_msg(mid, t, kind='user'):
    return {'content': text(t), 'source': {'kind': kind, 'rpcId': 'rpc-' + mid} if kind == 'user' else {'kind': kind},
            'role': 'user', 'id': mid}


def splice(target, start, inserted=(), removed=0):
    d = {'target': target, 'start': start, 'inserted': list(inserted)}
    if removed:
        d['removedCount'] = removed
    return event('agent/inbox/spliced', d)


def stream_start(attempt, turn, step):
    revision[0] += 1
    frame({'type': 'assistant-stream', 'frame': {'type': 'start', 'attemptId': attempt, 'revision': revision[0],
                                                 'turn': turn, 'step': step, 'startedAfterSeq': seq[0]}})
    return {'attempt': attempt, 'index': 0}


def chunk(s, c):
    revision[0] += 1
    frame({'type': 'assistant-stream', 'frame': {'type': 'chunk', 'attemptId': s['attempt'], 'revision': revision[0],
                                                 'index': s['index'], 'time': tick(), 'chunk': c}})
    s['index'] += 1


def stream_end(s, outcome):
    revision[0] += 1
    frame({'type': 'assistant-stream', 'frame': {'type': 'end', 'attemptId': s['attempt'], 'revision': revision[0],
                                                 'index': s['index'], 'outcome': outcome}})


def assistant_message(turn, step, mid, content, usage=True, interrupted=False):
    d = {'turn': turn, 'step': step,
         'message': {'role': 'assistant', 'content': content, 'source': {'kind': 'model', 'provider': 'p', 'model': 'm'}, 'id': mid},
         'stream': []}
    if usage:
        d['usage'] = {'inputTokens': 10, 'outputTokens': 5, 'totalTokens': 15}
    if interrupted:
        d['interrupted'] = True
    return event('assistant/message', d, 'append')


def text_stream(s, idx, parts):
    chunk(s, {'type': 'block-start', 'index': idx, 'blockType': 'text'})
    for p in parts:
        chunk(s, {'type': 'text-delta', 'index': idx, 'text': p})
    chunk(s, {'type': 'block-end', 'index': idx, 'block': {'type': 'text', 'text': ''.join(parts)}})


def finish(s, reason='stop'):
    chunk(s, {'type': 'usage', 'usage': {'inputTokens': 10, 'outputTokens': 5, 'totalTokens': 15}})
    chunk(s, {'type': 'finish', 'reason': {'kind': reason}})


def start_turn(turn, mid, t, human=True):
    msg = user_msg(mid, t, 'user' if human else 'agent-instructions')
    splice('next-turn', 0, [msg])
    event('turn/start', {'turn': turn})
    splice('next-turn', 0, removed=1)
    event('step/start', {'turn': turn, 'step': 1})
    event('user/message', msg, 'append')


steps.append({'op': 'action', 'name': 'open'})
steps.append({'op': 'opened', 'generation': 1})
# open snapshot: one system message at the session start
seq[0] = 1
sys_event = {'type': 'event', 'event': {'type': 'system/message', 'seq': 1, 'time': tick(),
                                        'data': {'turn': 0, 'step': 0, 'message': {'role': 'system', 'content': text('You are a helpful assistant.'), 'id': 'sys-1'}},
                                        'surfaceOp': 'append'}}
frame({'type': 'snapshot', 'header': {'version': 4, 'id': 'session-synth', 'createdAt': 1, 'cwd': 'work', 'isSeeded': False,
                                      'delegationDepth': 0, 'agentPreset': 'default'},
       'cursor': 1, 'records': [sys_event], 'hasMore': False,
       'projections': {'asOfSeq': 1, 'values': {}}, 'assistantStream': {'revision': 0}})

# ---- turn 1: reasoning, text, a streamed tool call that settles, then an answer
start_turn(1, 'u1', 'List the files')
s = stream_start('attempt-1', 1, 1)
chunk(s, {'type': 'block-start', 'index': 0, 'blockType': 'reasoning'})
chunk(s, {'type': 'reasoning-delta', 'index': 0, 'text': 'I should run '})
chunk(s, {'type': 'reasoning-delta', 'index': 0, 'text': 'a listing.'})
chunk(s, {'type': 'block-end', 'index': 0, 'block': {'type': 'reasoning', 'text': 'I should run a listing.'}})
text_stream(s, 1, ['Let me ', 'look.'])
chunk(s, {'type': 'block-start', 'index': 2, 'blockType': 'tool-call'})
chunk(s, {'type': 'tool-call-delta', 'index': 2, 'id': 'call-1', 'name': 'bash', 'argumentsDelta': '{"command":"ls'})
chunk(s, {'type': 'tool-call-delta', 'index': 2, 'id': 'call-1', 'argumentsDelta': ' -la","timeout":3'})
chunk(s, {'type': 'tool-call-delta', 'index': 2, 'id': 'call-1', 'argumentsDelta': '0}'})
args1 = '{"command":"ls -la","timeout":30}'
chunk(s, {'type': 'block-end', 'index': 2, 'block': {'type': 'tool-call', 'id': 'call-1', 'name': 'bash', 'arguments': args1}})
finish(s, 'toolUse')
assistant_message(1, 1, 'a1', [
    {'type': 'reasoning', 'text': 'I should run a listing.'},
    {'type': 'text', 'text': 'Let me look.'},
    {'type': 'tool-call', 'id': 'call-1', 'name': 'bash', 'arguments': args1}])
stream_end(s, {'kind': 'committed', 'eventType': 'assistant/message', 'seq': seq[0]})
event('tool/call', {'turn': 1, 'step': 1, 'callId': 'call-1', 'name': 'bash', 'arguments': args1})
event('tool/result', {'turn': 1, 'step': 1,
                      'message': {'role': 'tool', 'source': {'kind': 'tool', 'callId': 'call-1'}, 'toolCallId': 'call-1',
                                  'content': text('a.txt b.txt'), 'isError': False, 'id': 'tr1'},
                      'meta': {'cwd': 'work'}}, 'append', {'sourceEventSeqs': [seq[0] - 1]})
event('step/end', {'turn': 1, 'step': 1})
event('step/start', {'turn': 1, 'step': 2})
s = stream_start('attempt-2', 1, 2)
text_stream(s, 0, ['Two ', 'files.'])
finish(s)
assistant_message(1, 2, 'a2', text('Two files.'))
stream_end(s, {'kind': 'committed', 'eventType': 'assistant/message', 'seq': seq[0]})
event('step/end', {'turn': 1, 'step': 2})
event('turn/end', {'turn': 1, 'reason': {'kind': 'completed'}})

# ---- turn 2: cancelled mid-stream, no settled message (interruption fallback)
start_turn(2, 'u2', 'Read a big file')
s = stream_start('attempt-3', 2, 1)
text_stream(s, 0, ['Reading', ' now'])
chunk(s, {'type': 'block-start', 'index': 1, 'blockType': 'tool-call'})
chunk(s, {'type': 'tool-call-delta', 'index': 1, 'id': 'call-2', 'name': 'read', 'argumentsDelta': '{"path":"big'})
event('step/end', {'turn': 2, 'step': 1})
event('turn/end', {'turn': 2, 'reason': {'kind': 'aborted', 'reason': {'kind': 'user'}}})
stream_end(s, {'kind': 'abandoned'})  # the host retires the cancelled attempt after the turn closed

# ---- turn 3: a steering message admitted into a running turn, then a failed turn
start_turn(3, 'u3', 'Count the lines')
s = stream_start('attempt-4', 3, 1)
chunk(s, {'type': 'block-start', 'index': 0, 'blockType': 'tool-call'})
chunk(s, {'type': 'tool-call-delta', 'index': 0, 'id': 'call-3', 'name': 'bash', 'argumentsDelta': '{"command":"wc -l a.txt"}'})
args3 = '{"command":"wc -l a.txt"}'
chunk(s, {'type': 'block-end', 'index': 0, 'block': {'type': 'tool-call', 'id': 'call-3', 'name': 'bash', 'arguments': args3}})
finish(s, 'toolUse')
assistant_message(3, 1, 'a4', [{'type': 'tool-call', 'id': 'call-3', 'name': 'bash', 'arguments': args3}])
stream_end(s, {'kind': 'committed', 'eventType': 'assistant/message', 'seq': seq[0]})
event('tool/call', {'turn': 3, 'step': 1, 'callId': 'call-3', 'name': 'bash', 'arguments': args3})
steer = user_msg('u3b', 'Also count words')
splice('next-step', 0, [steer])
event('tool/result', {'turn': 3, 'step': 1,
                      'message': {'role': 'tool', 'source': {'kind': 'tool', 'callId': 'call-3'}, 'toolCallId': 'call-3',
                                  'content': text('3 a.txt'), 'isError': True, 'id': 'tr3'},
                      'error': {'name': 'ToolError', 'code': 'nonzero', 'reason': 'exit 1'}}, 'append', {'sourceEventSeqs': [seq[0] - 2]})
event('step/end', {'turn': 3, 'step': 1})
event('step/start', {'turn': 3, 'step': 2})
splice('next-step', 0, removed=1)
event('user/message', steer, 'append')
s = stream_start('attempt-5', 3, 2)
text_stream(s, 0, ['Counting words'])
stream_end(s, {'kind': 'abandoned'})
event('step/end', {'turn': 3, 'step': 2})
event('turn/end', {'turn': 3, 'reason': {'kind': 'error', 'error': {'code': 'RATE_LIMIT', 'message': 'slow down'}}})

# ---- turn 4: woken by a non-human notice, ends at the token cap
start_turn(4, 'n4', 'Notice: file changed', human=False)
s = stream_start('attempt-6', 4, 1)
text_stream(s, 0, ['A long ', 'answer that is cut'])
finish(s, 'length')
assistant_message(4, 1, 'a6', text('A long answer that is cut'))
stream_end(s, {'kind': 'committed', 'eventType': 'assistant/message', 'seq': seq[0]})
event('step/end', {'turn': 4, 'step': 1})
event('turn/end', {'turn': 4, 'reason': {'kind': 'max-tokens'}})

# ---- turn 5: a model retry within one step, then success
start_turn(5, 'u5', 'Say hi')
s = stream_start('attempt-7', 5, 1)
text_stream(s, 0, ['Hi th'])
stream_end(s, {'kind': 'abandoned'})
event('llm/retry', {'turn': 5, 'step': 1, 'attempt': 1, 'delayMs': 1000, 'error': {'code': 'OVERLOADED', 'message': 'busy'}})
s = stream_start('attempt-8', 5, 1)
text_stream(s, 0, ['Hi there'])
finish(s)
assistant_message(5, 1, 'a8', text('Hi there'))
stream_end(s, {'kind': 'committed', 'eventType': 'assistant/message', 'seq': seq[0]})
event('step/end', {'turn': 5, 'step': 1})
event('turn/end', {'turn': 5, 'reason': {'kind': 'completed'}})

out = {
    'format': 'dsh-session-vector/1',
    'description': 'Synthetic edge-case trace (see tool/vectors/synth_edge_trace.py): live tool-call streaming, '
                   'interruption, steering, failure, max-tokens, non-human trigger, model retry. `expected*` come '
                   'from dsh\'s own TypeScript engine.',
    'hostVersion': '0.2.1-rc.2',
    'openOptions': {'maxMessages': 500, 'turnWindow': {'minMessages': 50, 'minTurns': 2}},
    'steps': steps,
}
with open(sys.argv[1], 'w', encoding='utf-8') as handle:
    handle.write(json.dumps(out, indent=1) + '\n')
print('synth_edge_trace: %d steps' % len(steps))
