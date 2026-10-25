import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';

import 'question_card.dart';
import 'question_model.dart';

export 'question_card.dart';
export 'question_model.dart';

/// What the tracker needs beyond the forwarded events: the foreground claim of
/// a timed wait, the answer path of a continued question, and the projection
/// that lists the questions that can still take an answer.
class QuestionHost {
  const QuestionHost({
    this.attachWait,
    this.answerContinued,
    this.continued,
    this.projectionChanges,
  });

  /// `userQuestions/attachWait` for the request that was delivered: yields the
  /// Host-computed remaining duration once and ends when the wait is over.
  /// Null: no claim can be made (every request then waits like a blocking one).
  final Stream<Duration> Function(WaterfallEvent event, String callId)?
  attachWait;

  /// `userQuestions/answer`: whether the question is still continued.
  final Future<bool> Function(
    String sessionId,
    String callId,
    List<QuestionAnswer> answers,
  )?
  answerContinued;

  /// The active rows of the `userQuestions` projection of every session known:
  /// the timed calls that can still take an answer.
  final List<ProjectedQuestion> Function()? continued;

  /// Fires when a projection changed.
  final Stream<Object?>? projectionChanges;
}

/// One row of the `userQuestions` projection's `active` list.
class ProjectedQuestion {
  const ProjectedQuestion({
    required this.sessionId,
    required this.callId,
    required this.questions,
    required this.phase,
  });

  final String sessionId;
  final String callId;
  final List<QuestionItem> questions;
  final QuestionPhase phase;

  /// Reads `{callId, questions, state}` rows of [view] (null when the view is
  /// not one).
  static List<ProjectedQuestion> rowsOf(String sessionId, Object? view) {
    if (view is! Map || view['active'] is! List) return const [];
    return [
      for (final row
          in (view['active'] as List).whereType<Map<Object?, Object?>>())
        if (row['callId'] is String && row['questions'] is List)
          ProjectedQuestion(
            sessionId: sessionId,
            callId: row['callId'] as String,
            questions: [
              for (final q in (row['questions'] as List))
                if (q is Map<String, Object?>) QuestionItem.fromWire(q),
            ],
            phase: row['state'] == 'continued'
                ? QuestionPhase.continued
                : QuestionPhase.open,
          ),
    ];
  }
}

/// Tracks pending `user-questions/request` waterfalls from forwarded host
/// events and the questions the agent went on without (the `userQuestions`
/// projection), and answers them (the Client model behind dsh's
/// `ui-user-questions`). The host sends a waterfall to every answering
/// connection, the first accepted answer claims it, and a `cancel` frame
/// withdraws it. A timed question is claimed first, so the Host leaves the
/// countdown to this client.
class QuestionTracker {
  QuestionTracker({
    required Stream<HostEvent> events,
    required Future<void> Function(WaterfallEvent, WaterfallOutcome) answer,
    QuestionHost host = const QuestionHost(),
    DateTime Function()? now,
  }) : _answer = answer,
       _host = host,
       _now = now ?? DateTime.now {
    _sub = events.listen(_onEvent);
    _projectionSub = host.projectionChanges?.listen((_) => _reconcile());
    _reconcile();
  }

  final Future<void> Function(WaterfallEvent, WaterfallOutcome) _answer;
  final QuestionHost _host;
  final DateTime Function() _now;
  late final StreamSubscription<HostEvent> _sub;
  StreamSubscription<Object?>? _projectionSub;

  /// Cards by key, in the order they were last published (the last one wins
  /// the composer seat).
  final Map<String, PendingQuestion> _cards = {};
  final Map<String, _Request> _requests = {};
  int _unnamed = 0;

  /// The cards whose panel is not put away, in publication order.
  final Observable<List<PendingQuestion>> pending = Observable(const []);

  void _onEvent(HostEvent e) {
    switch (e) {
      case WaterfallEvent() when e.event == 'user-questions/request':
        _request(e);
      case CancelEvent():
        final request = _requests.remove(e.eventId);
        if (request != null) request.end();
      default:
        break;
    }
  }

  void _request(WaterfallEvent e) {
    final raw = e.request['questions'];
    final wait = e.request['wait'];
    final callId = wait is Map ? wait['callId'] as String? : null;
    final timed = wait is Map && wait['timed'] == true;
    final questions = [
      if (raw is List)
        for (final q in raw)
          if (q is Map<String, Object?>) QuestionItem.fromWire(q),
    ];
    final card = _ensure(e.agentId, questions, callId, timed: timed);
    final request = _Request(this, e, card, timed && callId != null);
    _requests[e.eventId] = request;
    request.start();
  }

  PendingQuestion _ensure(
    String sessionId,
    List<QuestionItem> questions,
    String? callId, {
    bool timed = false,
  }) {
    if (callId != null) {
      final existing = _cards[PendingQuestion.keyOf(sessionId, callId)];
      if (existing != null) return existing;
    }
    final key = callId == null
        ? 'question:$sessionId:unnamed:${++_unnamed}'
        : PendingQuestion.keyOf(sessionId, callId);
    final card = PendingQuestion(
      key: key,
      sessionId: sessionId,
      questions: questions,
      callId: callId,
      now: _now,
      timed: timed,
    );
    card.card.changes.listen((_) => _publish());
    _cards[key] = card;
    _publish();
    return card;
  }

  void _publish() {
    pending.set(
      List.unmodifiable([
        for (final c in _cards.values)
          if (!c.snapshot.hidden && !c.snapshot.closed) c,
      ]),
    );
  }

