import 'dart:async';

import 'package:dsh_models/dsh_models.dart';

import 'question_model.dart';

/// `open` while the tool call may still take the answer; `continued` once the
/// agent went on without it and the answer can only arrive as a late reply (dsh
/// `UserQuestionState`).
enum QuestionPhase { open, continued }

/// What the card says about its wait (dsh `QuestionCardSnapshot.waitState`).
enum QuestionWaitState {
  /// The countdown runs.
  counting,

  /// The person is in the answer surface: the countdown is paused.
  focused,

  /// The person started an answer: no countdown any more.
  editing,

  /// The person asked for time: the Host waits until they answer.
  waiting,

  /// The agent continued; the question stays answerable.
  continued,
}

/// Which way a submission goes right now.
enum QuestionChannel { waterfall, rpc, none }

/// The foreground countdown (dsh `countdown`): [remaining] and whether it still
/// runs ([running] is false while focus or a hold froze it).
class QuestionCountdown {
  const QuestionCountdown(this.remaining, this.running);
  final Duration remaining;
  final bool running;

  /// Whole seconds as dsh prints them (`Math.ceil(ms / 1000)`).
  int get seconds => (remaining.inMilliseconds / 1000).ceil();
}

/// Reactive state read by every presentation of one question.
class QuestionCardSnapshot {
  const QuestionCardSnapshot({
    required this.phase,
    required this.waitState,
    required this.countdown,
    required this.channel,
    required this.closed,
    required this.hidden,
  });

  final QuestionPhase phase;
  final QuestionWaitState waitState;

  /// Null for a request that carried no deadline.
  final QuestionCountdown? countdown;
  final QuestionChannel channel;

  /// The card left the registry; the panel clears.
  final bool closed;

  /// The panel was put away (dsh `hide`); the request stands, the countdown
  /// keeps running, and the tool call row brings it back.
  final bool hidden;
}

/// One live Host waterfall attached to a card; it settles once.
class QuestionWaterfallChannel {
  QuestionWaterfallChannel({
    required this.deadline,
    required this.resolve,
    required this.reject,
    required this.delegate,
  });

  /// Client-clock deadline; null for a blocking question.
  final DateTime? deadline;

  /// Answer the waterfall with the whole batch.
  final Future<void> Function(List<QuestionAnswer> answers) resolve;

  /// Reject it with `ASK_CANCELLED` or `ASK_TIMED_OUT`.
  final Future<void> Function(String code) reject;

  /// Hand the request to the next answerer.
  final Future<void> Function() delegate;
}

/// One answerable question card (dsh `PendingQuestion`, slots.ts): the set of
/// questions, the live waterfall, the countdown and its pauses. The card owns
/// the ticking, so a hidden panel keeps counting and still times out.
class PendingQuestion {
  PendingQuestion({
    required this.key,
    required this.sessionId,
    required this.questions,
    required this.callId,
    DateTime Function()? now,
    this.timed = false,
  }) : _now = now ?? DateTime.now {
    card = Observable(_snapshot());
  }

  /// Render identity: the tool call's key, or the request's own for a blocking
  /// question that names no call.
  final String key;
  final String sessionId;
  final List<QuestionItem> questions;
  final String? callId;

  /// A foreground wait with a Client claim (dsh `wait.timed`).
  final bool timed;
  final DateTime Function() _now;

  /// Card key of a tool call, shared by the forwarded waterfall and the
  /// Session projection.
  static String keyOf(String sessionId, String callId) =>
      'question:$sessionId:$callId';

  /// What closing the panel does: a call-keyed card stays reachable from its
  /// tool call row, so closing only puts it away; a card the Host never named
  /// has no way back, so closing it ends the request.
  bool get hidesOnDismiss => callId != null && timed;

  late final Observable<QuestionCardSnapshot> card;
  QuestionCardSnapshot get snapshot => card.value;

  QuestionPhase _phase = QuestionPhase.open;
  QuestionWaterfallChannel? _waterfall;
  Future<bool> Function(List<QuestionAnswer>)? _rpc;
  Timer? _timer;
  DateTime? _deadline;
  Duration? _remaining;
  bool _timedWait = false;
  bool _focused = false;
  bool _engaged = false;
  bool _held = false;
  bool _closed = false;
  bool _hidden = false;
  bool _disposed = false;

  QuestionCardSnapshot _snapshot() {
    final channel = _waterfall != null
        ? QuestionChannel.waterfall
        : _phase == QuestionPhase.continued && _rpc != null
        ? QuestionChannel.rpc
        : QuestionChannel.none;
    final waitState = _phase == QuestionPhase.continued
        ? QuestionWaitState.continued
        : _held
        ? QuestionWaitState.waiting
        : _engaged
        ? QuestionWaitState.editing
        : _focused
        ? QuestionWaitState.focused
        : QuestionWaitState.counting;
    return QuestionCardSnapshot(
      phase: _phase,
      waitState: waitState,
      countdown: _timedWait
          ? QuestionCountdown(
              _deadline == null
                  ? _remaining ?? Duration.zero
                  : _atLeastZero(_deadline!.difference(_now())),
              _deadline != null,
            )
          : null,
      channel: channel,
      closed: _closed,
      hidden: _hidden,
    );
  }

