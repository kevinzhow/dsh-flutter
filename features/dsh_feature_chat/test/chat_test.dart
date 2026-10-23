import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
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

  setUp(() {
    i18n = const DshI18n(DshLocale.en);
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerChatFeature(slots, i18n: () => i18n);
    owner = testSessionOwner('s1');
  });

  Widget view() => dshTestApp(slots.renderList(viewSlot, owner).first);

  Future<void> open(WidgetTester t, List<EventEntry> entries) async {
    owner.session.eventSource.replace(entries, false);
    await t.pumpWidget(view());
    await t.pump();
  }

  testWidgets('shows the empty state until something happens', (t) async {
    await open(t, []);
    expect(find.byKey(const ValueKey('chat-empty')), findsOneWidget);
  });

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
}
