import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_goals.dart';

import '../generated/session_events.g.dart';
import '../observable.dart';
import '../session.dart';
import '../settings/host_remotes.dart';

typedef GoalSnapshot = GoalChangeEventDataGoalChangeGoal;

class GoalActivationSnapshot {
  const GoalActivationSnapshot({this.id, this.revision, this.activation});
  final String? id, activation;
  final int? revision;
}

/// Mounted-session goal owner. Durable lifecycle comes only from the Host
/// projection; process-local activation is ordered against RPCs and events.
class GoalModel {
  GoalModel({
    required this.session,
    required this.remotes,
    required this.ensureOpen,
  }) {
    _running = session.snapshot.value.running;
    _projection = session.projections.changes.listen(
      (_) => _projectionChanged(),
    );
    _session = session.snapshot.changes.listen((next) {
      if (next.running == _running) return;
      _running = next.running;
      _startRead();
    });
    _events = remotes.emitted('goal/activation-changed').listen((event) {
      final value = event.args.firstOrNull;
      if (value is! Map || value['sessionId'] != session.sessionId) return;
      _eventEpoch++;
      _readEpoch++;
      final next = value['goal'];
      if (next is Map &&
          next['id'] is String &&
          next['revision'] is int &&
          next['activation'] is String) {
        activation = GoalActivationSnapshot(
          id: next['id'] as String,
          revision: next['revision'] as int,
          activation: next['activation'] as String,
        );
      } else {
        activation = const GoalActivationSnapshot();
      }
      _notify();
    });
    _resets = remotes.generations.listen((_) {
      _eventEpoch++;
      _projectionEpoch++;
      _startRead();
    });
    _projectionChanged();
  }
  final Session session;
  final HostRemotes remotes;
  final Future<void> Function() ensureOpen;
  final changed = Observable(0);
  GoalSnapshot? goal;
  GoalActivationSnapshot activation = const GoalActivationSnapshot();
  String? error, clearedId;
  bool pending = false, _disposed = false, _running = false;
  int _eventEpoch = 0, _projectionEpoch = 0, _readEpoch = 0;
  Object? _lastProjection;
  bool _projectionSeen = false;
  StreamSubscription<Object?>? _projection, _session, _events, _resets;
  void _notify() {
    if (!_disposed) changed.set(changed.value + 1);
  }

  GoalSnapshot? _projected() {
    final projection = session.projections.get('goal');
    if (projection is! Map || projection['goal'] == null) return null;
    try {
      return GoalSnapshot.fromJson(projection['goal']);
    } on FormatException {
      return null;
    }
  }

  void _projectionChanged() {
    final raw = session.projections.get('goal');
    if (_projectionSeen && identical(raw, _lastProjection)) return;
    _projectionSeen = true;
    _lastProjection = raw;
    _projectionEpoch++;
    final previous = goal?.id;
    goal = _projected();
    if (goal?.id != previous) {
      error = null;
      clearedId = null;
    }
    if (goal?.phase.value != 'active') {
      activation = const GoalActivationSnapshot();
    } else if (activation.id != goal!.id ||
        activation.revision != goal!.revision) {
      activation = GoalActivationSnapshot(
        id: goal!.id,
        revision: goal!.revision,
      );
    }
    _notify();
    _startRead();
  }

  String? get currentActivation =>
      activation.id == goal?.id && activation.revision == goal?.revision
      ? activation.activation
      : null;
  void _startRead() {
    if (_disposed || goal?.phase.value != 'active') return;
    final read = ++_readEpoch,
        event = _eventEpoch,
        projection = _projectionEpoch;
    unawaited(
      Future<void>(() async {
        try {
          await ensureOpen();
          if (_disposed) return;
          final next = await remotes.goals.get(session.sessionId);
          if (_disposed ||
              read != _readEpoch ||
              event != _eventEpoch ||
              projection != _projectionEpoch) {
            return;
          }
          if (next != null) {
            activation = GoalActivationSnapshot(
              id: next.id,
              revision: next.revision,
              activation: next.activation.value,
            );
            _notify();
          }
        } on Object {
          /* A failed live read never overwrites authoritative state. */
        }
      }),
    );
  }

  /// CAS ref is re-read from this exact Session's current projection at the
  /// gesture, so a stale editor cannot target another goal identity.
  Future<bool> act(
    String action, {
    String? objective,
    String? expectedId,
  }) async {
    if (_disposed || pending) return false;
    final current = _projected();
    if (current == null || (expectedId != null && expectedId != current.id)) {
      return false;
    }
    final ref = GoalRef(id: current.id, revision: current.revision);
    pending = true;
    error = null;
    _notify();
    try {
      switch (action) {
        case 'edit':
          await remotes.goals.edit(
            session.sessionId,
            ref,
            EditGoalRequest(objective: objective),
          );
        case 'pause':
          await remotes.goals.pause(session.sessionId, ref);
        case 'resume':
          await remotes.goals.resume(session.sessionId, ref);
        case 'complete':
          await remotes.goals.complete(session.sessionId, ref);
        case 'clear':
          await remotes.goals.clear(session.sessionId, ref);
          if (!_disposed && goal?.id == current.id) clearedId = current.id;
        default:
          throw ArgumentError.value(action, 'action');
      }
      return !_disposed;
    } on Object catch (e) {
      if (!_disposed && goal?.id == current.id) {
        error = e is RemoteException ? '${e.message} (${e.code})' : '$e';
      }
      return false;
    } finally {
      pending = false;
      _notify();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _readEpoch++;
    await _projection?.cancel();
    await _session?.cancel();
    await _events?.cancel();
    await _resets?.cancel();
    await changed.dispose();
  }
}