  static Duration _atLeastZero(Duration d) => d.isNegative ? Duration.zero : d;

  void _publish() {
    if (_disposed) return;
    final snapshot = _snapshot();
    _reschedule();
    card.set(snapshot);
  }

  void _reschedule() {
    final wanted = _deadline != null && !_closed;
    if (wanted == (_timer != null)) return;
    if (!wanted) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final deadline = _deadline;
    if (deadline == null) return;
    if (!_now().isBefore(deadline)) {
      timeout();
      return;
    }
    _publish();
  }

  /// Attach the live waterfall of a forwarded request.
  void attachWaterfall(QuestionWaterfallChannel channel) {
    _waterfall = channel;
    _timedWait = channel.deadline != null;
    if (!_held && !_engaged) {
      _deadline = channel.deadline;
      if (_focused && channel.deadline != null) {
        _remaining = _atLeastZero(channel.deadline!.difference(_now()));
        _deadline = null;
      }
    }
    _publish();
  }

  /// Drop a waterfall that settled or was cancelled; the card stays.
  void detachWaterfall(QuestionWaterfallChannel channel) {
    if (!identical(_waterfall, channel)) return;
    _waterfall = null;
    _timedWait = false;
    _deadline = null;
    _publish();
  }

  bool get hasWaterfall => _waterfall != null;

  /// Attach the Remote answer path used once the question is continued.
  void attachRpc(Future<bool> Function(List<QuestionAnswer>) answer) {
    _rpc = answer;
    _publish();
  }

  /// Copy the projection row's state.
  void setPhase(QuestionPhase phase) {
    if (_phase == phase) return;
    _phase = phase;
    _publish();
  }

  /// Stop this Client's countdown for good; the Host then waits like for a
  /// blocking question.
  void takeTime() {
    if (_held) return;
    _held = true;
    _focused = false;
    _remaining = null;
    _deadline = null;
    _publish();
  }

  /// The person is in the answer surface: freeze a pristine countdown.
  void holdFocus() {
    if (_held || _engaged || _focused) return;
    _remaining = _deadline == null
        ? null
        : _atLeastZero(_deadline!.difference(_now()));
    _deadline = null;
    _focused = true;
    _publish();
  }

  /// The answer surface lost focus: a pristine countdown resumes.
  void releaseFocus() {
    if (!_focused) return;
    _focused = false;
    _deadline = _timedWait && _remaining != null
        ? _now().add(_remaining!)
        : null;
    _remaining = null;
    _publish();
  }

  /// The first edit of a draft: answerable without a foreground deadline.
  void engage() {
    if (_held || _engaged) return;
    if (_remaining == null && _deadline != null) {
      _remaining = _atLeastZero(_deadline!.difference(_now()));
    }
    _engaged = true;
    _focused = false;
    _deadline = null;
    _publish();
  }

  /// The countdown reached zero: settle the waterfall with `ASK_TIMED_OUT` and
  /// keep the card (the projection turns it into a continued question).
  void timeout() {
    if (_held || _engaged || _focused) return;
    final channel = _waterfall;
    if (channel == null) return;
    _waterfall = null;
    _timedWait = false;
    _deadline = null;
    unawaited(channel.reject('ASK_TIMED_OUT').catchError((Object _) {}));
    _publish();
  }

  /// Hand a live waterfall to the next answerer.
  void delegate() {
    final channel = _waterfall;
    if (channel != null) {
      unawaited(channel.delegate().catchError((Object _) {}));
    }
  }

  /// Mark the card removed from the registry.
  void close() {
    if (_closed) return;
    _closed = true;
    _publish();
  }

  /// Put the panel away (`hide`) or bring it back.
  void setHidden(bool hidden) {
    if (_hidden == hidden) return;
    _hidden = hidden;
    _publish();
  }

  /// Submit the whole batch through the live waterfall, or through the Remote
  /// path once the question is continued. Rethrows when the Host refuses,
  /// leaving the card pending.
  Future<void> submit(List<QuestionAnswer> answers) {
    final waterfall = _waterfall;
    if (waterfall != null) return waterfall.resolve(answers);
    final rpc = _rpc;
    if (_phase == QuestionPhase.continued && rpc != null) {
      return rpc(answers).then((accepted) {
        if (!accepted) {
          throw StateError('this question is no longer answerable');
        }
      });
    }
    return Future.error(StateError('no channel accepts an answer yet'));
  }

  /// Close the panel. A call-keyed card only goes away from the composer (the
  /// request stands, the countdown keeps running); any other ends its request.
  Future<void> dismiss() {
    if (hidesOnDismiss) {
      setHidden(true);
      return Future.value();
    }
    final waterfall = _waterfall;
    if (waterfall == null) {
      return Future.error(StateError('no channel accepts a cancellation yet'));
    }
    return waterfall.reject('ASK_CANCELLED');
  }

  /// Stop the timer; the card is never used again.
  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await card.dispose();
  }
}
