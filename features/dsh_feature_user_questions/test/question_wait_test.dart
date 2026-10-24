import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart' show DshButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

WaterfallEvent timedRequest(String id, {String callId = 'call-1'}) =>
    WaterfallEvent(
      generation: 1,
      event: 'user-questions/request',
      eventId: id,
      agentId: 's1',
      request: {
        'questions': [
          {
            'id': 'q1',
            'question': 'Which database?',
            'options': [
              {'label': 'SQLite'},
              {'label': 'Postgres'},
            ],
          },
        ],
        'wait': {'callId': callId, 'timed': true},
      },
    );

Map<String, Object?> activeRow(String callId, String state) => {
  'callId': callId,
  'state': state,
  'questions': [
    {
      'id': 'q1',
      'question': 'Which database?',
      'options': [
        {'label': 'SQLite'},
        {'label': 'Postgres'},
      ],
    },
  ],
};

void main() {
  late StreamController<HostEvent> events;
  late List<(String, Map<String, Object?>)> answered;
  late List<StreamController<Duration>> claims;
  late StreamController<Object?> projection;
  late List<ProjectedQuestion> rows;
  late List<(String, String, List<QuestionAnswer>)> continuedAnswers;
  late DateTime clock;
  QuestionTracker? created;
  var i18n = const DshI18n(DshLocale.en);

  setUp(() {
    i18n = const DshI18n(DshLocale.en);
    events = StreamController<HostEvent>.broadcast(sync: true);
    projection = StreamController<Object?>.broadcast(sync: true);
    answered = [];
    claims = [];
    rows = [];
    continuedAnswers = [];
    clock = DateTime(2026, 10, 24, 12);
    created = null;
  });

  /// The tracker is built inside the test body: its timers must run on the
  /// test's fake clock, and stream callbacks keep the zone they were set up in.
  void begin() {
    created = QuestionTracker(
      events: events.stream,
      answer: (e, o) async => answered.add((e.eventId, o.toJson())),
      now: () => clock,
      host: QuestionHost(
        attachWait: (event, callId) {
          final c = StreamController<Duration>(sync: true);
          claims.add(c);
          return c.stream;
        },
        answerContinued: (session, callId, answers) async {
          continuedAnswers.add((session, callId, answers));
          return true;
        },
        continued: () => rows,
        projectionChanges: projection.stream,
      ),
    );
  }

  tearDown(() async {
    await created?.dispose();
    await events.close();
    await projection.close();
  });

  /// Real time and the card's clock advance together.
  Future<void> advance(WidgetTester t, Duration d) async {
    clock = clock.add(d);
    await t.pump(d);
  }

  Future<void> show(WidgetTester t) async {
    begin();
    final slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerUserQuestionsFeature(slots, tracker: created!, i18n: () => i18n);
    await t.pumpWidget(
      dshTestApp(
        StreamBuilder<List<PendingQuestion>>(
          stream: created!.pending.changes,
          initialData: created!.pending.value,
          builder: (context, _) => SingleChildScrollView(
            child:
                slots.renderChain(composerSlot, testSessionOwner('s1')) ??
                const Text('composer'),
          ),
        ),
      ),
    );
  }

  Finder status() => find.byKey(const ValueKey('question-wait-status'));

  testWidgets('a timed question is claimed first and counts down', (t) async {
    await show(t);
    events.add(timedRequest('e1'));
    await t.pump();
    expect(claims, hasLength(1));
    // The claim has not answered yet: no countdown, no outcome.
    expect(status(), findsNothing);
    claims.single.add(const Duration(seconds: 20));
    await t.pump();
    expect(find.text('Continuing in 20s'), findsOneWidget);
    expect(find.text('Take time'), findsOneWidget);
    await advance(t, const Duration(seconds: 5));
    expect(find.text('Continuing in 15s'), findsOneWidget);
    await advance(t, const Duration(seconds: 1));
    expect(find.text('Continuing in 14s'), findsOneWidget);
    expect(answered, isEmpty);
    created!.byCallId('s1', 'call-1')!.takeTime(); // stops the timer
  });

  testWidgets('the countdown ends in ASK_TIMED_OUT and the card stays', (
    t,
  ) async {
    await show(t);
    rows = [
      ProjectedQuestion(
        sessionId: 's1',
        callId: 'call-1',
        questions: [
          for (final q in [
            {'id': 'q1', 'question': 'Which database?'},
          ])
            QuestionItem.fromWire(q),
        ],
        phase: QuestionPhase.open,
      ),
    ];
    events.add(timedRequest('e1'));
    await t.pump();
    claims.single.add(const Duration(seconds: 3));
    await t.pump();
    await advance(t, const Duration(seconds: 3));
    expect(answered, hasLength(1));
    final outcome = answered.single.$2;
    expect(outcome['kind'], 'rejected');
    expect((outcome['error']! as Map)['code'], 'ASK_TIMED_OUT');
    expect((outcome['error']! as Map)['name'], 'UserQuestionError');
    // The question is still there, waiting for the projection to move on.
    expect(find.text('Which database?'), findsOneWidget);
    expect(find.text('Continuing in 0s'), findsNothing);
    expect(created!.byCallId('s1', 'call-1'), isNotNull);
  });

  testWidgets('the countdown pauses while the answer surface has focus', (
    t,
  ) async {
    await show(t);
    events.add(timedRequest('e1'));
    await t.pump();
    claims.single.add(const Duration(seconds: 20));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('question-custom')));
    await t.pump();
    expect(find.text('Paused · 20s remaining'), findsOneWidget);
    await advance(t, const Duration(seconds: 30));
    expect(answered, isEmpty);
    expect(find.text('Paused · 20s remaining'), findsOneWidget);
    // Leaving the surface resumes it with what was left.
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump();
    await t.pump();
    expect(find.text('Continuing in 20s'), findsOneWidget);
    await advance(t, const Duration(seconds: 4));
    expect(find.text('Continuing in 16s'), findsOneWidget);
    created!.byCallId('s1', 'call-1')!.takeTime();
  });

  testWidgets('taking time stops the countdown for good', (t) async {
    await show(t);
    events.add(timedRequest('e1'));
    await t.pump();
    claims.single.add(const Duration(seconds: 5));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('question-take-time')));
    await t.pump();
    expect(find.text('Waiting until you answer'), findsOneWidget);
    expect(find.text('Take time'), findsNothing);
    await advance(t, const Duration(minutes: 5));
    expect(answered, isEmpty);
  });

  testWidgets('starting an answer ends the countdown too', (t) async {
    await show(t);
    events.add(timedRequest('e1'));
    await t.pump();
    claims.single.add(const Duration(seconds: 5));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('option-Postgres')));
    await t.pump();
    expect(find.text('Waiting until you answer'), findsOneWidget);
    await advance(t, const Duration(minutes: 1));
    expect(answered, isEmpty);
  });

  testWidgets(
    'a wait that was over before the claim opened goes to the next answerer',
    (t) async {
      begin();
      events.add(timedRequest('e1'));
      unawaited(claims.single.close());
      await t.pump();
      expect(answered.single.$2, {'kind': 'next'});
      expect(created!.pending.value, isEmpty);
    },
  );

  testWidgets('the Host closing the claim withdraws the request', (t) async {
    await show(t);
    events.add(timedRequest('e1'));
    await t.pump();
    claims.single.add(const Duration(seconds: 20));
    await t.pump();
    unawaited(claims.single.close());
    await t.pump();
    expect(answered, isEmpty);
    expect(
      created!.byCallId('s1', 'call-1'),
      isNull,
      reason: 'the projection does not list it, so it is over',
    );
  });

  testWidgets('a failed claim leaves the Host to count', (t) async {
    await show(t);
    events.add(timedRequest('e1'));
    await t.pump();
    claims.single.addError(StateError('no claim'));
    await t.pump();
    expect(find.text('Which database?'), findsOneWidget);
    expect(status(), findsNothing);
  });

  testWidgets('a continued question stays answerable by the Remote path', (
    t,
  ) async {
    await show(t);
    rows = [
      ProjectedQuestion.rowsOf('s1', {
        'active': [activeRow('call-1', 'continued')],
        'settled': <Object?>[],
      }).single,
    ];
    projection.add('s1');
    await t.pump();
    expect(find.text('Which database?'), findsOneWidget);
    expect(find.text('Work continued — you can still answer'), findsOneWidget);
    expect(find.text('Take time'), findsNothing);
    await t.tap(find.byKey(const ValueKey('option-SQLite')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('question-submit')));
    await t.pump();
    expect(continuedAnswers.single.$1, 's1');
    expect(continuedAnswers.single.$2, 'call-1');
    expect(continuedAnswers.single.$3.single.selected, ['SQLite']);
    // Accepted: the panel goes away, the projection settles the call later.
    expect(find.text('Which database?'), findsNothing);
    rows = [];
    projection.add('s1');
    await t.pump();
    expect(created!.byCallId('s1', 'call-1'), isNull);
  });

  testWidgets(
    'a waterfall answer keeps the panel locked until the projection moves on',
    (t) async {
      await show(t);
      rows = [
        ProjectedQuestion.rowsOf('s1', {
          'active': [activeRow('call-1', 'open')],
        }).single,
      ];
      events.add(timedRequest('e1'));
      await t.pump();
      claims.single.add(const Duration(seconds: 20));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('option-SQLite')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('question-submit')));
      await t.pump();
      expect(answered.single.$2['kind'], 'result');
      // Sent, not yet closed by the projection: the controls stay frozen.
      expect(find.byKey(const ValueKey('question-panel')), findsOneWidget);
      final submit = t.widget<DshButton>(
        find.byKey(const ValueKey('question-submit')),
      );
      expect(submit.onPressed, isNull);
      // The agent went on without it: the draft goes through the other path.
      rows = [
        ProjectedQuestion.rowsOf('s1', {
          'active': [activeRow('call-1', 'continued')],
        }).single,
      ];
      projection.add('s1');
      await t.pump();
      expect(
        find.text(
          'The answer did not arrive before work continued; submit it again.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'closing a timed panel puts it away; the tool row brings it back',
    (t) async {
      await show(t);
      rows = [
        ProjectedQuestion.rowsOf('s1', {
          'active': [activeRow('call-1', 'open')],
        }).single,
      ];
      events.add(timedRequest('e1'));
      await t.pump();
      claims.single.add(const Duration(seconds: 20));
      await t.pump();
      expect(
        find.bySemanticsLabel('Close the panel — reopen it from the tool call'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('question-dismiss')));
      await t.pump();
      expect(answered, isEmpty, reason: 'closing sends nothing');
      expect(find.text('Which database?'), findsNothing);
      // The countdown keeps running behind the closed panel.
      await advance(t, const Duration(seconds: 20));
      expect(answered.single.$2['kind'], 'rejected');
      expect(created!.reveal('s1', 'call-1'), isTrue);
      await t.pump();
      expect(find.text('Which database?'), findsOneWidget);
      expect(created!.reveal('s1', 'nope'), isFalse);
    },
  );

  testWidgets('a blocking question has no countdown and cancels when closed', (
    t,
  ) async {
    await show(t);
    events.add(
      const WaterfallEvent(
        generation: 1,
        event: 'user-questions/request',
        eventId: 'e9',
        agentId: 's1',
        request: {
          'questions': [
            {'id': 'q1', 'question': 'Free text?'},
          ],
        },
      ),
    );
    await t.pump();
    expect(claims, isEmpty);
    expect(status(), findsNothing);
    await t.tap(find.byKey(const ValueKey('question-dismiss')));
    await t.pump();
    expect((answered.single.$2['error']! as Map)['code'], 'ASK_CANCELLED');
  });

  testWidgets('zh copy of the wait states', (t) async {
    i18n = const DshI18n(DshLocale.zh);
    await show(t);
    events.add(timedRequest('e1'));
    await t.pump();
    claims.single.add(const Duration(seconds: 20));
    await t.pump();
    expect(find.text('20 秒后继续工作'), findsOneWidget);
    expect(find.text('慢慢回答'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('question-take-time')));
    await t.pump();
    expect(find.text('会一直等你回答'), findsOneWidget);
  });
}
