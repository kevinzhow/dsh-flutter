import 'dart:convert';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_plan/dsh_feature_plan.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const en = DshI18n(DshLocale.en);

EventEntry ev(num seq, String type, Map<String, Object?> data) =>
    EventEntry({'type': type, 'seq': seq, 'time': 1000 + seq, 'data': data});

EventEntry planCall(num seq, String id, String plan) => ev(seq, 'tool/call', {
  'turn': 1,
  'step': 1,
  'callId': id,
  'name': 'exit_plan_mode',
  'arguments': jsonEncode({'plan': plan}),
});

List<EventEntry> turnWith(List<EventEntry> middle) => [
  ev(1, 'turn/start', {'turn': 1}),
  ev(2, 'step/start', {'turn': 1, 'step': 1}),
  ...middle,
  ev(20, 'step/end', {'turn': 1, 'step': 1}),
  ev(21, 'turn/end', {
    'turn': 1,
    'reason': {'kind': 'completed'},
  }),
];

const planText = '# Ship the release\n\n1. Write notes\n2. Tag it\n';

void main() {
  late SlotRegistry slots;
  late SessionOwner owner;

  setUp(() {
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerPlanFeature(slots, i18n: () => en);
    owner = testSessionOwner('s1');
  });

  List<Widget?> tail() => slots.renderList(
    turnTailSlot,
    TurnTailOwner(
      session: owner,
      turn: 1,
      snapshot: owner.conversation.chat.value,
    ),
  );

  group('submitted plans', () {
    test(
      'a plan is read from a native call, a PTC dispatch; others are ignored',
      () {
        final ok = submittedPlan('tool/call', {
          'name': 'exit_plan_mode',
          'callId': 'p',
          'arguments': jsonEncode({'plan': planText}),
        })!;
        expect((ok.callId, ok.title), ('p', 'Ship the release'));
        final ptc = submittedPlan('tool/ptc-dispatch', {
          'name': 'exit_plan_mode',
          'subCallId': 'sp',
          'arguments': {'plan': '# Second\n\nBody'},
        })!;
        expect((ptc.callId, ptc.title), ('sp', 'Second'));
        expect(
          submittedPlan('tool/call', {
            'name': 'exit_plan_mode',
            'callId': 'p',
            'arguments': '{"plan": "# Cut',
          }),
          isNull,
        );
        expect(
          submittedPlan('tool/call', {
            'name': 'exit_plan_mode',
            'callId': 'p',
            'arguments': jsonEncode({'plan': 'no heading'}),
          }),
          isNull,
        );
        expect(
          submittedPlan('tool/call', {
            'name': 'bash',
            'callId': 'p',
            'arguments': '{}',
          }),
          isNull,
        );
        expect(submittedPlan('user/message', {}), isNull);
      },
    );

    test('plan mode follows the host-folded target', () {
      expect(planModeOn(null), isFalse);
      expect(planModeOn({'active': true, 'pending': false}), isTrue);
      expect(planModeOn({'active': true, 'pending': true}), isFalse);
      expect(planModeOn({'active': false, 'pending': true}), isTrue);
    });
  });

  testWidgets('a turn with a plan shows one card per plan, in order', (
    t,
  ) async {
    owner.session.eventSource.replace(
      turnWith([
        planCall(10, 'p1', planText),
        planCall(11, 'p2', '# Another plan\n\nx'),
      ]),
      false,
    );
    final entries = tail();
    expect(entries.whereType<Widget>().length, 1);
    await t.pumpWidget(dshTestApp(entries.whereType<Widget>().single));
    expect(find.text('Ship the release'), findsOneWidget);
    expect(find.text('Another plan'), findsOneWidget);
    expect(find.text('Plan · Markdown'), findsNWidgets(2));
    expect(find.text('Open'), findsNWidgets(2));
  });

  test('a turn without plans adds nothing', () {
    owner.session.eventSource.replace(turnWith([]), false);
    expect(tail().whereType<Widget>(), isEmpty);
  });

  testWidgets('tapping a card opens the plan document in a sheet', (t) async {
    owner.session.eventSource.replace(
      turnWith([planCall(10, 'p1', planText)]),
      false,
    );
    await t.pumpWidget(dshTestApp(tail().whereType<Widget>().single));
    await t.tap(find.byKey(const ValueKey('plan-card-p1')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-sheet-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-document')), findsOneWidget);
    expect(
      find.textContaining('Write notes', findRichText: true),
      findsWidgets,
    );
    await t.tap(find.byKey(const ValueKey('plan-sheet-close')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-document')), findsNothing);
  });

  testWidgets('cards read in Chinese', (t) async {
    await t.pumpWidget(
      dshTestApp(
        PlanCards(
          plans: const [
            SubmittedPlan(callId: 'p', markdown: '# 发布\n', title: '发布'),
          ],
          i18n: const DshI18n(DshLocale.zh),
          onOpen: (_) {},
        ),
      ),
    );
    expect(find.text('计划 · Markdown'), findsOneWidget);
    expect(find.text('打开'), findsOneWidget);
  });

  testWidgets('the chip shows only while plan mode is the target', (t) async {
    final dock = slots
        .renderList(
          DshSlots.conversationInputDock.typed<SessionOwner, Widget>(),
          owner,
        )
        .single;
    await t.pumpWidget(dshTestApp(dock));
    expect(find.byKey(const ValueKey('plan-chip')), findsNothing);
    owner.session.projections.apply('plan', {
      'active': true,
      'pending': false,
    }, 3);
    await t.pump();
    expect(find.byKey(const ValueKey('plan-chip')), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    owner.session.projections.apply('plan', {
      'active': true,
      'pending': true,
    }, 4);
    await t.pump();
    expect(find.byKey(const ValueKey('plan-chip')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
