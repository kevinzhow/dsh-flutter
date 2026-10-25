import 'dart:convert';
import 'dart:io';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

import 'support/chat_projection.dart';

EventEntry ev(
  num seq,
  String type,
  Map<String, Object?> data, {
  bool transient = false,
  Object? surface,
}) => EventEntry({
  'type': type,
  'seq': seq,
  'time': 1000 + seq,
  'data': data,
  'surfaceOp': ?surface,
}, transient: transient);

EventEntry userMsg(num seq, String id, String text) => ev(seq, 'user/message', {
  'content': [
    {'type': 'text', 'text': text},
  ],
  'source': {'kind': 'user'},
  'role': 'user',
  'id': id,
}, surface: 'append');

EventEntry assistantMsg(num seq, int turn, String text) =>
    ev(seq, 'assistant/message', {
      'turn': turn,
      'step': 1,
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': text},
        ],
        'id': 'm$seq',
      },
      'stream': <Object?>[],
    }, surface: 'append');

List<EventEntry> turn(int n, int base) => [
  ev(base, 'turn/start', {'turn': n}),
  ev(base + 1, 'step/start', {'turn': n, 'step': 1}),
  userMsg(base + 2, 'u$n', 'question $n'),
  assistantMsg(base + 3, n, 'answer $n'),
  ev(base + 4, 'step/end', {'turn': n, 'step': 1}),
  ev(base + 5, 'turn/end', {
    'turn': n,
    'reason': {'kind': 'completed'},
  }),
];

ConversationBinding bind(MutableEventSource source) =>
    ConversationBinding.chat(source, scheduler: FlushScheduler.immediate());

Map<String, Object?> view(ConversationBinding b) =>
    projectChat(b.chat.value, b.openTurn.value, b.todoHistory.value);

