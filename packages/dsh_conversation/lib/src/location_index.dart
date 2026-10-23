import 'contract.dart';
import 'event.dart';
import 'registry.dart';

class _Coords {
  _Coords({this.turn, this.step, this.session = false, this.location});
  final int? turn;
  final int? step;
  final bool session;
  ConversationLocation? location;
}

class _StepDraft {
  _StepDraft(this.turn, this.step, this.firstSeq);
  final int turn;
  final int step;
  num firstSeq;
  ConvEvent? start;
  ConvEvent? end;
}

class _TurnDraft {
  _TurnDraft(this.turn, this.firstSeq);
  final int turn;
  num firstSeq;
  ConvEvent? start;
  ConvEvent? end;
  final Map<int, _StepDraft> steps = {};
}

const _session = SessionLocation();
const _unresolved = UnresolvedLocation();

_Coords _payloadCoordinates(ConvEvent event) {
  final data = event.entry.event['data'];
  if (data is Map<String, Object?>) {
    if (data.containsKey('turn') && data['turn'] == null) {
      return _Coords(session: true);
    }
    return _Coords(
      turn: coordinate(data['turn']),
      step: coordinate(data['step']),
    );
  }
  return _Coords();
}

bool _sameRefs<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

bool _sameStep(StepLocation? a, StepLocation b) =>
    a != null &&
    identical(a.start, b.start) &&
    identical(a.end, b.end) &&
    a.status == b.status &&
    identical(a.data, b.data);

bool _sameTurn(TurnLocation? a, TurnLocation b) =>
    a != null &&
    identical(a.start, b.start) &&
    identical(a.end, b.end) &&
    a.status == b.status &&
    identical(a.data, b.data) &&
    _sameRefs(a.steps, b.steps);

bool _sameLocation(ConversationLocation? a, ConversationLocation? b) {
  if (a == null || b == null) return a == b;
  if (a is SessionLocation) return b is SessionLocation;
  if (a is UnresolvedLocation) return b is UnresolvedLocation;
  if (b is SessionLocation || b is UnresolvedLocation) return false;
  if (a is TurnScopedLocation || b is TurnScopedLocation) {
    return a is TurnScopedLocation &&
        b is TurnScopedLocation &&
        identical(a.turn, b.turn);
  }
  final x = a as StepScopedLocation;
  final y = b as StepScopedLocation;
  return identical(x.turn, y.turn) && identical(x.step, y.step);
}

bool _isBoundary(String type) =>
    type == 'turn/start' ||
    type == 'turn/end' ||
    type == 'step/start' ||
    type == 'step/end';

/// One Definition-owned Location-data change (dsh `ConversationLocationDataChange`).
class LocationDataChange {
  const LocationDataChange(this.owner, this.previous, this.next);
  final String owner;
  final LocationData? previous;
  final LocationData? next;
}

/// Session-owned Turn/Step timeline and event-to-Location index (dsh
/// `ConversationLocationIndex`).
class ConversationLocationIndex {
  Map<int, Set<num>> _seqsByTurn = {};
  final Map<int, Map<int, StepLocation>> _stepsByTurn = {};
  ConversationTimeline _timeline = ConversationTimeline.empty;
  final Map<int, LocationDataStore> _turnData = {};
  final Map<String, LocationDataStore> _stepData = {};
  final Set<int> _changedTurns = {};
  int? _currentTurn;
  int? _currentStep;

  // Coordinates are keyed by seq; transient rows carry fractional seqs.
  final Map<num, _Coords> _bySeq = {};

  ConversationTimeline snapshot() => _timeline;

  List<int> takeChangedTurns() {
    final turns = [..._changedTurns];
    _changedTurns.clear();
    return turns;
  }

  LocationDataStore _turnStore(int turn) =>
      _turnData.putIfAbsent(turn, LocationDataStore.new);
  LocationDataStore _stepStore(int turn, int step) =>
      _stepData.putIfAbsent('$turn:$step', LocationDataStore.new);

  LocationDataStore _storeFor(LocationData d) => d.scope == LocationScope.turn
      ? _turnStore(d.turn)
      : _stepStore(d.turn, d.step!);

