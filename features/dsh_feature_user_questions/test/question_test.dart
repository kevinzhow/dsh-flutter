import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

WaterfallEvent request(
  String id, {
  String session = 's1',
  List<Object?>? questions,
}) => WaterfallEvent(
  generation: 1,
  event: 'user-questions/request',
  eventId: id,
  agentId: session,
  request: {
    'questions':
        questions ??
        [
          {
            'id': 'q1',
            'question': 'Which database?',
            'header': 'Storage',
            'options': [
              {'label': 'SQLite', 'description': 'embedded'},
              {'label': 'Postgres'},
            ],
          },
          {
            'id': 'q2',
            'question': 'Which extras?',
            'multiSelect': true,
            'options': [
              {'label': 'Auth'},
              {'label': 'Metrics'},
            ],
          },
        ],
    'wait': {'callId': 'call-9'},
  },
);

void main() {
  late StreamController<HostEvent> events;
  late List<(String, Map<String, Object?>)> answered;
  late QuestionTracker tracker;
  Object? failNext;

  setUp(() {
    events = StreamController<HostEvent>.broadcast(sync: true);
    answered = [];
    failNext = null;
    tracker = QuestionTracker(
      events: events.stream,
      answer: (e, o) async {
        if (failNext != null) throw failNext!;
        answered.add((e.eventId, o.toJson()));
      },
    );
  });

  tearDown(() async {
    await tracker.dispose();
    await events.close();
  });

  test(
    'tracks user-questions/request per session, ignores other waterfalls',
    () {
      events.add(request('e1'));
      events.add(
        const WaterfallEvent(
          generation: 1,
          event: 'approval/request',
          eventId: 'x',
          agentId: 's1',
          request: {},
        ),
      );
      expect(tracker.pending.value, hasLength(1));
      final q = tracker.forSession('s1')!;
      expect(q.questions, hasLength(2));
      expect(q.callId, 'call-9');
      expect(q.questions.first.options.first.description, 'embedded');
      expect(q.questions.last.multiSelect, isTrue);
      expect(tracker.forSession('other'), isNull);
      events.add(const CancelEvent('e1'));
      expect(tracker.pending.value, isEmpty);
    },
  );

  test(
    'submit sends the answers as a result; dismiss rejects with ASK_CANCELLED',
    () async {
      events.add(request('e1'));
      final q = tracker.forSession('s1')!;
      await q.submit(const [
        QuestionAnswer('q1', ['SQLite']),
        QuestionAnswer('q2', ['Auth', 'Metrics'], custom: 'tracing'),
      ]);
      expect(answered.single.$1, 'e1');
      expect(answered.single.$2, {
        'kind': 'result',
        'value': {
          'answers': [
            {
              'id': 'q1',
              'selected': ['SQLite'],
            },
            {
              'id': 'q2',
              'selected': ['Auth', 'Metrics'],
              'custom': 'tracing',
            },
          ],
        },
      });
      expect(tracker.pending.value, isEmpty);

      events.add(request('e2'));
      await tracker.forSession('s1')!.dismiss();
      final error = (answered.last.$2['error']! as Map);
      expect(answered.last.$2['kind'], 'rejected');
      expect(error['code'], 'ASK_CANCELLED');
    },
  );

  testWidgets('the panel walks the questions and sends every answer', (
    t,
  ) async {
    events.add(request('e1'));
    final slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerUserQuestionsFeature(
      slots,
      tracker: tracker,
      i18n: () => const DshI18n(DshLocale.en),
    );
    final panel = slots.renderChain(composerSlot, testSessionOwner('s1'))!;
    await t.pumpWidget(dshTestApp(SingleChildScrollView(child: panel)));
    expect(find.text('Which database?'), findsOneWidget);
    final next = find.byKey(const ValueKey('question-next'));
    await t.tap(next); // nothing chosen yet: disabled
    await t.pump();
    expect(find.text('Which database?'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('option-Postgres')));
    await t.pump();
    await t.tap(next);
    await t.pump();
    expect(find.text('Which extras?'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('option-Auth')));
    await t.tap(find.byKey(const ValueKey('option-Metrics')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('question-submit')));
    await t.pump();
    expect(answered, hasLength(1));
    final value = (answered.single.$2['value']! as Map)['answers']! as List;
    expect(value[0], {
      'id': 'q1',
      'selected': ['Postgres'],
    });
    expect((value[1] as Map)['selected'], ['Auth', 'Metrics']);
  });

  testWidgets('a refused answer keeps the panel and shows the error', (
    t,
  ) async {
    events.add(
      request(
        'e1',
        questions: [
          {'id': 'q1', 'question': 'Free text?'},
        ],
      ),
    );
    failNext = StateError('host said no');
    final panel = QuestionPanel(
      pending: tracker.forSession('s1')!,
      i18n: const DshI18n(DshLocale.zh),
    );
    await t.pumpWidget(dshTestApp(SingleChildScrollView(child: panel)));
    await t.enterText(find.byType(EditableText), 'my answer');
    await t.pump();
    expect(find.text('发送回答'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('question-submit')));
    await t.pump();
    expect(find.byKey(const ValueKey('question-error')), findsOneWidget);
    expect(tracker.pending.value, hasLength(1));
  });
}
