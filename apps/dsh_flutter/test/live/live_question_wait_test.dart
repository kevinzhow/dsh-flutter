@Tags(['live'])
library;

// Live check of timed question waits against a real `dsh web` host that the
// caller started on 127.0.0.1 with its own DSH_HOME and a profile that sets the
// `tool-ask-user` row to `mode: timed` (never Kevin's instance):
//   DSH_LIVE_LAUNCH_FILE  mode-600 file holding the launch URL (never printed)
//   DSH_LIVE_RESULT       where to write the JSON result table
// It drives the real AppController + LiveBackend: the Host leaves a timed
// question's countdown to this client (a claim), the countdown runs, expires in
// ASK_TIMED_OUT, the agent goes on, and the question stays answerable through
// the Remote path; a second question is held with Take time and answered in
// time. Two prompts (and the agent's turn that follows the late reply).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart'
    hide composerSlot;
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:flutter_test/flutter_test.dart';

final launchFile = Platform.environment['DSH_LIVE_LAUNCH_FILE'];
final resultFile = Platform.environment['DSH_LIVE_RESULT'];

final results = <Map<String, Object?>>[];

Future<T> step<T>(
  String name,
  Future<T> Function() body, {
  String Function(T)? detail,
}) async {
  final sw = Stopwatch()..start();
  try {
    final value = await body();
    results.add({
      'check': name,
      'state': 'pass',
      'ms': sw.elapsedMilliseconds,
      'detail': detail?.call(value) ?? '',
    });
    return value;
  } on Object catch (e) {
    results.add({
      'check': name,
      'state': 'FAIL',
      'ms': sw.elapsedMilliseconds,
      'detail': '$e',
    });
    rethrow;
  }
}

Future<void> until(
  String what,
  bool Function() test, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final end = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

void main() {
  test(
    'timed question waits against a live dsh host',
    () async {
      final launch = File(launchFile!).readAsStringSync().trim();
      final controller = AppController(
        backend: LiveBackend(),
        locale: DshLocale.en,
      );
      try {
        await step('pair and open a session', () async {
          expect(await controller.pair(launch), isTrue);
          await controller.createSession();
          final sc = controller.openSession!;
          await sc.open();
          await until('cwd', () => sc.owner.cwd != null);
          return sc.sessionId;
        }, detail: (_) => 'session opened');
        final sc = controller.openSession!;
        final tracker = controller.questions;
        PendingQuestion? card() => tracker.forSession(sc.sessionId);
        final session = sc.session;
        Object? view() => session.projections.get('userQuestions');
        String phases() => '${card()?.snapshot.phase.name}';

        // ---- a countdown that runs out -------------------------------------
        await sc.send(
          'Call the ask_user_question tool exactly once. One question, id "q1", text "Which colour?", '
          'options "Red" and "Blue", timeout 6 (seconds). Do not wait for me: after the tool returns, '
          'reply with the single word done.',
        );
        await step(
          'the Host hands the timed wait to this client as a claim',
          () async {
            await until(
              'question card',
              () => card() != null,
              timeout: const Duration(seconds: 120),
            );
            final c = card()!;
            expect(c.timed, isTrue);
            expect(c.callId, isNotNull);
            await until(
              'countdown',
              () => c.snapshot.countdown != null,
              timeout: const Duration(seconds: 10),
            );
            return c.snapshot.countdown!;
          },
          detail: (cd) =>
              'countdown from the Host: ${cd.seconds}s remaining, running ${cd.running}',
        );
        final first = card()!;
        await step(
          'the countdown runs, then settles with ASK_TIMED_OUT',
          () async {
            final started = first.snapshot.countdown!.remaining;
            await Future<void>.delayed(const Duration(seconds: 2));
            final later = first.snapshot.countdown?.remaining;
            expect(later, isNotNull);
            expect(later! < started, isTrue);
            await until(
              'the agent continued',
              () => first.snapshot.phase == QuestionPhase.continued,
              timeout: const Duration(seconds: 60),
            );
            return phases();
          },
          detail: (p) => 'card phase $p after the deadline; card kept',
        );
        await step(
          'the projection lists it as continued and it stays answerable',
          () async {
            final rows = ProjectedQuestion.rowsOf(sc.sessionId, view());
            expect(rows.single.phase, QuestionPhase.continued);
            expect(card(), same(first));
            expect(first.snapshot.channel, QuestionChannel.rpc);
            expect(first.snapshot.waitState, QuestionWaitState.continued);
          },
          detail: (_) => 'projection row state continued; card channel rpc',
        );
        await step(
          'a late answer goes through userQuestions/answer',
          () async {
            await first.submit([
              QuestionAnswer(first.questions.first.id, [
                first.questions.first.options.first.label,
              ]),
            ]);
            await until(
              'projection settles',
              () => tracker.byCallId(sc.sessionId, first.callId!) == null,
              timeout: const Duration(seconds: 60),
            );
            final settled = (view()! as Map)['settled'] as List;
            expect(
              settled.whereType<Map<Object?, Object?>>().any(
                (r) => r['callId'] == first.callId,
              ),
              isTrue,
            );
          },
          detail: (_) =>
              'host accepted the reply; card closed; projection settled',
        );

        // ---- take time ------------------------------------------------------
        await until(
          'agent idle',
          () => !session.snapshot.value.running,
          timeout: const Duration(seconds: 180),
        );
        await sc.send(
          'Call the ask_user_question tool exactly once. One question, id "q1", text "Which size?", '
          'options "Small" and "Large", timeout 10 (seconds). After the answer, reply with the single word ok.',
        );
        await step(
          'Take time holds the wait past the deadline and the answer lands in time',
          () async {
            await until(
              'question card',
              () => card() != null && card()!.callId != first.callId,
              timeout: const Duration(seconds: 120),
            );
            final c = card()!;
            await until(
              'countdown',
              () => c.snapshot.countdown != null,
              timeout: const Duration(seconds: 10),
            );
            c.takeTime();
            expect(c.snapshot.waitState, QuestionWaitState.waiting);
            await Future<void>.delayed(const Duration(seconds: 14));
            expect(
              c.snapshot.phase,
              QuestionPhase.open,
              reason: 'held past its 10s deadline',
            );
            expect(c.hasWaterfall, isTrue);
            await c.submit([
              QuestionAnswer(c.questions.first.id, [
                c.questions.first.options.last.label,
              ]),
            ]);
            await until(
              'card closed by the projection',
              () => tracker.byCallId(sc.sessionId, c.callId!) == null,
              timeout: const Duration(seconds: 120),
            );
          },
          detail: (_) =>
              'waited 14s on a 10s deadline; answered through the waterfall',
        );
      } finally {
        if (resultFile != null) {
          File(resultFile!).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(results),
          );
        }
        controller.dispose();
      }
    },
    skip: launchFile == null
        ? 'needs a live host (see the header of this file)'
        : null,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
