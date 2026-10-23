import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';

/// One pending `approval/request` waterfall (dsh `PendingApproval`,
/// `ui-approval/contract/slots.ts`).
class PendingApproval {
  PendingApproval._({
    required this.key,
    required this.sessionId,
    required this.toolName,
    required this.callId,
    required this.reason,
    required this.displayReason,
    required Future<void> Function(String outcome) answerFn,
  }) : _answer = answerFn;

  /// The host's waterfall `eventId`.
  final String key;

  /// The Agent (= session) the question is asked on behalf of.
  final String sessionId;
  final String toolName;
  final String? callId;

  /// The asker's human-readable explanation, if any.
  final String? reason;

  /// Localized presentation `{en, zh, ...}`; never audited.
  final Map<String, String>? displayReason;

  final Future<void> Function(String outcome) _answer;
  bool _inFlight = false;

  /// True while an answer is being sent (the UI disables its buttons).
  bool get answering => _inFlight;

  /// The reason in [locale] (`zh`, `en`), falling back to `en`, then [reason].
  String? reasonFor(String locale) =>
      displayReason?[locale] ?? displayReason?['en'] ?? reason;

  /// Send `allowed-once` or `rejected`. Resolves once the host accepted the
  /// result; on failure the approval stays pending and the error is rethrown.
  Future<void> answer(String outcome) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      await _answer(outcome);
    } finally {
      _inFlight = false;
    }
  }
}

/// Tracks pending approvals from forwarded host events and answers them
/// through the connection (the Client model behind dsh's `ui-approval`).
///
/// Every connection that attached with `interactions=answer` receives the
/// waterfall; the first answer the host accepts claims it. A host `cancel`
/// frame (turn cancelled, someone else answered) withdraws it locally.
class ApprovalTracker {
  ApprovalTracker({
    required Stream<HostEvent> events,
    required Future<void> Function(
      WaterfallEvent event,
      WaterfallOutcome outcome,
    )
    answer,
  }) : _answer = answer {
    _sub = events.listen(_onEvent);
  }

  final Future<void> Function(WaterfallEvent, WaterfallOutcome) _answer;
  late final StreamSubscription<HostEvent> _sub;
  final Map<String, ({WaterfallEvent event, PendingApproval approval})>
  _pending = {};

  /// Pending approvals in arrival order.
  final Observable<List<PendingApproval>> pending = Observable(const []);

  void _onEvent(HostEvent e) {
    switch (e) {
      case WaterfallEvent() when e.event == 'approval/request':
        final r = e.request;
        final display = r['displayReason'];
        final approval = PendingApproval._(
          key: e.eventId,
          sessionId: e.agentId,
          toolName: '${r['toolName']}',
          callId: r['callId'] as String?,
          reason: r['reason'] as String?,
          displayReason: display is Map
              ? {for (final x in display.entries) '${x.key}': '${x.value}'}
              : null,
          answerFn: (outcome) async {
            await _answer(e, WaterfallResult(outcome));
            _remove(e.eventId);
          },
        );
        _pending[e.eventId] = (event: e, approval: approval);
        _publish();
      case CancelEvent():
        _remove(e.eventId);
      default:
        break;
    }
  }

  void _remove(String eventId) {
    if (_pending.remove(eventId) != null) _publish();
  }

  void _publish() =>
      pending.set(List.unmodifiable(_pending.values.map((v) => v.approval)));

  /// The oldest pending approval for [sessionId], or null.
  PendingApproval? forSession(String sessionId) {
    for (final a in pending.value) {
      if (a.sessionId == sessionId) return a;
    }
    return null;
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await pending.dispose();
  }
}