  /// Replace every Definition-owned Location value.
  bool replaceData(List<({String owner, LocationData data})> entries) {
    final turns = <int, Map<String, ({String owner, Object? value})>>{};
    final steps = <String, Map<String, ({String owner, Object? value})>>{};
    for (final (:owner, :data) in entries) {
      final values = data.scope == LocationScope.turn
          ? turns.putIfAbsent(data.turn, () => {})
          : steps.putIfAbsent('${data.turn}:${data.step}', () => {});
      final current = values[data.key];
      if (current != null && current.owner != owner) {
        throw StateError(
          'conversation Location data "${data.key}" is already owned by ${current.owner}',
        );
      }
      values[data.key] = (owner: owner, value: data.value);
    }
    var changed = false;
    for (final turn in {..._turnData.keys, ...turns.keys}) {
      changed = _turnStore(turn).replaceAll(turns[turn] ?? const {}) || changed;
    }
    for (final key in {..._stepData.keys, ...steps.keys}) {
      final turn = int.parse(key.substring(0, key.indexOf(':')));
      final step = int.parse(key.substring(key.indexOf(':') + 1));
      changed =
          _stepStore(turn, step).replaceAll(steps[key] ?? const {}) || changed;
    }
    return changed;
  }

  /// Apply changed Context publications without rebuilding membership.
  bool applyData(List<LocationDataChange> changes) {
    var changed = false;
    for (final c in changes) {
      final p = c.previous;
      if (p == null) continue;
      changed = _storeFor(p).removeOwned(c.owner, p.key) || changed;
    }
    for (final c in changes) {
      final n = c.next;
      if (n == null) continue;
      changed = _storeFor(n).setOwned(c.owner, n.key, n.value) || changed;
    }
    return changed;
  }

  ConversationLocation locationOf(ConvEvent event) =>
      _bySeq[event.seq]?.location ?? _session;

  /// Rebuild timeline facts after replace/prepend.
  Set<num> rebuild(List<ConvEvent> entries) {
    final previousCoordinates = Map<num, _Coords>.of(_bySeq);
    final turns = <int, _TurnDraft>{};
    final coordinates = <num, _Coords>{};
    int? currentTurn;
    int? currentStep;

    _TurnDraft turnDraft(int turn, num seq) {
      var d = turns[turn];
      if (d == null) {
        d = _TurnDraft(turn, seq);
        turns[turn] = d;
      } else if (seq < d.firstSeq) {
        d.firstSeq = seq;
      }
      return d;
    }

    _StepDraft stepDraft(int turn, int step, num seq) {
      final owner = turnDraft(turn, seq);
      var d = owner.steps[step];
      if (d == null) {
        d = _StepDraft(turn, step, seq);
        owner.steps[step] = d;
      } else if (seq < d.firstSeq) {
        d.firstSeq = seq;
      }
      return d;
    }

    for (final event in entries) {
      final explicit = _payloadCoordinates(event);
      if (event.type == 'turn/start') {
        currentTurn = coordinate(event.data['turn']);
        currentStep = null;
      }
      if (event.type == 'step/start') {
        currentTurn = coordinate(event.data['turn']);
        currentStep = coordinate(event.data['step']);
      }
      if (!explicit.session && explicit.turn != null) {
        if (currentTurn != explicit.turn) currentStep = null;
        currentTurn = explicit.turn;
        if (explicit.step != null) currentStep = explicit.step;
      }
      final turn = explicit.session ? null : explicit.turn ?? currentTurn;
      final step =
          explicit.session ||
              event.type == 'turn/start' ||
              event.type == 'turn/end'
          ? null
          : explicit.step ?? (turn == currentTurn ? currentStep : null);
      coordinates[event.seq] = _Coords(
        turn: turn,
        step: turn == null ? null : step,
      );
      if (turn != null) turnDraft(turn, event.seq);
      if (turn != null && step != null) stepDraft(turn, step, event.seq);

      switch (event.type) {
        case 'turn/start':
          turnDraft(coordinate(event.data['turn'])!, event.seq).start = event;
        case 'turn/end':
          turnDraft(coordinate(event.data['turn'])!, event.seq).end = event;
        case 'step/start':
          stepDraft(
            coordinate(event.data['turn'])!,
            coordinate(event.data['step'])!,
            event.seq,
          ).start = event;
        case 'step/end':
          stepDraft(
            coordinate(event.data['turn'])!,
            coordinate(event.data['step'])!,
            event.seq,
          ).end = event;
      }

      if (event.type == 'step/end' &&
          currentTurn == coordinate(event.data['turn']) &&
          currentStep == coordinate(event.data['step'])) {
        currentStep = null;
      }
      if (event.type == 'turn/end' &&
          currentTurn == coordinate(event.data['turn'])) {
        currentTurn = null;
        currentStep = null;
      }
    }

    final previousTurns = _timeline.turns;
    final nextTurns = <int, TurnLocation>{};
    final ordered = turns.values.toList()
      ..sort((a, b) => a.firstSeq.compareTo(b.firstSeq));
    for (final draft in ordered) {
      final previousTurn = previousTurns[draft.turn];
      final previousSteps = {
        for (final s in previousTurn?.steps ?? const <StepLocation>[])
          s.step: s,
      };
      final stepDrafts = draft.steps.values.toList()
        ..sort((a, b) => a.firstSeq.compareTo(b.firstSeq));
      final steps = [
        for (final c in stepDrafts)
          () {
            final value = StepLocation(
              turn: c.turn,
              step: c.step,
              start: c.start,
              end: c.end,
              status: c.end != null
                  ? BoundaryStatus.closed
                  : c.start == null
                  ? BoundaryStatus.unknown
                  : BoundaryStatus.open,
              data: _stepStore(c.turn, c.step),
            );
            final prev = previousSteps[c.step];
            return _sameStep(prev, value) ? prev! : value;
          }(),
      ];
      final value = TurnLocation(
        turn: draft.turn,
        start: draft.start,
        end: draft.end,
        status: draft.end != null
            ? BoundaryStatus.closed
            : draft.start == null
            ? BoundaryStatus.unknown
            : BoundaryStatus.open,
        steps: steps,
        data: _turnStore(draft.turn),
      );
      nextTurns[draft.turn] = _sameTurn(previousTurn, value)
          ? previousTurn!
          : value;
    }

    final nextOrder = [for (final d in ordered) d.turn];
    final turnOrder = _listEq(_timeline.turnOrder, nextOrder)
        ? _timeline.turnOrder
        : nextOrder;
    var sameMap = previousTurns.length == nextTurns.length;
    if (sameMap) {
      for (final e in nextTurns.entries) {
        if (!identical(previousTurns[e.key], e.value)) {
          sameMap = false;
          break;
        }
      }
    }
    for (final turn in {...previousTurns.keys, ...nextTurns.keys}) {
      if (!identical(previousTurns[turn], nextTurns[turn])) {
        _changedTurns.add(turn);
      }
    }
    _timeline = sameMap && identical(turnOrder, _timeline.turnOrder)
        ? _timeline
        : ConversationTimeline(turnOrder, nextTurns);
    _stepsByTurn.clear();
    for (final e in _timeline.turns.entries) {
      _stepsByTurn[e.key] = {for (final s in e.value.steps) s.step: s};
    }
    _bySeq
      ..clear()
      ..addAll(coordinates);
    _seqsByTurn = {};
    for (final event in entries) {
      final c = _bySeq[event.seq]!;
      if (c.turn != null) _indexTurnSeq(c.turn!, event.seq);
      c.location = _resolve(event.seq);
    }
    _currentTurn = currentTurn;
    _currentStep = currentStep;

    final changed = <num>{};
    for (final event in entries) {
      if (!_sameLocation(
        previousCoordinates[event.seq]?.location,
        _bySeq[event.seq]?.location,
      )) {
        changed.add(event.seq);
      }
    }
    return changed;
  }

