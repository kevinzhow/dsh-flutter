"""Write the synthetic `attachment_vector.json` behaviour-vector fixture.

A hand-authored trace (every string generic) of messages that carry attachments: user messages with images, files and
text in different orders, a steering message with an image, an assistant message with an image block, and `read_image`
rounds (settled with an image block, and one that failed). Attachments reach the chat only as message content and tool
results, so the nodes must carry those blocks through untouched. The expected snapshots are NOT written here: run `gen_expected.py --write` on the output so dsh's own TypeScript
engine produces them.

    synth_attachment_trace.py OUT.json
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
seq[0] = 1
sys_event = {'type': 'event', 'event': {'type': 'system/message', 'seq': 1, 'time': tick(),
                                        'data': {'turn': 0, 'step': 0, 'message': {'role': 'system', 'content': text('You are a helpful assistant.'), 'id': 'sys-1'}},
                                        'surfaceOp': 'append'}}
frame({'type': 'snapshot', 'header': {'version': 4, 'id': 'session-synth', 'createdAt': 1, 'cwd': 'work', 'isSeeded': False,
                                      'delegationDepth': 0, 'agentPreset': 'default'},
       'cursor': 1, 'records': [sys_event], 'hasMore': False,
       'projections': {'asOfSeq': 1, 'values': {}}, 'assistantStream': {'revision': 0}})


def tool_round(turn, step, call_id, name, args, result_text, mid, is_error=False):
    event('tool/call', {'turn': turn, 'step': step, 'callId': call_id, 'name': name, 'arguments': args})
    event('tool/result', {'turn': turn, 'step': step,
                          'message': {'role': 'tool', 'source': {'kind': 'tool', 'callId': call_id}, 'toolCallId': call_id,
                                      'content': text(result_text), 'isError': is_error, 'id': mid}},
          'append', {'sourceEventSeqs': [seq[0]]})



def image(n, name='shot.png', w=320, h=200):
    return {'attachmentId': 'sha256:img%d' % n, 'mediaType': 'image/png', 'bytes': 1000 + n, 'width': w, 'height': h,
            'name': name}


def user_content(mid, blocks, kind='user'):
    return {'content': blocks, 'source': {'kind': kind, 'rpcId': 'rpc-' + mid} if kind == 'user' else {'kind': kind},
            'role': 'user', 'id': mid}


def start_turn_content(turn, mid, blocks):
    msg = user_content(mid, blocks)
    splice('next-turn', 0, [msg])
    event('turn/start', {'turn': turn})
    splice('next-turn', 0, removed=1)
    event('step/start', {'turn': turn, 'step': 1})
    event('user/message', msg, 'append')


# ---- turn 1: image, file and text in source order, then an answer that includes an image block
start_turn_content(1, 'u1', [
    {'type': 'image', 'attachment': image(1)},
    {'type': 'file', 'attachment': {'attachmentId': 'sha256:file1', 'name': 'notes (1).txt', 'bytes': 2048}},
    {'type': 'text', 'text': 'Compare these'},
    {'type': 'image', 'attachment': image(2, 'wide.png', 4000, 900)},
])
assistant_message(1, 1, 'a1', [{'type': 'image', 'attachment': image(3, 'chart.png')}, {'type': 'text', 'text': 'Done'}])
event('step/end', {'turn': 1, 'step': 1})
event('turn/end', {'turn': 1, 'reason': {'kind': 'completed'}})

# ---- turn 2: an attachment-only message and read_image rounds
start_turn_content(2, 'u2', [{'type': 'file', 'attachment': {'attachmentId': 'sha256:file2', 'name': 'data.csv', 'bytes': 0}}])
envelope = '<path>shot.png</path>\n<type>image</type>\n<content>\nimage 320x200\n</content>'
event('tool/call', {'turn': 2, 'step': 1, 'callId': 'img-1', 'name': 'read_image', 'arguments': json.dumps({'file_path': 'shot.png'})})
event('tool/result', {'turn': 2, 'step': 1,
                      'message': {'role': 'tool', 'source': {'kind': 'tool', 'callId': 'img-1'}, 'toolCallId': 'img-1',
                                  'content': [{'type': 'text', 'text': envelope}, {'type': 'image', 'attachment': image(4)}],
                                  'isError': False, 'id': 'tr1'},
                      'meta': {'path': '/work/shot.png'}},
      'append', {'sourceEventSeqs': [seq[0]]})
event('tool/call', {'turn': 2, 'step': 1, 'callId': 'img-2', 'name': 'read_image', 'arguments': json.dumps({'file_path': 'missing.png'})})
event('tool/result', {'turn': 2, 'step': 1,
                      'message': {'role': 'tool', 'source': {'kind': 'tool', 'callId': 'img-2'}, 'toolCallId': 'img-2',
                                  'content': text('no such file'), 'isError': True, 'id': 'tr2'}},
      'append', {'sourceEventSeqs': [seq[0]]})
event('step/end', {'turn': 2, 'step': 1})
event('turn/end', {'turn': 2, 'reason': {'kind': 'completed'}})

# ---- turn 3: a steering message that carries an image while the turn runs
start_turn(3, 'u3', 'Keep going')
splice('next-step', 0, [user_content('u4', [{'type': 'image', 'attachment': image(5, 'extra.png')},
                                           {'type': 'text', 'text': 'Also this one'}])])
event('step/end', {'turn': 3, 'step': 1})
event('step/start', {'turn': 3, 'step': 2})
splice('next-step', 0, removed=1)
event('user/message', user_content('u4', [{'type': 'image', 'attachment': image(5, 'extra.png')},
                                          {'type': 'text', 'text': 'Also this one'}]), 'append')
event('step/end', {'turn': 3, 'step': 2})
event('turn/end', {'turn': 3, 'reason': {'kind': 'completed'}})

out = {
    'format': 'dsh-session-vector/1',
    'description': 'Synthetic attachment trace (see tool/vectors/synth_attachment_trace.py): image and file blocks in user, '
                   'steering and assistant messages and read_image results. `expected*` come from dsh\'s own TypeScript engine.',
    'hostVersion': '0.2.1-rc.2',
    'openOptions': {'maxMessages': 500, 'turnWindow': {'minMessages': 50, 'minTurns': 2}},
    'steps': steps,
}
with open(sys.argv[1], 'w', encoding='utf-8') as handle:
    handle.write(json.dumps(out, indent=1) + '\n')
print('synth_attachment_trace: %d steps' % len(steps))
