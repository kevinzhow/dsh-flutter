"""Write the synthetic `plan_todo_vector.json` behaviour-vector fixture.

A hand-authored trace (every string generic) of what the plan and todo surfaces derive on the client: submitted-plan
nodes from native and PTC `exit_plan_mode` calls (a malformed one and one without a heading are ignored), the todo
write index and each todo call's predecessor list (initial call, update, call after a rejected write, PTC child).
The expected snapshots are NOT written here: run `gen_expected.py --write` on the output so dsh's own TypeScript
engine produces them.

    synth_plan_todo_trace.py OUT.json
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


def todos(*items):
    return json.dumps({'todos': [{'content': c, 'status': s} for c, s in items]})


# ---- turn 1: the first list, then an update to it
start_turn(1, 'u1', 'Plan the release')
a1 = todos(('Write notes', 'in_progress'), ('Tag release', 'pending'))
tool_round(1, 1, 'todo-1', 'todo_write', a1, 'ok', 'tr1')
event('todo/write', {'todos': [{'content': 'Write notes', 'status': 'in_progress'}, {'content': 'Tag release', 'status': 'pending'}]})
a2 = todos(('Write notes', 'completed'), ('Tag release', 'in_progress'), ('Announce', 'pending'))
tool_round(1, 1, 'todo-2', 'todo_write', a2, 'ok', 'tr2')
event('todo/write', {'todos': [{'content': 'Write notes', 'status': 'completed'}, {'content': 'Tag release', 'status': 'in_progress'}, {'content': 'Announce', 'status': 'pending'}]})
event('step/end', {'turn': 1, 'step': 1})
event('turn/end', {'turn': 1, 'reason': {'kind': 'completed'}})

# ---- turn 2: plans. A good plan, one with malformed JSON, one without a heading, a PTC dispatch of a plan
start_turn(2, 'u2', 'Draft the plan')
plan_a = json.dumps({'plan': '# Ship the release\n\n1. Write notes\n2. Tag it\n'})
tool_round(2, 1, 'plan-1', 'exit_plan_mode', plan_a, 'approved', 'tr3')
tool_round(2, 1, 'plan-bad-json', 'exit_plan_mode', '{"plan": "# Broken', 'rejected', 'tr4', is_error=True)
tool_round(2, 1, 'plan-no-heading', 'exit_plan_mode', json.dumps({'plan': 'No heading here'}), 'ok', 'tr5')
event('tool/ptc-dispatch-start', {'turn': 2, 'step': 1, 'parentCallId': 'run-1', 'subCallId': 'ptc-plan', 'name': 'exit_plan_mode',
                                  'arguments': {'plan': '# Second plan\n\nBody.'}})
event('tool/ptc-dispatch', {'turn': 2, 'step': 1, 'parentCallId': 'run-1', 'subCallId': 'ptc-plan', 'name': 'exit_plan_mode',
                            'arguments': {'plan': '# Second plan\n\nBody.'}, 'result': {'content': text('ok'), 'isError': False}})
event('tool/ptc-dispatch-start', {'turn': 2, 'step': 1, 'parentCallId': 'run-1', 'subCallId': 'ptc-todo', 'name': 'todo_write',
                                  'arguments': {'todos': [{'content': 'Announce', 'status': 'completed'}]}})
event('step/end', {'turn': 2, 'step': 1})
event('turn/end', {'turn': 2, 'reason': {'kind': 'completed'}})

out = {
    'format': 'dsh-session-vector/1',
    'description': 'Synthetic plan and todo trace (see tool/vectors/synth_plan_todo_trace.py): submitted plans from native and '
                   'PTC calls, todo write index and call predecessors. `expected*` come from dsh\'s own TypeScript engine.',
    'hostVersion': '0.2.1-rc.2',
    'openOptions': {'maxMessages': 500, 'turnWindow': {'minMessages': 50, 'minTurns': 2}},
    'steps': steps,
}
with open(sys.argv[1], 'w', encoding='utf-8') as handle:
    handle.write(json.dumps(out, indent=1) + '\n')
print('synth_plan_todo_trace: %d steps' % len(steps))
