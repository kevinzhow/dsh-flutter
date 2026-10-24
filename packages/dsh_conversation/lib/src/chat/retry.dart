import '../contract.dart';
import '../event.dart';
import 'definitions.dart' show chatNode, chatTarget;
import 'projection.dart' show asRecord;

enum ModelRetryState { scheduled, started, cancelled }

/// One provider-owned attempt, before or after its retry actually starts.
class ModelRetryAttempt {
  const ModelRetryAttempt({
    required this.seq,
    required this.time,
    required this.retryId,
    required this.turn,
    required this.step,
    required this.retry,
    required this.delayMs,
    required this.failureMessage,
    required this.failureCode,
    this.maxRetries,
    this.state = ModelRetryState.scheduled,
  });

  final num seq, time, delayMs;
  final String retryId, failureMessage, failureCode;
  final int turn, step, retry;

  /// Null is the producer's unlimited (`always`) policy.
  final int? maxRetries;
  final ModelRetryState state;

  ModelRetryAttempt withState(ModelRetryState state) => ModelRetryAttempt(
    seq: seq,
    time: time,
    retryId: retryId,
    turn: turn,
    step: step,
    retry: retry,
    delayMs: delayMs,
    maxRetries: maxRetries,
    failureMessage: failureMessage,
    failureCode: failureCode,
    state: state,
  );
}

/// A retry chain keeps one timeline row anchored to its first attempt.
class ModelRetryData {
  const ModelRetryData(this.attempts);
  final List<ModelRetryAttempt> attempts;
  ModelRetryAttempt get current => attempts.last;
}

ModelRetryAttempt _scheduled(ConvEvent event) {
  final d = event.data;
  final failure = asRecord(d['failure']) ?? const <String, Object?>{};
  return ModelRetryAttempt(
    seq: event.seq,
    time: event.time,
    retryId: d['retryId']! as String,
    turn: coordinate(d['turn']) ?? 0,
    step: coordinate(d['step']) ?? 0,
    retry: coordinate(d['retry']) ?? 1,
    delayMs: d['delayMs']! as num,
    maxRetries: d['mode'] == 'normal' ? coordinate(d['maxRetries']) : null,
    failureMessage: failure['message'] as String? ?? '',
    failureCode: failure['code'] as String? ?? '',
  );
}

/// Pinned dsh `retryDefinition`: producer RetryId correlation, with boundary
/// closure cancelling the last scheduled attempt (never a started attempt).
class ModelRetryDefinition extends ConversationDefinition {
  const ModelRetryDefinition();
  @override
  String get kind => 'model-retry';
  @override
  String? get target => chatTarget;
  @override
  Set<String>? get eventTypes => const {'llm/retry', 'llm/retry-started'};

  @override
  MatchResult? match(ConvEvent event) {
    if (!eventTypes!.contains(event.type)) return null;
    final id = event.data['retryId'];
    if (id is! String || id.isEmpty) return null;
    return MatchResult(
      id,
      event.type == 'llm/retry' && event.data['retry'] == 1
          ? MatchRole.start
          : MatchRole.update,
    );
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => ModelRetryData([_scheduled(match.event)]);

  @override
  Object update(NodeContext context, ConversationMatch match) {
    final state = context.state! as ModelRetryData;
    if (match.event.type == 'llm/retry') {
      return ModelRetryData([...state.attempts, _scheduled(match.event)]);
    }
    final retry = match.event.data['retry'];
    return ModelRetryData([
      for (final attempt in state.attempts)
        attempt.retry == retry
            ? attempt.withState(ModelRetryState.started)
            : attempt,
    ]);
  }

  @override
  ViewNode? buildViewNode(NodeContext context) {
    final state = context.state as ModelRetryData?;
    if (state == null || state.attempts.isEmpty) return null;
    final location = context.start?.location ?? context.matches.first.location;
    final closed = switch (location) {
      StepScopedLocation(:final turn, :final step) =>
        turn.status == BoundaryStatus.closed ||
            step.status == BoundaryStatus.closed,
      TurnScopedLocation(:final turn) => turn.status == BoundaryStatus.closed,
      _ => false,
    };
    final attempts = [
      for (var i = 0; i < state.attempts.length; i++)
        if (closed &&
            i == state.attempts.length - 1 &&
            state.attempts[i].state == ModelRetryState.scheduled)
          state.attempts[i].withState(ModelRetryState.cancelled)
        else
          state.attempts[i],
    ];
    return chatNode(
      context,
      kind,
      attempts.first.seq,
      ModelRetryData(List.unmodifiable(attempts)),
      groupTree: 'process',
    );
  }
}
