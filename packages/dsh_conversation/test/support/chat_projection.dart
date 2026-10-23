import 'dart:convert';

import 'package:dsh_conversation/dsh_conversation.dart';

/// The language-neutral projection of a chat snapshot that the TS side writes
/// into `expectedChat` (tool/vectors/ts/chat_glue.mjs `projectChat`). Both sides
/// must produce the same JSON.
Map<String, Object?> projectChat(ChatSnapshot snapshot, int? openTurn) {
  final nodes = [
    for (final n in snapshot.visibleNodes)
      {
        'kind': n.kind,
        'id': n.id,
        'anchorSeq': n.anchorSeq,
        'groupTree': n.groupTree,
        'location': switch (n.location) {
          SessionLocation() => 'session',
          UnresolvedLocation() => 'unresolved',
          TurnScopedLocation() => 'turn',
          StepScopedLocation() => 'step',
        },
        'turn': locationTurn(n.location),
        'step': locationStep(n.location),
        'data': _data(n),
      },
  ];
  final timeline = [
    for (final turn in snapshot.timeline.turnOrder)
      () {
        final l = snapshot.timeline.turns[turn]!;
        return {
          'turn': turn,
          'status': l.status.name,
          'startSeq': l.start?.seq,
          'endSeq': l.end?.seq,
          'steps': [
            for (final s in l.steps)
              {
                'step': s.step,
                'status': s.status.name,
                'startSeq': s.start?.seq,
                'endSeq': s.end?.seq,
              },
          ],
        };
      }(),
  ];
  return _canon({
    'nodes': nodes,
    'timeline': timeline,
    'nodeCount': snapshot.nodes.values
        .where((n) => n.kind != 'system-prompt')
        .length,
    'openTurn': openTurn,
  });
}

Map<String, Object?> _canon(Map<String, Object?> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, Object?>;

List<Object?> _block(AssistantBlock b) => switch (b) {
  TextBlock(:final text) => ['text', text],
  ReasoningBlock(:final text) => ['reasoning', text],
  ToolCallRefBlock() => ['tool-call', b.callId, b.name, b.argsRaw],
  ImageBlock() => ['image'],
  OtherBlock() => ['other'],
};

Map<String, Object?>? _final(AssistantMessage? n) => n == null
    ? null
    : {
        'seq': n.seq,
        'messageId': n.messageId,
        'time': n.time,
        'turn': n.turn,
        'step': n.step,
        'blocks': n.blocks.map(_block).toList(),
        'usage': n.usage,
        'interrupted': n.interrupted,
        'stepStartTime': n.stepStartTime,
        'firstTokenTime': n.firstTokenTime,
        'completedTime': n.completedTime,
      };

Map<String, Object?> _tool(ToolCall b) {
  final base = {
    'callId': b.callId,
    'parentCallId': b.parentCallId,
    'name': b.name,
  };
  switch (b) {
    case ToolResult():
      return {
        'state': 'settled',
        ...base,
        'args': b.args.raw,
        'callArgsRaw': b.callArgsRaw,
        'callTime': b.callTime,
        'seq': b.seq,
        'time': b.time,
        'isError': b.isError,
        'error': b.error,
        'content': b.content,
        'meta': b.meta,
        'subCalls': b.subCalls.map(_tool).toList(),
      };
    case PreparingToolCall():
      return {
        'state': 'preparing',
        ...base,
        'args': b.args.raw,
        'turn': b.turn,
        'step': b.step,
        'time': b.time,
        'subCalls': b.subCalls.map(_tool).toList(),
      };
    case StartedToolCall():
      return {
        'state': 'started',
        ...base,
        'args': b.args.raw,
        'argsRaw': b.argsRaw,
        'turn': b.turn,
        'step': b.step,
        'time': b.time,
        'subCalls': b.subCalls.map(_tool).toList(),
      };
  }
}

Object? _data(ViewNode node) {
  final d = node.data;
  switch (node.kind) {
    case 'user' || 'steering' || 'context' || 'turn-trigger':
      final m = d! as MessageData;
      return {
        'kind': m.kind,
        'seq': m.seq,
        'time': m.time,
        'content': m.content,
        'source': m.source,
        'messageId': m.kind == 'steering' ? m.messageId : null,
        'producer': m.producerRole == null
            ? null
            : [m.producerRole, m.producerLabel],
        'form': m.form,
        'waking': m.waking,
      };
    case 'assistant-step':
      final a = d! as AssistantData;
      return {
        'status': a.status,
        'turn': a.turn,
        'step': a.step,
        'time': a.time,
        'blocks': a.blocks.map(_block).toList(),
        'usage': a.usage,
        'final': _final(a.finalNode),
      };
    case 'tool-call':
      return _tool((d! as ToolData).root);
    case 'turn-tail':
      final t = d! as TurnTailData;
      return {
        'turn': t.turn,
        'seq': t.seq,
        'time': t.time,
        'closingSeq': t.closing?.finalNode?.seq,
        'branchUnavailable': t.branchUnavailable,
      };
    case 'turn-error':
      final e = d! as TurnErrorData;
      return {
        'seq': e.seq,
        'time': e.time,
        'turn': e.turn,
        'step': e.step,
        'message': e.message,
        'code': e.code,
      };
    case 'turn-max-tokens':
      final e = d! as TurnMaxTokensData;
      return {'seq': e.seq, 'time': e.time, 'turn': e.turn, 'step': e.step};
    case 'unknown':
      final u = d! as UnknownData;
      return {'seq': u.seq, 'time': u.time, 'type': u.type};
  }
  throw StateError('chat projection: unhandled node kind ${node.kind}');
}
