import 'dart:async';

import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_feature_chat/src/process_layout.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter_test/flutter_test.dart';

EventEntry event(
  int seq,
  String type,
  Map<String, Object?> data, {
  bool surface = false,
}) => EventEntry({
  'type': type,
  'seq': seq,
  'time': 1000 + seq * 1000,
  'data': data,
  if (surface) 'surfaceOp': 'append',
});
EventEntry reply(int seq, int step, String text, {bool reasoning = false}) =>
    event(seq, 'assistant/message', {
      'turn': 1,
      'step': step,
      'message': {
        'id': 'm-$seq',
        'content': [
          if (reasoning)
            {'type': 'reasoning', 'text': 'Private reasoning body'},
          {'type': 'text', 'text': text},
        ],
      },
    }, surface: true);
List<EventEntry> transcript({
  String reason = 'complete',
  bool interleaved = false,
}) => [
  event(1, 'turn/start', {'turn': 1}),
  event(2, 'step/start', {'turn': 1, 'step': 1}),
  event(3, 'user/message', {
    'turn': 1,
    'step': 1,
    'id': 'u',
    'source': {'kind': 'user'},
    'content': [
      {'type': 'text', 'text': 'User input'},
    ],
  }, surface: true),
  reply(4, 1, 'Intermediate progress', reasoning: true),
  if (interleaved)
    event(5, 'user/message', {
      'turn': 1,
      'step': 1,
      'id': 'u2',
      'source': {'kind': 'user'},
      'content': [
        {'type': 'text', 'text': 'Later input'},
      ],
    }, surface: true),
  event(6, 'step/end', {
    'turn': 1,
    'step': 1,
    'reason': {'kind': 'complete'},
  }),
  event(7, 'step/start', {'turn': 1, 'step': 2}),
  reply(8, 2, 'Final answer'),
  event(9, 'step/end', {
    'turn': 1,
    'step': 2,
    'reason': {'kind': 'complete'},
  }),
  event(10, 'turn/end', {
    'turn': 1,
    'reason': {'kind': reason},
  }),
];
void main() {
  final i18n = const DshI18n(DshLocale.en);
  late SessionOwner owner;
  late ChatPreferences prefs;
  late SlotRegistry slots;
  setUp(() async {
    final transport = FakeTransport();
    final session = Session('details', transport);
    unawaited(session.open());
    await Future<void>.delayed(Duration.zero);
    transport.open(1, snapshot([]));
    await Future<void>.delayed(Duration.zero);
    owner = testSessionOwner('details', session: session);
    prefs = ChatPreferences();
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerChatFeature(slots, i18n: () => i18n, preferences: prefs);
  });
  tearDown(() async {
    await owner.conversation.dispose();
    await owner.session.dispose();
    await prefs.dispose();
  });
  Future<void> open(WidgetTester t, List<EventEntry> events) async {
    owner.session.eventSource.replace(events, false);
    await t.pumpWidget(dshTestApp(slots.renderList(viewSlot, owner).first));
    await t.pump();
  }

  Finder control() => find.byKey(const ValueKey('turn-process-1'));
  testWidgets('completed process folds while final answer and input remain', (
    t,
  ) async {
    await open(t, transcript());
    expect(find.text('User input'), findsOneWidget);
    expect(find.text('Final answer'), findsOneWidget);
    expect(find.text('Intermediate progress'), findsNothing);
    expect(control(), findsOneWidget);
    await t.tap(control());
    await t.pump();
    expect(find.text('Intermediate progress'), findsOneWidget);
    await t.tap(control());
    await t.pump();
    expect(find.text('Intermediate progress'), findsNothing);
    expect(find.text('Final answer'), findsOneWidget);
  });
  testWidgets('failed and interleaved turns retain progress', (t) async {
    await open(t, transcript(reason: 'error'));
    expect(find.text('Intermediate progress'), findsOneWidget);
    await t.tap(control());
    await t.pump();
    expect(find.text('Intermediate progress'), findsOneWidget);
    owner.session.eventSource.replace(transcript(interleaved: true), false);
    await t.pump();
    expect(find.text('Intermediate progress'), findsOneWidget);
    expect(find.text('Later input'), findsOneWidget);
  });
  testWidgets(
    'mode changes preserve manual whole-turn choice; verbose stays open',
    (t) async {
      await open(t, transcript());
      await t.tap(control());
      await t.pump();
      prefs.setMode(TranscriptViewMode.compact);
      await t.pump();
      expect(find.text('Intermediate progress'), findsOneWidget);
      await t.tap(control());
      await t.pump();
      prefs.setMode(TranscriptViewMode.verbose);
      await t.pump();
      expect(find.text('Intermediate progress'), findsOneWidget);
      prefs.setMode(TranscriptViewMode.detailed);
      await t.pump();
      expect(find.text('Intermediate progress'), findsNothing);
    },
  );
  testWidgets('next-input keeps latest process until a fresh user exchange', (
    t,
  ) async {
    prefs.setTiming(CollapseTiming.nextInput);
    await open(t, transcript());
    expect(find.text('Intermediate progress'), findsOneWidget);
    owner.session.eventSource.append(event(11, 'turn/start', {'turn': 2}));
    await t.pump();
    expect(find.text('Intermediate progress'), findsOneWidget);
    owner.session.eventSource.append(
      event(12, 'step/start', {'turn': 2, 'step': 1}),
    );
    owner.session.eventSource.append(
      event(13, 'user/message', {
        'turn': 2,
        'step': 1,
        'id': 'next',
        'source': {'kind': 'user'},
        'content': [
          {'type': 'text', 'text': 'Next input'},
        ],
      }, surface: true),
    );
    await t.pump();
    expect(find.text('Intermediate progress'), findsNothing);
    expect(find.text('Final answer'), findsOneWidget);
  });
  testWidgets(
    'keyboard toggles keep control focus and outer collapse resets reasoning',
    (t) async {
      await open(t, transcript());
      await t.tap(control());
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(find.text('Intermediate progress'), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(find.text('Intermediate progress'), findsOneWidget);
      await t.tap(find.text('Analysis completed'));
      await t.pump();
      final thinking = find.byWidgetPredicate(
        (w) => w is DshDisclosureRow && w.title == 'Think',
      );
      await t.tap(thinking);
      await t.pump();
      expect(t.widget<DshDisclosureRow>(thinking).open, isTrue);
      prefs.setMode(TranscriptViewMode.verbose);
      await t.pump();
      expect(t.widget<DshDisclosureRow>(thinking).open, isTrue);
      prefs.setMode(TranscriptViewMode.detailed);
      await t.pump();
      expect(t.widget<DshDisclosureRow>(thinking).open, isTrue);
      await t.tap(control());
      await t.pump();
      await t.tap(control());
      await t.pump();
      await t.tap(find.text('Analysis completed'));
      await t.pump();
      expect(t.widget<DshDisclosureRow>(thinking).open, isFalse);
    },
  );

  testWidgets('automatic completion preserves a focused process member', (
    t,
  ) async {
    final events = transcript();
    await open(t, events.take(events.length - 1).toList());
    final thinking = find.byWidgetPredicate(
      (w) => w is DshDisclosureRow && w.title == 'Think',
    );
    Focus.of(
      t.element(find.descendant(of: thinking, matching: find.text('Think'))),
    ).requestFocus();
    await t.pump();
    owner.session.eventSource.append(events.last);
    await t.pump();
    expect(find.text('Intermediate progress'), findsOneWidget);
    expect(find.text('Final answer'), findsOneWidget);
  });

  testWidgets('settings selectors restore keyboard focus before publishing', (
    t,
  ) async {
    await t.pumpWidget(
      dshTestApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 480,
            child: WorkDetailsSettings(preferences: prefs, i18n: i18n),
          ),
        ),
      ),
    );
    final selector = find.byKey(const ValueKey('settings.transcript-selector'));
    await t.tap(selector);
    await t.pumpAndSettle();
    await t.tap(find.text(i18n.t('chat', 'settings.transcript.verbose')).last);
    await t.pumpAndSettle();
    expect(prefs.mode.value, TranscriptViewMode.verbose);
    expect(Focus.of(t.element(selector)).hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byType(DshMenuCard), findsOneWidget);
  });

  testWidgets(
    'opening a long process holds its header at the reading position',
    (t) async {
      final events = transcript();
      events[3] = reply(
        4,
        1,
        List.generate(30, (i) => 'Long progress paragraph $i').join('\n\n'),
        reasoning: true,
      );
      await open(t, events);
      final top = t.getTopLeft(control()).dy;
      await t.tap(control());
      await t.pumpAndSettle();
      expect(t.getTopLeft(control()).dy, closeTo(top, .5));
      expect(find.textContaining('Long progress paragraph 0'), findsWidgets);
      await t.tap(control());
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-to-bottom')), findsNothing);
      expect(find.text('Final answer'), findsOneWidget);
    },
  );

  test('groups split reasoning from replies and keep identity', () {
    owner.session.eventSource.replace(transcript(), false);
    final layout = ProcessLayout();
    final entries = layout.project(owner.conversation.chat.value);
    final groups = entries.where((e) => e.group != null).toList();
    expect(groups, hasLength(1));
    expect(groups.single.group!.members.single.part, 'reasoning');
    expect(entries.where((e) => e.member?.part == 'response'), hasLength(2));
    expect(
      layout
          .project(owner.conversation.chat.value)
          .where((e) => e.group != null)
          .single
          .key,
      groups.single.key,
    );
  });
}