  void _remove(PendingQuestion card) {
    if (_cards.remove(card.key) == null) return;
    card.close();
    unawaited(card.dispose());
    _publish();
  }

  /// Mirror the projection onto cards: a continued question gets (or keeps) a
  /// card with the Remote answer path; a card with no request left and no
  /// projection row is over.
  void _reconcile() {
    final rows = {
      for (final row in _host.continued?.call() ?? const <ProjectedQuestion>[])
        PendingQuestion.keyOf(row.sessionId, row.callId): row,
    };
    for (final row in rows.values) {
      if (row.phase == QuestionPhase.continued) {
        final card = _ensure(
          row.sessionId,
          row.questions,
          row.callId,
          timed: true,
        );
        final answer = _host.answerContinued;
        if (answer != null) {
          card.attachRpc(
            (answers) => answer(row.sessionId, row.callId, answers),
          );
        }
        card.setPhase(QuestionPhase.continued);
      } else {
        _cards[PendingQuestion.keyOf(row.sessionId, row.callId)]?.setPhase(
          QuestionPhase.open,
        );
      }
    }
    for (final card in [..._cards.values]) {
      if (card.callId == null ||
          rows.containsKey(card.key) ||
          card.hasWaterfall ||
          _requests.values.any((r) => identical(r.card, card) && r.active)) {
        continue;
      }
      _remove(card);
    }
  }

  /// The card of a tool call, if one is still answerable.
  PendingQuestion? byCallId(String sessionId, String callId) =>
      _cards[PendingQuestion.keyOf(sessionId, callId)];

  /// Put one call's answer panel back in the composer, ahead of any other
  /// pending question (the tool call row's "reopen"). False when there is no
  /// such card.
  bool reveal(String sessionId, String callId) {
    final card = byCallId(sessionId, callId);
    if (card == null) return false;
    // Republish last: the registry keeps the latest of equal precedence.
    _cards.remove(card.key);
    _cards[card.key] = card;
    card.setHidden(false);
    _publish();
    return true;
  }

  /// The panel the composer of [sessionId] shows: the card published last.
  PendingQuestion? forSession(String sessionId) {
    PendingQuestion? last;
    for (final q in pending.value) {
      if (q.sessionId == sessionId &&
          (last == null ||
              planReviewOf(q.questions) != null ||
              planReviewOf(last.questions) == null)) {
        last = q;
      }
    }
    return last;
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await _projectionSub?.cancel();
    for (final request in [..._requests.values]) {
      request.dispose();
    }
    _requests.clear();
    for (final card in _cards.values) {
      card.delegate();
      await card.dispose();
    }
    _cards.clear();
    await pending.dispose();
  }
}

/// One forwarded waterfall and its claim.
class _Request {
  _Request(this.tracker, this.event, this.card, this.claims);

  final QuestionTracker tracker;
  final WaterfallEvent event;
  final PendingQuestion card;
  final bool claims;
  StreamSubscription<Duration>? _claim;
  QuestionWaterfallChannel? _channel;
  bool active = true;

  void start() {
    final attach = tracker._host.attachWait;
    if (!claims || attach == null) {
      _attach(null);
      return;
    }
    var first = true;
    _claim = attach(event, card.callId!).listen(
      (remaining) {
        if (!first) return;
        first = false;
        _attach(tracker._now().add(remaining));
      },
      onError: (Object _) {
        // No claim: the Host decides by its own clock; this client does not
        // count down.
        if (first) {
          first = false;
          _attach(null);
        } else {
          end();
        }
      },
      onDone: () {
        if (first) {
          // The wait was already over when the claim opened: hand the request
          // to the next answerer.
          first = false;
          unawaited(_reply(const WaterfallNext()).catchError((Object _) {}));
          _finish();
        } else {
          // The Host closed the claim: it accepted an outcome or gave up.
          end();
        }
      },
    );
  }

  void _attach(DateTime? deadline) {
    final channel = _channel = QuestionWaterfallChannel(
      deadline: deadline,
      resolve: (answers) async {
        await _reply(
          WaterfallResult({
            'answers': [for (final a in answers) a.toJson()],
          }),
        );
        _finish();
      },
      reject: (code) async {
        await _reply(
          WaterfallRejected(
            'UserQuestionError',
            code == 'ASK_TIMED_OUT'
                ? 'ask_user_question timed out before the user answered'
                : 'the user cancelled ask_user_question',
            code: code,
          ),
        );
        _finish();
      },
      delegate: () async {
        await _reply(const WaterfallNext());
        _finish();
      },
    );
    card.attachWaterfall(channel);
  }

  Future<void> _reply(WaterfallOutcome outcome) =>
      tracker._answer(event, outcome);

  /// The request is over without an outcome from this client (cancelled by
  /// the Host, or its claim closed).
  void end() {
    if (!active) return;
    final channel = _channel;
    if (channel != null) card.detachWaterfall(channel);
    _finish();
  }

  void _finish() {
    if (!active) return;
    active = false;
    tracker._requests.remove(event.eventId);
    unawaited(_claim?.cancel());
    _claim = null;
    final channel = _channel;
    if (channel != null) card.detachWaterfall(channel);
    // A blocking request without a call is over with its waterfall; a keyed
    // card stays until the projection stops listing its call.
    if (card.callId == null || !card.timed) {
      tracker._remove(card);
    } else {
      tracker._reconcile();
    }
  }

  void dispose() {
    active = false;
    unawaited(_claim?.cancel());
    _claim = null;
  }
}
