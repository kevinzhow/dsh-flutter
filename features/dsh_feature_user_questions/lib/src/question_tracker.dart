import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';

/// One option of a question (`AskUserQuestionOption`).
class QuestionOption {
  const QuestionOption(this.label, this.description);
  final String label;
  final String? description;
}

/// One question of a request (`AskUserQuestionItem`).
class QuestionItem {
  const QuestionItem({
    required this.id,
    required this.question,
    this.detail,
    this.header,
    this.options = const [],
    this.multiSelect = false,
  });

  factory QuestionItem.fromWire(Map<String, Object?> json) => QuestionItem(
    id: '${json['id']}',
    question: '${json['question']}',
    detail: json['detail'] as String?,
    header: json['header'] as String?,
    multiSelect: json['multiSelect'] == true,
    options: [
      if (json['options'] is List)
        for (final o in json['options']! as List)
          if (o is Map<String, Object?>)
            QuestionOption('${o['label']}', o['description'] as String?),
    ],
  );

  final String id;
  final String question;
  final String? detail;
  final String? header;
  final List<QuestionOption> options;
  final bool multiSelect;
}

/// The answer to one question (`AskUserQuestionAnswerItem`).
class QuestionAnswer {
  const QuestionAnswer(this.id, this.selected, {this.custom});
  final String id;
  final List<String> selected;
  final String? custom;

  Map<String, Object?> toJson() => {
    'id': id,
    'selected': selected,
    if (custom != null && custom!.isNotEmpty) 'custom': custom,
  };
}

/// One pending `user-questions/request` waterfall (dsh `PendingQuestion`).
class PendingQuestion {
  PendingQuestion._({
    required this.key,
    required this.sessionId,
    required this.questions,
    required this.callId,
    required Future<void> Function(WaterfallOutcome) reply,
  }) : _reply = reply;

  /// The host's waterfall `eventId`.
  final String key;
  final String sessionId;
  final List<QuestionItem> questions;
  final String? callId;
  final Future<void> Function(WaterfallOutcome) _reply;

  /// Send the answers (`{answers: [...]}`); resolves when the host accepted
  /// them, rethrows (leaving the question pending) when it did not.
  Future<void> submit(List<QuestionAnswer> answers) => _reply(
    WaterfallResult({
      'answers': [for (final a in answers) a.toJson()],
    }),
  );

  /// Dismiss the whole set: the host's tool call fails with `ASK_CANCELLED`.
  Future<void> dismiss() => _reply(
    const WaterfallRejected(
      'Error',
      'the user cancelled ask_user_question',
      code: 'ASK_CANCELLED',
    ),
  );
}

/// Tracks pending `user-questions/request` waterfalls from forwarded host
/// events and answers them through the connection (the Client model behind
/// dsh's `ui-user-questions`). Same flow as approvals: the host sends the
/// waterfall to every answering connection, the first accepted answer claims
/// it, and a `cancel` frame withdraws it.
class QuestionTracker {
  QuestionTracker({
    required Stream<HostEvent> events,
    required Future<void> Function(WaterfallEvent, WaterfallOutcome) answer,
  }) : _answer = answer {
    _sub = events.listen(_onEvent);
  }

  final Future<void> Function(WaterfallEvent, WaterfallOutcome) _answer;
  late final StreamSubscription<HostEvent> _sub;
  final Map<String, PendingQuestion> _pending = {};

  /// Pending questions in arrival order.
  final Observable<List<PendingQuestion>> pending = Observable(const []);

  void _onEvent(HostEvent e) {
    switch (e) {
      case WaterfallEvent() when e.event == 'user-questions/request':
        final raw = e.request['questions'];
        final wait = e.request['wait'];
        _pending[e.eventId] = PendingQuestion._(
          key: e.eventId,
          sessionId: e.agentId,
          callId: wait is Map ? wait['callId'] as String? : null,
          questions: [
            if (raw is List)
              for (final q in raw)
                if (q is Map<String, Object?>) QuestionItem.fromWire(q),
          ],
          reply: (outcome) async {
            await _answer(e, outcome);
            _remove(e.eventId);
          },
        );
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

  void _publish() => pending.set(List.unmodifiable(_pending.values));

  /// The oldest pending question for [sessionId], or null.
  PendingQuestion? forSession(String sessionId) {
    for (final q in pending.value) {
      if (q.sessionId == sessionId) return q;
    }
    return null;
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await pending.dispose();
  }
}
