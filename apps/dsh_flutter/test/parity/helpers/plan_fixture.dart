import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_plan/dsh_feature_plan.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';

const syntheticPlan =
    '# **Synthetic plan**\n\nRead the synthetic files before making changes.\n\n## Verification\n\n- Inspect the fixture\n- Keep request identity';
PlanReview get syntheticReview => const PlanReview(
  id: 'decision',
  question: 'Approve synthetic plan?',
  plan: syntheticPlan,
  callId: 'plan-call',
  approve: QuestionOption('Start building', null),
);
PendingQuestion syntheticPending({bool busy = false, bool failure = false}) {
  final pending = PendingQuestion(
    key: 'review-fixture',
    sessionId: 'fixture',
    questions: const [],
    callId: 'review-call',
    timed: true,
  );
  pending.setPhase(QuestionPhase.continued);
  pending.attachRpc((_) async {
    if (busy) await Completer<void>().future;
    if (failure) throw Exception('Synthetic refusal');
    return true;
  });
  return pending;
}

class SyntheticPlanServices implements PlanServices {
  SyntheticPlanServices({this.kind = 'not-found', this.onOpen});
  final String kind;
  final void Function(String, Map<String, Object?>)? onOpen;
  @override
  Future<String?> exitPlanMode(String sessionId) async => null;
  @override
  void openResource(
    SessionOwner owner,
    String address, {
    Map<String, Object?> params = const {},
  }) => onOpen?.call(address, params);
  @override
  SessionHistoryRead historyRead(Map<String, Object?> address) {
    final transport = FakeTransport();
    scheduleMicrotask(() {
      if (kind == 'failed') {
        transport.open(1);
        transport.end(
          1,
          RemoteException('plan/read-failed', 'Synthetic history refused'),
        );
      } else {
        transport.open(1, snapshot([]));
      }
    });
    return SessionHistoryRead(transport, address);
  }
}