  /// Append one Turn/Step boundary while revisiting only the owning Turn.
  Set<num> appendBoundary(ConvEvent event) {
    if (!_isBoundary(event.type)) {
      throw StateError(
        'conversation Location boundary expected, received ${event.type}',
      );
    }
    final explicit = _payloadCoordinates(event);
    if (event.type == 'turn/start') {
      _currentTurn = coordinate(event.data['turn']);
      _currentStep = null;
    } else if (event.type == 'step/start') {
      _currentTurn = coordinate(event.data['turn']);
      _currentStep = coordinate(event.data['step']);
    }
    if (explicit.turn != null) {
      if (_currentTurn != explicit.turn) _currentStep = null;
      _currentTurn = explicit.turn;
      if (explicit.step != null) _currentStep = explicit.step;
    }
    final turnNumber = explicit.turn ?? _currentTurn;
    if (turnNumber == null) {
      throw StateError('conversation boundary ${event.type} has no turn');
    }
    final stepNumber = event.type == 'turn/start' || event.type == 'turn/end'
        ? null
        : explicit.step ?? (turnNumber == _currentTurn ? _currentStep : null);
    _bySeq[event.seq] = _Coords(
      turn: turnNumber,
      step: stepNumber,
      location: _bySeq[event.seq]?.location,
    );
    _indexTurnSeq(turnNumber, event.seq);

    final previousTurn = _timeline.turns[turnNumber];
    var steps = previousTurn?.steps ?? const <StepLocation>[];
    if (event.type == 'step/start' || event.type == 'step/end') {
      final number = coordinate(event.data['step'])!;
      final indexed = _stepsByTurn.putIfAbsent(turnNumber, () => {});
      final previousStep = indexed[number];
      final candidate = StepLocation(
        turn: turnNumber,
        step: number,
        start: event.type == 'step/start' ? event : previousStep?.start,
        end: event.type == 'step/end' ? event : previousStep?.end,
        status: event.type == 'step/end' || previousStep?.end != null
            ? BoundaryStatus.closed
            : BoundaryStatus.open,
        data: _stepStore(turnNumber, number),
      );
      final next = _sameStep(previousStep, candidate)
          ? previousStep!
          : candidate;
      indexed[number] = next;
      final index = steps.indexWhere((s) => s.step == number);
      steps = index < 0
          ? [...steps, next]
          : [
              for (var i = 0; i < steps.length; i++)
                i == index ? next : steps[i],
            ];
    }
    final candidate = TurnLocation(
      turn: turnNumber,
      start: event.type == 'turn/start' ? event : previousTurn?.start,
      end: event.type == 'turn/end' ? event : previousTurn?.end,
      status: event.type == 'turn/end' || previousTurn?.end != null
          ? BoundaryStatus.closed
          : event.type == 'turn/start' || previousTurn?.start != null
          ? BoundaryStatus.open
          : BoundaryStatus.unknown,
      steps: steps,
      data: _turnStore(turnNumber),
    );
    final turn = _sameTurn(previousTurn, candidate) ? previousTurn! : candidate;
    final turns = Map<int, TurnLocation>.of(_timeline.turns);
    turns[turnNumber] = turn;
    final turnOrder = previousTurn == null
        ? [..._timeline.turnOrder, turnNumber]
        : _timeline.turnOrder;
    _timeline = ConversationTimeline(turnOrder, turns);
    if (!identical(turn, previousTurn)) _changedTurns.add(turnNumber);

    final changed = <num>{};
    for (final seq in _seqsByTurn[turnNumber] ?? const <num>{}) {
      final c = _bySeq[seq]!;
      final prev = c.location;
      final next = _resolve(seq);
      c.location = next;
      if (!_sameLocation(prev, next)) changed.add(seq);
    }

    if (event.type == 'step/end' &&
        _currentTurn == coordinate(event.data['turn']) &&
        _currentStep == coordinate(event.data['step'])) {
      _currentStep = null;
    }
    if (event.type == 'turn/end' &&
        _currentTurn == coordinate(event.data['turn'])) {
      _currentTurn = null;
      _currentStep = null;
    }
    return changed;
  }

