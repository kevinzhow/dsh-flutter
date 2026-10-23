/// One `session/list` row (dsh `SessionSummary`).
class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.updatedAt,
    required this.running,
    required this.blank,
    required this.agentAvailable,
    this.formatStatus,
    this.parentSessionId,
    this.origin,
    this.cwd,
    this.projections,
  });

  factory SessionSummary.fromWire(Map<String, Object?> json) => SessionSummary(
    sessionId: json['sessionId']! as String,
    updatedAt: json['updatedAt']! as num,
    running: json['running'] == true,
    blank: json['blank'] == true,
    agentAvailable: json['agentAvailable'] == true,
    formatStatus: json['formatStatus'] as String?,
    parentSessionId: json['parentSessionId'] as String?,
    origin: json['origin'] as String?,
    cwd: json['cwd'] as String?,
    projections: json['projections'] as Map<String, Object?>?,
  );

  final String sessionId;
  final num updatedAt;
  final bool running;
  final bool blank;
  final bool agentAvailable;
  final String? formatStatus;
  final String? parentSessionId;
  final String? origin;
  final String? cwd;

  /// `{kind: sequenced|cached, asOfSeq, values}` list-surface projection block.
  final Map<String, Object?>? projections;

  SessionSummary copyWith({
    num? updatedAt,
    bool? running,
    bool? blank,
    bool? agentAvailable,
    String? formatStatus,
    String? parentSessionId,
    String? origin,
    String? cwd,
  }) => SessionSummary(
    sessionId: sessionId,
    updatedAt: updatedAt ?? this.updatedAt,
    running: running ?? this.running,
    blank: blank ?? this.blank,
    agentAvailable: agentAvailable ?? this.agentAvailable,
    formatStatus: formatStatus ?? this.formatStatus,
    parentSessionId: parentSessionId ?? this.parentSessionId,
    origin: origin ?? this.origin,
    cwd: cwd ?? this.cwd,
    projections: projections,
  );
}

/// A list mutation recorded while a `session/list` pull is in flight, so the
/// pull never erases later live updates (dsh `SessionListMutation`).
sealed class ListMutation {
  const ListMutation();
}

class UpsertMutation extends ListMutation {
  const UpsertMutation(this.summary);
  final SessionSummary summary;
}

class RemoveMutation extends ListMutation {
  const RemoveMutation(this.sessionId);
  final String sessionId;
}

class StatusMutation extends ListMutation {
  const StatusMutation(this.sessionId, this.running, this.agentAvailable);
  final String sessionId;
  final bool running;
  final bool agentAvailable;
}

class ActivityMutation extends ListMutation {
  const ActivityMutation(this.sessionId, this.updatedAt);
  final String sessionId;
  final num updatedAt;
}

/// Apply one mutation without deriving display order (dsh `applyMutation`).
List<SessionSummary> applyMutation(
  List<SessionSummary> summaries,
  ListMutation mutation,
) {
  switch (mutation) {
    case UpsertMutation(:final summary):
      final i = summaries.indexWhere((s) => s.sessionId == summary.sessionId);
      if (i < 0) return [summary, ...summaries];
      final existing = summaries[i];
      final filled = existing.copyWith(
        // Blank only lowers: a stale true never re-hides a surfaced session.
        blank: existing.blank && summary.blank,
        agentAvailable: summary.agentAvailable,
        running: summary.running,
        formatStatus: summary.formatStatus,
        cwd: existing.cwd == null ? summary.cwd : null,
        parentSessionId: existing.parentSessionId == null
            ? summary.parentSessionId
            : null,
        origin: existing.origin == null ? summary.origin : null,
      );
      return [...summaries]..[i] = filled;
    case RemoveMutation(:final sessionId):
      return summaries.where((s) => s.sessionId != sessionId).toList();
    case StatusMutation(
      :final sessionId,
      :final running,
      :final agentAvailable,
    ):
      return [
        for (final s in summaries)
          if (s.sessionId == sessionId &&
              (s.running != running ||
                  s.agentAvailable != agentAvailable ||
                  (running && s.blank)))
            s.copyWith(
              running: running,
              agentAvailable: agentAvailable,
              blank: s.blank && !running,
            )
          else
            s,
      ];
    case ActivityMutation(:final sessionId, :final updatedAt):
      return [
        for (final s in summaries)
          if (s.sessionId == sessionId && updatedAt > s.updatedAt)
            s.copyWith(updatedAt: updatedAt)
          else
            s,
      ];
  }
}

/// Merge an authoritative baseline without moving identities already visible
/// (dsh `mergeOrderedBaseline`): baseline-only identities are inserted before
/// the nearest following known identity; absent identities are dropped.
List<T> mergeOrderedBaseline<T>(
  List<T> current,
  List<T> baseline,
  Object? Function(T) keyOf,
) {
  final byKey = {for (final v in baseline) keyOf(v): v};
  final merged = [
    for (final v in current)
      if (byKey[keyOf(v)] != null) byKey[keyOf(v)] as T,
  ];
  final keys = merged.map(keyOf).toSet();
  for (var i = 0; i < baseline.length; i++) {
    final value = baseline[i];
    if (keys.contains(keyOf(value))) continue;
    var insertion = merged.length;
    for (var f = i + 1; f < baseline.length; f++) {
      final known = merged.indexWhere((m) => keyOf(m) == keyOf(baseline[f]));
      if (known != -1) {
        insertion = known;
        break;
      }
    }
    merged.insert(insertion, value);
    keys.add(keyOf(value));
  }
  return merged;
}
