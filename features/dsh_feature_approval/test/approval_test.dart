import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_approval/dsh_feature_approval.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WaterfallEvent approvalEvent(
  String id, {
  String session = 's1',
  Map<String, Object?>? extra,
}) => WaterfallEvent(
  generation: 1,
  event: 'approval/request',
  eventId: id,
  agentId: session,
  request: {'toolName': 'bash', 'callId': 'c1', ...?extra},
);

Widget host(Widget child, {Brightness b = Brightness.light}) => MaterialApp(
  theme: ThemeData(
    extensions: [resolveTheme(officialPack, ThemeSettings(), b)],
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  late StreamController<HostEvent> events;
  late List<(String, Object?)> answers;
  late ApprovalTracker tracker;
  Object? failNext;

  setUp(() {
    events = StreamController<HostEvent>.broadcast(sync: true);
    answers = [];
    failNext = null;
    tracker = ApprovalTracker(
      events: events.stream,
      answer: (e, outcome) async {
        if (failNext != null) throw failNext!;
        answers.add((e.eventId, (outcome as WaterfallResult).value));
      },
    );
  });
  tearDown(() async {
    await tracker.dispose();
    await events.close();
  });

  group('tracker', () {
    test(
      'tracks approval/request per session and ignores other waterfalls',
      () {
        events.add(approvalEvent('e1'));
        events.add(approvalEvent('e2', session: 's2'));
        events.add(
          const WaterfallEvent(
            generation: 1,
            event: 'user-questions/request',
            eventId: 'q',
            agentId: 's1',
            request: {},
          ),
        );
        expect(tracker.pending.value.map((a) => a.key), ['e1', 'e2']);
        expect(tracker.forSession('s2')!.key, 'e2');
        expect(tracker.forSession('nope'), isNull);
      },
    );

    test('a cancel frame withdraws; a successful answer removes', () async {
      events.add(approvalEvent('e1'));
      events.add(approvalEvent('e2'));
      events.add(const CancelEvent('e1'));
      expect(tracker.pending.value.map((a) => a.key), ['e2']);
      await tracker.forSession('s1')!.answer('allowed-once');
      expect(answers, [('e2', 'allowed-once')]);
      expect(tracker.pending.value, isEmpty);
    });

    test('a failed answer keeps it pending and rethrows', () async {
      events.add(approvalEvent('e1'));
      failNext = RemoteException('x/y', 'boom');
      final a = tracker.forSession('s1')!;
      await expectLater(a.answer('rejected'), throwsA(isA<RemoteException>()));
      expect(tracker.pending.value, hasLength(1));
      expect(a.answering, isFalse);
    });

    test('displayReason resolves by locale with en fallback', () {
      events.add(
        approvalEvent(
          'e1',
          extra: {
            'reason': 'raw',
            'displayReason': {'en': 'Run it?', 'zh': '运行?'},
          },
        ),
      );
      final a = tracker.forSession('s1')!;
      expect(a.reasonFor('zh'), '运行?');
      expect(a.reasonFor('fr'), 'Run it?');
    });
  });

  group('slot registration', () {
    test(
      'the chain entry matches only while the session has a pending approval',
      () {
        final slots = SlotRegistry();
        for (final s in DshSlots.all) {
          slots.declare(s);
        }
        registerApprovalFeature(
          slots,
          tracker: tracker,
          i18n: () => const DshI18n(DshLocale.en),
        );
        expect(slots.renderChain(composerSlot, testSessionOwner('s1')), isNull);
        events.add(approvalEvent('e1'));
        expect(
          slots.renderChain(composerSlot, testSessionOwner('s1')),
          isA<ApprovalPanel>(),
        );
        expect(
          slots.renderChain(composerSlot, testSessionOwner('other')),
          isNull,
        );
      },
    );

    test('registering twice fails (duplicate chain id)', () {
      final slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      registerApprovalFeature(
        slots,
        tracker: tracker,
        i18n: () => const DshI18n(DshLocale.en),
      );
      expect(
        () => registerApprovalFeature(
          slots,
          tracker: tracker,
          i18n: () => const DshI18n(DshLocale.en),
        ),
        throwsA(isA<SlotError>()),
      );
    });
  });

  group('panel', () {
    testWidgets(
      'shows the generic escalation sentence and answers Allow once',
      (tester) async {
        events.add(approvalEvent('e1'));
        final a = tracker.forSession('s1')!;
        await tester.pumpWidget(
          host(ApprovalPanel(approval: a, i18n: const DshI18n(DshLocale.en))),
        );
        final i18n = const DshI18n(DshLocale.en);
        expect(find.text(i18n.t('approval', 'waiting')), findsOneWidget);
        expect(
          find.text(
            i18n.t('approval', 'escalation', params: {'toolName': 'bash'}),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('approval-allow')));
        await tester.pump();
        expect(answers, [('e1', 'allowed-once')]);
      },
    );

    testWidgets('Reject sends rejected; buttons disable while answering', (
      tester,
    ) async {
      events.add(approvalEvent('e1'));
      final a = tracker.forSession('s1')!;
      await tester.pumpWidget(
        host(
          ApprovalPanel(approval: a, i18n: const DshI18n(DshLocale.en)),
          b: Brightness.dark,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('approval-reject')));
      await tester.pump();
      expect(answers, [('e1', 'rejected')]);
    });

    testWidgets(
      'zh locale renders the Chinese catalog and the localized displayReason',
      (tester) async {
        events.add(
          approvalEvent(
            'e1',
            extra: {
              'displayReason': {'en': 'Run it?', 'zh': '要运行吗?'},
            },
          ),
        );
        final a = tracker.forSession('s1')!;
        const zh = DshI18n(DshLocale.zh);
        await tester.pumpWidget(host(ApprovalPanel(approval: a, i18n: zh)));
        expect(find.text('要运行吗?'), findsOneWidget);
        expect(find.text(zh.t('approval', 'allowOnce')), findsOneWidget);
        expect(
          zh.t('approval', 'allowOnce'),
          isNot(const DshI18n(DshLocale.en).t('approval', 'allowOnce')),
        );
      },
    );

    testWidgets('a refused answer re-enables the buttons', (tester) async {
      events.add(approvalEvent('e1'));
      failNext = RemoteException('x/y', 'boom');
      final a = tracker.forSession('s1')!;
      await tester.pumpWidget(
        host(ApprovalPanel(approval: a, i18n: const DshI18n(DshLocale.en))),
      );
      await tester.tap(find.byKey(const ValueKey('approval-allow')));
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<DshButton>(find.byKey(const ValueKey('approval-allow')))
            .onPressed,
        isNotNull,
      );
    });
  });
}
