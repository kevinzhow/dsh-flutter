import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';

class PlanAddress {
  const PlanAddress(this.session, this.callId);
  final Map<String, Object?> session;
  final String callId;
  String get encoded {
    final s = session;
    final parts = s['kind'] == 'session'
        ? [s['sessionId'], callId]
        : [
            'subagent',
            s['parentSessionId'],
            s['childSessionId'],
            s['mode'],
            callId,
          ];
    return 'dsh-resource://plan/${parts.map((v) => Uri.encodeComponent(v! as String)).join('/')}';
  }

  static PlanAddress? parse(String address) {
    final match = RegExp(r'^dsh-resource://plan/([^?#]+)$').firstMatch(address);
    if (match == null) return null;
    try {
      final parts = match[1]!.split('/').map(Uri.decodeComponent).toList();
      if (parts.any((p) => p.isEmpty)) return null;
      if (parts.length == 2) {
        return PlanAddress({
          'kind': 'session',
          'sessionId': parts[0],
        }, parts[1]);
      }
      if (parts.length == 5 &&
          parts[0] == 'subagent' &&
          const ['one-shot', 'continuable', 'unknown'].contains(parts[3])) {
        return PlanAddress({
          'kind': 'subagent',
          'parentSessionId': parts[1],
          'childSessionId': parts[2],
          'mode': parts[3],
        }, parts[4]);
      }
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    return null;
  }
}

String reviewPreviewAddress(String sessionId, String requestKey) =>
    'dsh-resource://plan-review/${Uri.encodeComponent(sessionId)}/${Uri.encodeComponent(requestKey)}';
bool isReviewPreviewAddress(String address) =>
    RegExp(r'^dsh-resource://plan-review/[^/?#]+/[^/?#]+$').hasMatch(address);

/// Locate an immutable submitted plan by invocation identity, even when its
/// tool call is older than the visible chat window. Page reads share one cut.
Future<SubmittedPlan?> readSubmittedPlan(
  SessionHistoryRead read,
  String callId,
) async {
  final snapshot = await read.snapshot();
  final cursor = snapshot['cursor'];
  if (cursor is! num) throw StateError('Session snapshot carried no cursor');
  Map<String, Object?> page = snapshot;
  num? previousBefore;
  while (true) {
    final records = page['records'];
    if (records is! List) {
      throw StateError('Session history carried no records');
    }
    num? before;
    for (final raw in records) {
      if (raw is! Map || raw['event'] is! Map<String, Object?>) continue;
      final event = raw['event'] as Map<String, Object?>;
      final seq = event['seq'];
      if (seq is num && (before == null || seq < before)) before = seq;
      if (event['type'] is! String || event['data'] is! Map<String, Object?>) {
        continue;
      }
      final plan = submittedPlan(
        event['type'] as String,
        event['data'] as Map<String, Object?>,
      );
      if (plan?.callId == callId) return plan;
    }
    if (page['hasMore'] != true ||
        before == null ||
        (previousBefore != null && before >= previousBefore)) {
      return null;
    }
    previousBefore = before;
    page = await read.page(throughSeq: cursor, beforeSeq: before);
  }
}