void main() {
  group('registry', () {
    test('duplicate definitions, duplicate fallback and fallback without target fail', () {
      final r = defaultChatRegistries();
      expect(
        () => r.events.register(const MessageDefinition()),
        throwsA(isA<ConversationRegistryError>()),
      );
      expect(
        () => r.events.registerFallback(const UnknownSurfaceDefinition()),
        throwsA(isA<ConversationRegistryError>()),
      );
      expect(
        () => r.views.register(ChatViewDefinition()),
        throwsA(isA<ConversationRegistryError>()),
      );
    });

    test('definitions route by event type in registration order', () {
      final r = defaultChatRegistries();
      final kinds = r.events
          .forEvent('tool/result')
          .map((d) => d.kind)
          .toList();
      expect(kinds, containsAll(['tool-call', 'turn-tail', 'inbox-next-step']));
      expect(
        kinds.indexOf('inbox-next-step'),
        lessThan(kinds.indexOf('tool-call')),
      );
      expect(
        r.events.forEvent('no/such/event').map((d) => d.kind),
        isNot(contains('tool-call')),
      );
    });
  });

  group('window paths agree with a full replace', () {
    final all = [for (var n = 0; n < 4; n++) ...turn(n + 1, 1 + n * 10)];

    test('append one by one equals replace of the whole window', () {
      final live = MutableEventSource()..replace(all.take(2).toList(), false);
      final a = bind(live);
      for (final e in all.skip(2)) {
        live.append(e);
      }
      final whole = MutableEventSource()..replace(all, false);
      final b = bind(whole);
      expect(view(a), view(b));
    });

    test(
      'prepending older pages equals replace; update-only tails stay pending',
      () {
        final tail = all.skip(14).toList();
        final live = MutableEventSource()..replace(tail, true);
        final a = bind(live);
        // the tail starts mid-turn: assistant message and the turn end only
        expect(
          a.chat.value.visibleNodes.any((n) => n.kind == 'assistant-step'),
          isTrue,
        );
        for (var start = 14; start > 0; start -= 7) {
          final from = start - 7 < 0 ? 0 : start - 7;
          live.prepend(all.sublist(from, start), from > 0);
        }
        final whole = MutableEventSource()..replace(all, false);
        final b = bind(whole);
        final va = view(a);
        final vb = view(b);
        expect(va['nodes'], vb['nodes']);
        expect(va['timeline'], vb['timeline']);
      },
    );

    test(
      'a durable settlement retires its live rows without changing the nodes',
      () {
        final live = MutableEventSource()
          ..replace([
            ev(1, 'turn/start', {'turn': 1}),
            ev(2, 'step/start', {'turn': 1, 'step': 1}),
            userMsg(3, 'u', 'hi'),
          ], false);
        final b = bind(live);
        live.append(
          ev(3.5, 'assistant/live-chunk', {
            'attemptId': 'a',
            'turn': 1,
            'step': 1,
            'chunk': {'type': 'text-delta', 'index': 0, 'text': 'par'},
          }, transient: true),
        );
        var step = b.chat.value.visibleNodes.last;
        expect((step.data! as AssistantData).status, 'running');
        live.settleAssistant('a', assistantMsg(4, 1, 'partial answer'));
        step = b.chat.value.visibleNodes.last;
        expect((step.data! as AssistantData).status, 'settled');
        expect(
          ((step.data! as AssistantData).blocks.single as TextBlock).text,
          'partial answer',
        );
        expect(
          b.chat.value.visibleNodes.where((n) => n.kind == 'assistant-step'),
          hasLength(1),
        );
      },
    );

    test(
      'the edge trace ends in the same nodes whether replayed or replaced',
      () async {
        final fixture = jsonDecode(
          File('test/fixtures/conversation_edge_vector.json')
              .readAsStringSync(),
        ) as Map<String, Object?>;
        late Session session;
        late ConversationBinding live;
        await replayFixture(
          fixture,
          attach: (s) {
            session = s;
            live = bind(s.eventSource);
          },
        );
        final entries = session.eventSource.window.entries
            .where((e) => !e.transient)
            .toList();
        final whole = MutableEventSource()..replace(entries, false);
        final replaced = bind(whole);
        expect(view(live)['nodes'], view(replaced)['nodes']);
      },
    );
  });

  group('engine rules', () {
    test('an update whose start is outside the window stays pending', () {
      final source = MutableEventSource()
        ..replace([
          ev(5, 'step/end', {'turn': 3, 'step': 1}),
          ev(6, 'tool/result', {
            'turn': 3,
            'step': 1,
            'message': {
              'role': 'tool',
              'source': {'kind': 'tool', 'callId': 'c1'},
              'content': <Object?>[],
              'id': 't',
            },
          }, surface: 'append'),
        ], true);
      final b = bind(source);
      // The result alone still builds a settled row (terminal events carry
      // fallback state); the step boundary alone builds nothing.
      expect(b.chat.value.visibleNodes.map((n) => n.kind), [
        'turn-process',
        'tool-call',
      ]);
      source.prepend([
        ev(4, 'tool/call', {
          'turn': 3,
          'step': 1,
          'callId': 'c1',
          'name': 'bash',
          'arguments': '{}',
        }),
      ], true);
      final tool =
          b.chat.value.visibleNodes
                  .singleWhere((n) => n.kind == 'tool-call')
                  .data!
              as ToolData;
      expect((tool.root as ToolResult).name, 'bash');
    });

    test('a user/message of a compaction checkpoint is not a chat row', () {
      final source = MutableEventSource()
        ..replace([
          ev(1, 'turn/start', {'turn': 1}),
          ev(
            2,
            'user/message',
            {
              'content': [
                {'type': 'text', 'text': 'summary'},
              ],
              'source': {'kind': 'compact-checkpoint'},
              'role': 'user',
              'id': 'c1',
            },
            surface: {'op': 'replace', 'startSeq': 1, 'endSeq': 1},
          ),
        ], false);
      expect(bind(source).chat.value.visibleNodes.map((n) => n.kind), [
        'turn-process',
      ]);
    });

    test('non-user context messages are hidden rows', () {
      final source = MutableEventSource()
        ..replace([
          ev(1, 'turn/start', {'turn': 1}),
          ev(2, 'step/start', {'turn': 1, 'step': 1}),
          ev(3, 'user/message', {
            'content': [
              {'type': 'text', 'text': 'x'},
            ],
            'source': {'kind': 'skill-invocation', 'name': 'pdf'},
            'role': 'user',
            'id': 'c1',
          }, surface: 'append'),
        ], false);
      final b = bind(source);
      expect(b.chat.value.visibleNodes.map((n) => n.kind), ['turn-process']);
      expect(
        b.chat.value.nodes.values.where((n) => n.kind == 'context'),
        hasLength(1),
      );
    });

    test('the open turn follows turn/start and turn/end', () {
      final source = MutableEventSource()
        ..replace([
          ev(1, 'turn/start', {'turn': 1}),
        ], false);
      final b = bind(source);
      expect(b.openTurn.value, 1);
      source.append(
        ev(2, 'turn/end', {
          'turn': 1,
          'reason': {'kind': 'completed'},
        }),
      );
      expect(b.openTurn.value, isNull);
    });
  });

  group('ordering helper', () {
    test(
      'localeCompare orders like ICU for the ASCII keys the engine builds',
      () {
        final keys = [
          '9:tool-call9',
          '13:assistant-step1:1',
          '9:tool-call10',
          '9:tool-call-x',
          '9:Tool-call1',
        ];
        keys.sort(localeCompare);
        expect(keys, [
          '13:assistant-step1:1',
          '9:tool-call-x',
          '9:Tool-call1',
          '9:tool-call10',
          '9:tool-call9',
        ]);
        expect(localeCompare('a', 'A'), lessThan(0));
        expect(localeCompare('a', 'a'), 0);
      },
    );
  });

  group('locations', () {
    test('seqText prints like JavaScript String(seq)', () {
      expect(seqText(167), '167');
      expect(seqText(3.5), '3.5');
      expect(seqText(166.0), '166');
    });
  });
}
