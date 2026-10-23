import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

EventEntry ev(
  num seq,
  String type,
  Map<String, Object?> data, {
  bool transient = false,
}) => EventEntry({
  'type': type,
  'seq': seq,
  'time': 1,
  'data': data,
}, transient: transient);

EventWindow window(List<EventEntry> e) => EventWindow(
  entries: e,
  hasMore: false,
  revision: 1,
  change: WindowChangeKind.replace,
);

void main() {
  test('chat target builds user and assistant nodes, streaming text from live chunks', () {
    final snap = buildChatSnapshot(
      window([
        ev(1, 'user/message', {
          'source': {'kind': 'user'},
          'content': [
            {'type': 'text', 'text': 'q'},
          ],
        }),
        ev(2, 'user/message', {
          'source': {'kind': 'runtime-context'},
          'content': [
            {'type': 'text', 'text': 'noise'},
          ],
        }),
        ev(3, 'assistant/message', {
          'message': {
            'content': [
              {'type': 'text', 'text': 'a'},
            ],
          },
        }),
        ev(3.5, 'assistant/live-chunk', {
          'attemptId': 'x',
          'chunk': {'type': 'text-delta', 'text': 'str'},
        }, transient: true),
        ev(3.75, 'assistant/live-chunk', {
          'attemptId': 'x',
          'chunk': {'type': 'text-delta', 'text': 'eam'},
        }, transient: true),
      ]),
    );
    expect(snap.nodes.map((n) => n.key), [
      'user',
      'assistant-step',
      'assistant-step',
    ]);
    expect(snap.nodes[0].data['text'], 'q');
    expect(snap.nodes[1].data['text'], 'a');
    expect(snap.nodes[2].data['text'], 'stream');
    expect(snap.nodes[2].streaming, isTrue);
  });

  test(
    'registry rejects a duplicate event definition and a duplicate target',
    () {
      final r = defaultConversationRegistry();
      expect(
        () => r.defineEvent(
          const EventDefinition(
            target: chatTarget,
            eventType: 'user/message',
            nodeKey: 'user',
          ),
        ),
        throwsA(isA<ConversationRegistryError>()),
      );
      expect(
        () => r.registerTarget(chatTarget, buildChatSnapshot),
        throwsA(isA<ConversationRegistryError>()),
      );
      expect(
        () => r.snapshot(trajectoryTarget, EventWindow.empty),
        throwsA(isA<ConversationRegistryError>()),
      );
      expect(r.definitionsFor(chatTarget), hasLength(3));
    },
  );
}
