import 'package:dsh_models/dsh_models.dart';

import 'registry.dart';
import 'types.dart';

/// Event definitions of the skeleton chat target (a deliberately tiny subset
/// of `ui-chat`: user messages and settled/streaming assistant text).
const chatEventDefinitions = [
  EventDefinition(
    target: chatTarget,
    eventType: 'user/message',
    nodeKey: 'user',
  ),
  EventDefinition(
    target: chatTarget,
    eventType: 'assistant/message',
    nodeKey: 'assistant-step',
  ),
  EventDefinition(
    target: chatTarget,
    eventType: 'assistant/live-chunk',
    nodeKey: 'assistant-step',
  ),
];

/// Skeleton chat builder: `user/message` with `source.kind == 'user'` becomes a
/// `user` node; a settled `assistant/message` becomes an `assistant-step` node
/// whose text is its text blocks; transient live chunks of an unsettled attempt
/// fold into one streaming `assistant-step`. Everything else (tools, plans,
/// subagents, ...) is the phase-1 port and is ignored here.
ConversationSnapshot buildChatSnapshot(EventWindow window) {
  final nodes = <ConversationNode>[];
  final live = <String, StringBuffer>{};
  final liveSeq = <String, (num, num)>{};
  for (final e in window.entries) {
    final data = e.data as Map<String, Object?>?;
    if (e.transient) {
      final chunk = data!['chunk'] as Map<String, Object?>;
      final attempt = data['attemptId'] as String;
      if (chunk['type'] == 'text-delta') {
        live.putIfAbsent(attempt, StringBuffer.new).write(chunk['text']);
        final range = liveSeq[attempt];
        liveSeq[attempt] = (range?.$1 ?? e.seq, e.seq);
      }
      continue;
    }
    switch (e.type) {
      case 'user/message':
        final source = data?['source'] as Map<String, Object?>?;
        if (source?['kind'] != 'user') continue;
        nodes.add(
          ConversationNode(
            key: 'user',
            id: 'user-${e.seq}',
            firstSeq: e.seq,
            lastSeq: e.seq,
            data: {'text': _text(data?['content'])},
          ),
        );
      case 'assistant/message':
        nodes.add(
          ConversationNode(
            key: 'assistant-step',
            id: 'assistant-${e.seq}',
            firstSeq: e.seq,
            lastSeq: e.seq,
            data: {
              'text': _text(
                (data?['message'] as Map<String, Object?>?)?['content'],
              ),
            },
          ),
        );
    }
  }
  for (final a in live.entries) {
    final range = liveSeq[a.key]!;
    nodes.add(
      ConversationNode(
        key: 'assistant-step',
        id: 'live-${a.key}',
        firstSeq: range.$1,
        lastSeq: range.$2,
        data: {'text': a.value.toString()},
        streaming: true,
      ),
    );
  }
  nodes.sort((a, b) => a.firstSeq.compareTo(b.firstSeq));
  return ConversationSnapshot(chatTarget, nodes);
}

String _text(Object? content) {
  if (content is! List) return '';
  return content
      .whereType<Map<String, Object?>>()
      .where((p) => p['type'] == 'text')
      .map((p) => '${p['text']}')
      .join();
}

/// A registry with the chat target installed.
ConversationRegistry defaultConversationRegistry() {
  final r = ConversationRegistry();
  chatEventDefinitions.forEach(r.defineEvent);
  r.registerTarget(chatTarget, buildChatSnapshot);
  return r;
}