  /// Index one non-boundary tail event.
  void appendNonBoundary(ConvEvent event) {
    final explicit = _payloadCoordinates(event);
    if (explicit.session) {
      _bySeq[event.seq] = _Coords(location: _session);
      return;
    }
    if (explicit.turn != null) {
      if (_currentTurn != explicit.turn) _currentStep = null;
      _currentTurn = explicit.turn;
      if (explicit.step != null) _currentStep = explicit.step;
    }
    final turn = explicit.turn ?? _currentTurn;
    final step = explicit.step ?? (turn == _currentTurn ? _currentStep : null);
    final c = explicit.turn != null && explicit.step != null
        ? explicit
        : _Coords(turn: turn, step: turn == null ? null : step);
    _bySeq[event.seq] = c;
    if (turn != null) _indexTurnSeq(turn, event.seq);
    c.location = _resolve(event.seq);
  }

  /// Remove indexed Assistant transients without rebuilding the timeline.
  void removeAssistantTransients(List<ConvEvent> events) {
    for (final event in events) {
      final turn = _bySeq[event.seq]?.turn;
      if (turn != null) {
        final seqs = _seqsByTurn[turn];
        seqs?.remove(event.seq);
        if (seqs != null && seqs.isEmpty) _seqsByTurn.remove(turn);
      }
      _bySeq.remove(event.seq);
    }
  }

  /// Index one durable Assistant settlement inserted before a visible tail.
  void insertAssistantSettlement(ConvEvent event) {
    final c = _Coords(
      turn: coordinate(event.data['turn']),
      step: coordinate(event.data['step']),
    );
    _bySeq[event.seq] = c;
    _indexTurnSeq(c.turn!, event.seq);
    c.location = _resolve(event.seq);
  }

  void _indexTurnSeq(int turn, num seq) =>
      _seqsByTurn.putIfAbsent(turn, () => {}).add(seq);

  ConversationLocation _resolve(num seq) {
    final c = _bySeq[seq];
    if (c?.turn == null) return _session;
    final turn = _timeline.turns[c!.turn!];
    if (turn == null) return _unresolved;
    if (c.step == null) return TurnScopedLocation(turn);
    final step = _stepsByTurn[c.turn!]?[c.step!];
    return step == null
        ? TurnScopedLocation(turn)
        : StepScopedLocation(turn, step);
  }
}

bool _listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
