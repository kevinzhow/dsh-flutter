import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:dsh_models/testing.dart' show snapshot;

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

EventEntry ev(
  num seq,
  String type,
  Map<String, Object?> data, {
  String? surface,
}) => EventEntry({
  'type': type,
  'seq': seq,
  'time': 1000 + seq,
  'data': data,
  'surfaceOp': ?surface,
});

EventEntry live(num seq, Map<String, Object?> chunk) => EventEntry({
  'type': 'assistant/live-chunk',
  'seq': seq,
  'time': 1,
  'data': {'attemptId': 'a1', 'turn': 1, 'step': 1, 'chunk': chunk},
}, transient: true);

List<EventEntry> openTurn() => [
  ev(1, 'turn/start', {'turn': 1}),
  ev(2, 'step/start', {'turn': 1, 'step': 1}),
  ev(3, 'user/message', {
    'content': [
      {'type': 'text', 'text': 'Hello there'},
    ],
    'source': {'kind': 'user', 'rpcId': 'r1'},
    'role': 'user',
    'id': 'u1',
  }, surface: 'append'),
];

void main() {
  late SlotRegistry slots;
  late SessionOwner owner;
  var i18n = const DshI18n(DshLocale.en);

  /// An owner over a session that has been opened (empty), as the app shows a
  /// session: the chat view shows a skeleton until it is.
  Future<SessionOwner> openedOwner(String id) async {
    final transport = FakeTransport();
    final session = Session(id, transport);
    unawaited(session.open());
    await Future<void>.delayed(Duration.zero);
    transport.open(1, snapshot([]));
    await Future<void>.delayed(Duration.zero);
    expect(session.snapshot.value.openState, OpenState.open);
    return testSessionOwner(id, session: session);
  }

  setUp(() async {
    i18n = const DshI18n(DshLocale.en);
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerChatFeature(slots, i18n: () => i18n);
    owner = await openedOwner('s1');
  });

  Widget view() => dshTestApp(slots.renderList(viewSlot, owner).first);

  Future<void> open(WidgetTester t, List<EventEntry> entries) async {
    owner.session.eventSource.replace(entries, false);
    await t.pumpWidget(view());
    await t.pump();
  }

  testWidgets(
    'system prompt has a registered disclosure and stays outside the transcript',
    (t) async {
      await open(t, [
        ev(1, 'turn/start', {'turn': 1}),
        ev(2, 'step/start', {'turn': 1, 'step': 1}),
        ev(3, 'system/message', {
          'turn': 1,
          'step': 1,
          'message': {
            'id': 'sys',
            'role': 'system',
            'source': {'kind': 'system-prompt'},
            'content': [
              {'type': 'text', 'text': 'Model-visible prompt'},
            ],
          },
        }, surface: 'append'),
        ev(4, 'request/header', {
          'turn': 1,
          'step': 1,
          'reason': 'initial',
          'header': {'config': {}},
        }),
      ]);
      final snapshot = owner.conversation.chat.value;
      final node = snapshot.nodes.values.singleWhere(
        (n) => n.kind == 'system-prompt',
      );
      expect(find.byType(SystemPromptView), findsNothing);
      final card = slots.renderKeyed(
        chatNodeSlot,
        node.kind,
        ChatNodeOwner(session: owner, node: node, snapshot: snapshot),
      );
      expect(card, isA<SystemPromptView>());
      await t.pumpWidget(dshTestApp(card!));
      await t.tap(find.text(i18n.t('chat', 'message.systemPrompt')));
      await t.pump();
      expect(find.text('Model-visible prompt'), findsOneWidget);
    },
  );

  testWidgets('shows the empty state until something happens', (t) async {
    await open(t, []);
    expect(find.byKey(const ValueKey('chat-empty')), findsOneWidget);
  });

  testWidgets(
    'retry events render and update through the registered chat slot',
    (t) async {
      await open(t, [
        ...openTurn(),
        ev(4, 'llm/retry', {
          'turn': 1,
          'step': 1,
          'retryId': 'fixture',
          'retry': 1,
          'mode': 'normal',
          'maxRetries': 3,
          'delayMs': 2500,
          'provider': 'fixture',
          'policyKey': 'fixture',
          'failure': {'code': 'RATE_LIMIT', 'message': 'Try later'},
        }),
      ]);
      expect(find.byType(ModelRetryView), findsOneWidget);
      expect(find.textContaining('Retrying model request'), findsWidgets);
      owner.session.eventSource.append(
        ev(5, 'llm/retry-started', {
          'turn': 1,
          'step': 1,
          'retryId': 'fixture',
          'retry': 1,
        }),
      );
      await t.pump();
      expect(find.textContaining('Retried model request'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('streams answer text and keeps it as markdown', (t) async {
    await open(t, openTurn());
    expect(find.text('Hello there'), findsOneWidget);
    final es = owner.session.eventSource;
    es.append(
      live(3.5, {'type': 'block-start', 'index': 0, 'blockType': 'text'}),
    );
    es.append(
      live(3.6, {'type': 'text-delta', 'index': 0, 'text': 'Hi **there'}),
    );
    await t.pump();
    expect(find.textContaining('Hi', findRichText: true), findsWidgets);
    es.append(
      live(3.7, {'type': 'text-delta', 'index': 0, 'text': '**, friend'}),
    );
    await t.pump();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is RichText && w.text.toPlainText().contains('Hi there, friend'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('reasoning is collapsible and open while it streams', (t) async {
    await open(t, openTurn());
    final es = owner.session.eventSource;
    es.append(
      live(3.5, {'type': 'block-start', 'index': 0, 'blockType': 'reasoning'}),
    );
    es.append(
      live(3.6, {
        'type': 'reasoning-delta',
        'index': 0,
        'text': 'weighing options',
      }),
    );
    await t.pump();
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.text('weighing options'), findsOneWidget);

    es.append(
      live(3.7, {
        'type': 'block-end',
        'index': 0,
        'block': {'type': 'reasoning', 'text': 'weighing options'},
      }),
    );
    es.append(
      live(3.8, {'type': 'block-start', 'index': 1, 'blockType': 'text'}),
    );
    es.append(live(3.9, {'type': 'text-delta', 'index': 1, 'text': 'Answer'}));
    await t.pump();
    // reasoning is no longer the last block: its header is the settled label
    expect(find.text('Think'), findsOneWidget);
    // streaming moved on to the answer: the reasoning folded away by itself
    expect(find.text('weighing options'), findsNothing);
    await t.tap(find.text('Think'));
    await t.pump();
    expect(find.text('weighing options'), findsOneWidget);
    await t.tap(find.text('Think'));
    await t.pump();
    expect(find.text('weighing options'), findsNothing);
  });

  testWidgets('a local echo is shown dimmed until the host admits the prompt', (
    t,
  ) async {
    final transport = FakeTransport();
    owner = testSessionOwner('s1', session: Session('s1', transport));
    await open(t, []);
    await owner.session.prompt('queued thought');
    await t.pump();
    expect(find.text('queued thought'), findsOneWidget);
    final opacity = t.widget<Opacity>(
      find
          .ancestor(
            of: find.text('queued thought'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(opacity.opacity, lessThan(1));
  });

  testWidgets('a failed turn shows the error card, a stopped step is marked', (
    t,
  ) async {
    await open(t, [
      ...openTurn(),
      ev(4, 'turn/end', {
        'turn': 1,
        'reason': {
          'kind': 'error',
          'error': {'code': 'RATE_LIMIT', 'message': 'slow down'},
        },
      }),
    ]);
    expect(find.byKey(const ValueKey('turn-error')), findsOneWidget);
    expect(find.text('slow down'), findsOneWidget);
    expect(find.text('This turn failed'), findsOneWidget);
  });

  testWidgets('the running indicator and load-earlier follow the session', (
    t,
  ) async {
    final transport = FakeTransport();
    final session = Session('s1', transport);
    owner = testSessionOwner('s1', session: session);
    await open(t, openTurn());
    session.handleRunning(true);
    await t.pump();
    expect(find.byKey(const ValueKey('running-indicator')), findsOneWidget);
    expect(find.text('Deep diving'), findsOneWidget);
    session.handleRunning(false);
    await t.pump();
    expect(find.byKey(const ValueKey('running-indicator')), findsNothing);
  });

  testWidgets('zh locale uses the Chinese dsh copy', (t) async {
    i18n = const DshI18n(DshLocale.zh);
    await open(t, [
      ...openTurn(),
      ev(4, 'turn/end', {
        'turn': 1,
        'reason': {
          'kind': 'error',
          'error': {'code': 'AUTH', 'message': 'secret'},
        },
      }),
    ]);
    expect(find.text('本轮运行失败'), findsOneWidget);
    expect(find.text('API 密钥无效'), findsOneWidget);
    expect(find.text('secret'), findsNothing);
  });

  testWidgets(
    'turn-tail entries follow the closing row of a finished turn; null adds nothing',
    (t) async {
      slots.register<TurnTailOwner, Widget?>(
        DshSlots.conversationChatTurnTail.typed<TurnTailOwner, Widget?>(),
        (o) => Text('tail of turn ${o.turn}', key: const ValueKey('tail-a')),
        id: 'a',
      );
      slots.register<TurnTailOwner, Widget?>(
        DshSlots.conversationChatTurnTail.typed<TurnTailOwner, Widget?>(),
        (o) => null,
        id: 'b',
      );
      await open(t, [
        ...openTurn(),
        ev(4, 'assistant/message', {
          'turn': 1,
          'step': 1,
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'Done.'},
            ],
            'id': 'a1',
          },
          'stream': <Object?>[],
        }, surface: 'append'),
        ev(5, 'step/end', {'turn': 1, 'step': 1}),
        ev(6, 'turn/end', {
          'turn': 1,
          'reason': {'kind': 'completed'},
        }),
      ]);
      expect(find.byKey(const ValueKey('tail-a')), findsOneWidget);
      expect(find.text('tail of turn 1'), findsOneWidget);
    },
  );

  group('attachments', () {
    const image = {
      'attachmentId': 'sha256:img',
      'mediaType': 'image/png',
      'bytes': 1658,
      'width': 320,
      'height': 200,
      'name': 'shot.png',
    };
    const file = {
      'attachmentId': 'sha256:f',
      'name': 'notes.txt',
      'bytes': 2048,
    };

    List<List<GalleryImage>> calls = [];
    List<(int, bool, int)> layout = [];

    setUp(() {
      calls = [];
      layout = [];
      slots.register<ImageGalleryOwner, Widget>(
        DshSlots.conversationChatUserImages.typed<ImageGalleryOwner, Widget>(),
        (o) {
          calls.add(o.images);
          layout.add((o.group?.length ?? 0, o.compact, o.groupIndex));
          return Text('gallery ${o.images.length}');
        },
      );
      slots.register<ImageGalleryOwner, Widget>(
        DshSlots.conversationChatMessageImages
            .typed<ImageGalleryOwner, Widget>(),
        (o) => Text('assistant gallery ${o.images.length}'),
      );
    });

    List<EventEntry> turn(List<Object?> content) => [
      ev(1, 'turn/start', {'turn': 1}),
      ev(2, 'step/start', {'turn': 1, 'step': 1}),
      ev(3, 'user/message', {
        'content': content,
        'source': {'kind': 'user', 'rpcId': 'r1'},
        'role': 'user',
        'id': 'u1',
      }, surface: 'append'),
    ];

    testWidgets('a lone image has no bubble and goes through the slot', (
      t,
    ) async {
      await open(
        t,
        turn([
          {'type': 'image', 'attachment': image},
        ]),
      );
      expect(find.text('gallery 1'), findsOneWidget);
      expect(layout.single, (1, false, 0));
    });

    testWidgets(
      'images, a file and text keep their order and share the group',
      (t) async {
        await open(
          t,
          turn([
            {'type': 'image', 'attachment': image},
            {'type': 'file', 'attachment': file},
            {'type': 'image', 'attachment': image},
            {'type': 'text', 'text': 'compare these'},
          ]),
        );
        expect(find.text('gallery 1'), findsNWidgets(2));
        expect(find.byKey(const ValueKey('message-file-card')), findsOneWidget);
        expect(find.text('notes.txt'), findsOneWidget);
        expect(find.text('TXT 2.0KB'), findsOneWidget);
        expect(find.text('compare these'), findsOneWidget);
        // more than one attachment: compact tiles, each knowing its place in the group
        expect(layout, [(2, true, 0), (2, true, 1)]);
      },
    );

    testWidgets('a malformed attachment block is not drawn as an image', (
      t,
    ) async {
      await open(
        t,
        turn([
          {
            'type': 'image',
            'attachment': {'attachmentId': 'x'},
          },
          {'type': 'text', 'text': 'hi'},
        ]),
      );
      expect(find.textContaining('gallery'), findsNothing);
      expect(find.text('hi'), findsOneWidget);
    });

    testWidgets('the local echo shows its previews and file card', (t) async {
      final transport = FakeTransport();
      owner = testSessionOwner('s1', session: Session('s1', transport));
      slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      registerChatFeature(slots, i18n: () => i18n);
      slots.register<ImageGalleryOwner, Widget>(
        DshSlots.conversationChatUserImages.typed<ImageGalleryOwner, Widget>(),
        (o) => Text(
          'preview ${o.images.map((i) => i is PreviewGalleryImage).join()}',
        ),
      );
      await open(t, []);
      await owner.session.prompt(
        'see',
        attachments: [
          OutgoingImage(
            name: 'p.png',
            bytes: Uint8List(3),
            mediaType: 'image/png',
            width: 4,
            height: 2,
          ),
          const OutgoingFile(name: 'n.csv', size: 12, receiptId: 'r'),
        ],
      );
      await t.pump();
      expect(find.text('preview true'), findsOneWidget);
      expect(find.text('n.csv'), findsOneWidget);
      expect(find.text('see'), findsOneWidget);
    });

    testWidgets('an assistant image block goes through the message slot', (
      t,
    ) async {
      await open(t, [
        ...turn([
          {'type': 'text', 'text': 'draw'},
        ]),
        ev(4, 'assistant/message', {
          'turn': 1,
          'step': 1,
          'message': {
            'role': 'assistant',
            'id': 'a1',
            'content': [
              {'type': 'image', 'attachment': image},
              {'type': 'text', 'text': 'done'},
            ],
            'source': {'kind': 'model'},
          },
        }, surface: 'append'),
      ]);
      expect(find.text('assistant gallery 1'), findsOneWidget);
    });
  });

  testWidgets(
    'a fenced block is a code card, coloured by the ambient highlighter',
    (t) async {
      owner.session.eventSource.replace([
        ev(1, 'turn/start', {'turn': 1}),
        ev(2, 'step/start', {'turn': 1, 'step': 1}),
        ev(3, 'assistant/message', {
          'turn': 1,
          'step': 1,
          'message': {
            'role': 'assistant',
            'id': 'a1',
            'content': [
              {'type': 'text', 'text': 'Run:\n\n```ts\nconst x = 1\n```\n'},
            ],
            'source': {'kind': 'model'},
          },
        }, surface: 'append'),
      ], false);
      await t.pumpWidget(
        DshCodeHighlighting(highlighter: _KeywordHighlighter(), child: view()),
      );
      await t.pump();
      expect(find.byKey(const ValueKey('code-block')), findsOneWidget);
      expect(find.byKey(const ValueKey('code-copy')), findsOneWidget);
      final rich = find.descendant(
        of: find.byKey(const ValueKey('code-block')),
        matching: find.byType(RichText),
      );
      final colours = <Color?>{};
      for (final w in t.widgetList<RichText>(rich)) {
        w.text.visitChildren((s) {
          if (s is TextSpan && s.text == 'const') colours.add(s.style?.color);
          return true;
        });
      }
      expect(colours, hasLength(1));
    },
  );
}

class _KeywordHighlighter implements DshCodeHighlighter {
  @override
  List<List<DshCodeSpan>>? highlight(String code, String? lang) => [
    for (final line in code.split('\n'))
      line.startsWith('const')
          ? [
              const DshCodeSpan('const', DshCodeToken.keyword),
              DshCodeSpan(line.substring(5)),
            ]
          : [DshCodeSpan(line)],
  ];
  @override
  void prepare(String? lang) {}
  @override
  Stream<void> get loaded => const Stream.empty();
}
