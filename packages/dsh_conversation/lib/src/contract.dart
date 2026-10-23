import 'event.dart';

/// Lifecycle role of one matched event (dsh `ConversationMatchResult.role`).
enum MatchRole { start, update }

/// Requested publication cadence of one accepted match.
enum Publication {
  none,
  animationFrame,
  immediate;

  Publication max(Publication other) => index >= other.index ? this : other;
}

/// Engine-owned Location data publication phase.
enum LocationScope { step, turn }

/// Definition-local identity returned by `match` (dsh `ConversationMatchResult`).
class MatchResult {
  const MatchResult(this.id, this.role, {this.exclusive = false});
  final String id;
  final MatchRole role;

  /// Claim this event on the Definition's target (see dsh conversation.md).
  final bool exclusive;
}

/// Resolved boundary state of a Turn or Step.
enum BoundaryStatus { open, closed, unknown }

/// Read access to the Definition-owned values published against one Turn or
/// Step (dsh `ConversationLocationDataStore`).
class LocationDataStore {
  final Map<String, ({String owner, Object? value})> _entries = {};

  Object? get(String key) => _entries[key]?.value;

  bool removeOwned(String owner, String key) {
    final current = _entries[key];
    if (current?.owner != owner) return false;
    _entries.remove(key);
    return true;
  }

  bool setOwned(String owner, String key, Object? value) {
    final current = _entries[key];
    if (current != null && current.owner != owner) {
      throw StateError(
        'conversation Location data "$key" is already owned by ${current.owner}',
      );
    }
    if (identical(current?.value, value)) return false;
    _entries[key] = (owner: owner, value: value);
    return true;
  }

  bool replaceAll(Map<String, ({String owner, Object? value})> next) {
    var changed = false;
    for (final key in {..._entries.keys, ...next.keys}) {
      final a = _entries[key];
      final b = next[key];
      if (a?.owner != b?.owner || !identical(a?.value, b?.value)) {
        changed = true;
      }
    }
    if (!changed) return false;
    _entries
      ..clear()
      ..addAll(next);
    return true;
  }
}

/// Immutable resolved boundary for one Agent step (dsh `StepLocation`).
class StepLocation {
  const StepLocation({
    required this.turn,
    required this.step,
    required this.start,
    required this.end,
    required this.status,
    required this.data,
  });
  final int turn;
  final int step;
  final ConvEvent? start;
  final ConvEvent? end;
  final BoundaryStatus status;
  final LocationDataStore data;
}

/// Immutable resolved boundary for one Agent turn (dsh `TurnLocation`).
class TurnLocation {
  const TurnLocation({
    required this.turn,
    required this.start,
    required this.end,
    required this.status,
    required this.steps,
    required this.data,
  });
  final int turn;
  final ConvEvent? start;
  final ConvEvent? end;
  final BoundaryStatus status;
  final List<StepLocation> steps;
  final LocationDataStore data;
}

/// Engine-owned placement of one matched event in the Session hierarchy.
sealed class ConversationLocation {
  const ConversationLocation();
}

class SessionLocation extends ConversationLocation {
  const SessionLocation();
}

class UnresolvedLocation extends ConversationLocation {
  const UnresolvedLocation();
}

class TurnScopedLocation extends ConversationLocation {
  const TurnScopedLocation(this.turn);
  final TurnLocation turn;
}

class StepScopedLocation extends ConversationLocation {
  const StepScopedLocation(this.turn, this.step);
  final TurnLocation turn;
  final StepLocation step;
}

/// The turn a location resolves to, if any.
int? locationTurn(ConversationLocation l) => switch (l) {
  TurnScopedLocation(:final turn) => turn.turn,
  StepScopedLocation(:final turn) => turn.turn,
  _ => null,
};

int? locationStep(ConversationLocation l) => switch (l) {
  StepScopedLocation(:final step) => step.step,
  _ => null,
};

/// One event accepted by a Definition (dsh `ConversationMatch`).
class ConversationMatch {
  const ConversationMatch(this.event, this.role, this.location);
  final ConvEvent event;
  final MatchRole role;
  final ConversationLocation location;

  ConversationMatch withLocation(ConversationLocation next) =>
      ConversationMatch(event, role, next);
}

/// One Definition-owned value attached to an engine-owned Turn or Step.
class LocationData {
  const LocationData.turn({
    required this.turn,
    required this.key,
    required this.value,
  }) : scope = LocationScope.turn,
       step = null;
  const LocationData.step({
    required this.turn,
    required int this.step,
    required this.key,
    required this.value,
  }) : scope = LocationScope.step;
  final LocationScope scope;
  final int turn;
  final int? step;
  final String key;
  final Object? value;
}

/// Target-neutral identity returned by `buildViewNode` (dsh `ConversationViewNode`).
class ViewNode {
  const ViewNode({
    required this.key,
    required this.kind,
    required this.id,
    required this.target,
    required this.anchorSeq,
    required this.location,
    required this.visible,
    required this.data,
    this.groupTree,
  });
  final String key;
  final String kind;
  final String id;
  final String target;
  final num anchorSeq;
  final ConversationLocation location;
  final bool visible;
  final Object? data;

  /// `exchange`, `input`, `turn` or `process`; absent joins the surrounding step run.
  final String? groupTree;

  ViewNode hidden() => ViewNode(
    key: key,
    kind: kind,
    id: id,
    target: target,
    anchorSeq: anchorSeq,
    location: location,
    visible: false,
    data: data,
    groupTree: groupTree,
  );
}

/// Immutable public view of an assembled business Context (dsh
/// `ConversationNodeContext`).
class NodeContext {
  NodeContext({
    required this.key,
    required this.kind,
    required this.id,
    required this.matches,
    required this.start,
    required this.state,
    required this.current,
  });
  final String key;
  final String kind;
  final String id;
  final List<ConversationMatch> matches;
  final ConversationMatch? start;
  final Object? state;

  /// The node this Context last published per target (null when withheld).
  final Map<String, ViewNode?> current;

  ConversationLocation get location =>
      start?.location ??
      matches.firstOrNull?.location ??
      const UnresolvedLocation();
}

/// Read-only predecessor returned to a Definition's start function.
class PreviousContext {
  const PreviousContext({
    required this.key,
    required this.kind,
    required this.id,
    required this.startSeq,
    required this.state,
    required this.matches,
  });
  final String key;
  final String kind;
  final String id;
  final num startSeq;
  final Object state;
  final List<ConversationMatch> matches;
}

/// Strictly-backward Context lookup available while a start is evaluated.
abstract interface class ContextReader {
  PreviousContext? previous(String kind);
}

/// One independently registered business Event-to-Node state machine (dsh
/// `ConversationNodeDefinition`). State is `Object`, cast by the owner.
abstract class ConversationDefinition {
  const ConversationDefinition();

  String get kind;

  /// Sole view target owned by this Definition; null for state-only Contexts.
  String? get target => null;

  /// Event types this Definition listens to (dsh's table-form `match`); null
  /// receives every event.
  Set<String>? get eventTypes => null;

  MatchResult? match(ConvEvent event);

  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  );

  Object update(NodeContext context, ConversationMatch match);

  Publication publication(ConversationMatch match) => Publication.immediate;

  LocationData? buildLocationData(
    NodeContext context,
    LocationScope scope,
    LocationData? previous,
  ) => null;

  ViewNode? buildViewNode(NodeContext context) => null;
}
