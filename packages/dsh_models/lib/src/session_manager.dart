import 'dart:async';

import 'package:dsh_client/dsh_client.dart';

import 'observable.dart';
import 'projection_store.dart';
import 'session.dart';
import 'session_summary.dart';
import 'transport.dart';

enum ListState { idle, loading, error }

enum ListPhase { pending, ready }

/// One row of the visible session list: the host summary plus the `title`
/// projection value.
class SessionListEntry {
  const SessionListEntry(this.summary, this.title);
  final SessionSummary summary;
  final String? title;
  String get sessionId => summary.sessionId;
}

/// Immutable list snapshot (dsh `SessionListSnapshot`).
class SessionListSnapshot {
  const SessionListSnapshot({
    this.items = const [],
    this.state = ListState.idle,
    this.phase = ListPhase.pending,
    this.error,
  });
  final List<SessionListEntry> items;
  final ListState state;
  final ListPhase phase;
  final Object? error;
}

/// Owns the list baseline, live list/control updates, lazy [Session]
/// instances, projection stores, and the conflict ordering between pulls and
/// later updates (dsh `SessionManager`).
class SessionManager {
  SessionManager(this._transport);

  final SessionTransport _transport;

  final Map<String, Session> _sessions = {};
  final Map<String, ProjectionStore> _stores = {};
  List<SessionSummary> _summaries = [];
  ListState _state = ListState.idle;
  ListPhase _phase = ListPhase.pending;
  Object? _error;
  Future<void>? _inflight;
  List<ListMutation>? _mutations;
  bool _disposed = false;

  final Observable<SessionListSnapshot> list = Observable(
    const SessionListSnapshot(),
  );

  StreamSubscription<GenerationFrame>? _controlSub;
  StreamSubscription<HostEvent>? _eventSub;
  StreamSubscription<ConnectionGeneration?>? _genSub;

  /// Begin consuming the control stream, forwarded `api-session/*` events and
  /// generation changes. A baseline refresh runs on every new generation
  /// (dsh `handleConnected`).
  void start() {
    _controlSub ??= _transport.control().listen(_onControl);
    _eventSub ??= _transport.hostEvents.listen(_onHostEvent);
    _genSub ??= _transport.generations.listen((g) {
      if (g != null) handleConnected();
    });
    if (_transport.generation != null) handleConnected();
  }

  Future<void> dispose() async {
    _disposed = true;
    await _controlSub?.cancel();
    await _eventSub?.cancel();
    await _genSub?.cancel();
    for (final s in _sessions.values) {
      await s.dispose();
    }
    _sessions.clear();
    await _projectionChanges.close();
  }

  final StreamController<String> _projectionChanges =
      StreamController<String>.broadcast(sync: true);

  /// The id of a session whose projection values changed (control frames and
  /// follow snapshots alike: they share one store per session).
  Stream<String> get projectionChanges => _projectionChanges.stream;

  ProjectionStore _store(String id) => _stores.putIfAbsent(id, () {
    final store = ProjectionStore();
    store.changes.listen((_) {
      if (!_projectionChanges.isClosed) _projectionChanges.add(id);
    });
    return store;
  });

  /// Ids of the sessions that have projection values.
  Iterable<String> get projectionSessionIds => _stores.keys;

  /// The resident [Session] for [sessionId] (created lazily, never opened
  /// implicitly: call `Session.open`).
  Session get(String sessionId) => _sessions.putIfAbsent(sessionId, () {
    final session = Session(
      sessionId,
      _transport,
      projections: _store(sessionId),
    );
    final summary = _summaries
        .where((s) => s.sessionId == sessionId)
        .firstOrNull;
    if (summary != null) {
      session.handleBlank(summary.blank);
      session.handleRunning(summary.running);
    }
    return session;
  });

  /// The resident read-only [Session] of one direct subagent child, addressed
  /// as dsh addresses it (`kind: subagent` with the exact parent and mode).
  /// Never opened implicitly.
  Session getSubagent({
    required String parentSessionId,
    required String childSessionId,
    required String mode,
  }) => _sessions.putIfAbsent(
    'subagent:$parentSessionId:$childSessionId:$mode',
    () => Session(
      childSessionId,
      _transport,
      projections: _store(childSessionId),
      address: {
        'kind': 'subagent',
        'parentSessionId': parentSessionId,
        'childSessionId': childSessionId,
        'mode': mode,
      },
    ),
  );

  /// The current list summary of [sessionId], if the host listed it.
  SessionSummary? summaryOf(String sessionId) =>
      _summaries.where((s) => s.sessionId == sessionId).firstOrNull;

  /// Values cached for [sessionId] (control baseline, list blocks, follow).
  Map<String, Object?> projectionValues(String sessionId) =>
      _stores[sessionId]?.values ?? const {};

  // ---- List API ----

  /// Full refresh via `session/list`, single-flight within one generation.
  Future<void> refreshList() {
    final running = _inflight;
    if (running != null) return running;
    _state = ListState.loading;
    _error = null;
    final established = _summaries;
    final mutations = <ListMutation>[];
    _mutations = mutations;
    _publish();
    final future = () async {
      try {
        final result = await _transport.list();
        if (!identical(_mutations, mutations)) return;
        final items = [
          for (final i in result['items']! as List)
            SessionSummary.fromWire(i! as Map<String, Object?>),
        ];
        final baseline = _phase == ListPhase.pending
            ? [...items]
            : mergeOrderedBaseline(established, items, (s) => s.sessionId);
        _summaries = mutations.fold(baseline, applyMutation);
        _state = ListState.idle;
        _phase = ListPhase.ready;
        for (final s in _summaries) {
          final session = _sessions[s.sessionId];
          session?.handleBlank(s.blank);
          session?.handleRunning(s.running);
        }
        for (final s in items) {
          final block = s.projections;
          if (block != null) _applyListBlock(s.sessionId, block);
        }
      } on Object catch (e) {
        if (!identical(_mutations, mutations)) return;
        _state = ListState.error;
        _error = e;
      } finally {
        if (identical(_mutations, mutations)) {
          _mutations = null;
          _inflight = null;
          _publish();
        }
      }
    }();
    _inflight = future;
    return future;
  }

  /// `session/create`; the new row appears via the `api-session/added` event
  /// (or immediately as a placeholder if it is slower).
  Future<Session> create({
    String? cwd,
    String? workspaceId,
    String? agentPreset,
  }) async {
    final value = await _transport.create({
      if (cwd != null) 'cwd': cwd,
      if (workspaceId != null) 'workspaceId': workspaceId,
      if (agentPreset != null) 'agentPreset': agentPreset,
    });
    final id = value['sessionId']! as String;
    if (_summaries.every((s) => s.sessionId != id)) {
      _record(
        UpsertMutation(
          SessionSummary(
            sessionId: id,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            running: false,
            blank: true,
            agentAvailable: true,
            cwd: cwd,
          ),
        ),
      );
    }
    return get(id);
  }

  // ---- Live sinks ----

  void _onControl(GenerationFrame frame) {
    if (frame is! StreamItem) return;
    final v = frame.value;
    if (v is! Map<String, Object?>) return;
    handleControlFrame(v);
  }

  /// A control baseline (`{type:'baseline', value:{projections}}`) or one
  /// `projection` update.
  void handleControlFrame(Map<String, Object?> frame) {
    if (frame['type'] == 'baseline') {
      final value = frame['value']! as Map<String, Object?>;
      final projections = value['projections']! as Map<String, Object?>;
      for (final e in projections.entries) {
        final block = e.value! as Map<String, Object?>;
        _store(e.key).seed(
          block['asOfSeq']! as num,
          Map<String, Object?>.from(block['values']! as Map),
        );
      }
    } else if (frame['type'] == 'projection') {
      _store(frame['sessionId']! as String)
          .apply(frame['key']! as String, frame['value'], frame['seq']! as num);
    }
    _publish();
  }

  void _onHostEvent(HostEvent e) {
    if (e is! EmitEvent) return;
    switch (e.event) {
      case 'api-session/added':
        handleSessionAdded(
          SessionSummary.fromWire(e.args[0]! as Map<String, Object?>),
        );
      case 'api-session/removed':
        handleSessionRemoved(e.args[0]! as String);
      case 'api-session/status':
        handleSessionStatus(e.args[0]! as String, e.args[1] == true);
      case 'api-session/activity':
        handleSessionActivity(e.args[0]! as String, e.args[1]! as num);
      case 'api-session/error':
        handleSessionError(e.args[0]! as String, '${e.args[1]}');
    }
  }

  void handleSessionAdded(SessionSummary summary) {
    _record(UpsertMutation(summary));
    _sessions[summary.sessionId]?.handleBlank(summary.blank);
    final block = summary.projections;
    if (block != null) _applyListBlock(summary.sessionId, block);
  }

  void handleSessionRemoved(String sessionId) {
    _record(RemoveMutation(sessionId));
    _sessions[sessionId]?.handleRemoved();
    _stores.remove(sessionId);
  }

  void handleSessionStatus(String sessionId, bool running) {
    _record(StatusMutation(sessionId, running, true));
    _sessions[sessionId]?.handleRunning(running);
  }

  void handleSessionActivity(String sessionId, num updatedAt) =>
      _record(ActivityMutation(sessionId, updatedAt));

  void handleSessionError(String sessionId, String message) =>
      _sessions[sessionId]?.handleAgentError(message);

  /// Repair a re-established generation: discard old projection cuts and pull
  /// the list baseline again; open follows resume independently.
  void handleConnected() {
    for (final s in _stores.values) {
      s.clear();
    }
    _mutations = null;
    _inflight = null;
    unawaited(refreshList());
  }

  void _applyListBlock(String sessionId, Map<String, Object?> block) {
    final store = _store(sessionId);
    final values = Map<String, Object?>.from(
      (block['values'] ?? const {}) as Map,
    );
    switch (block['kind']) {
      case 'sequenced':
        final seq = block['asOfSeq']! as num;
        for (final e in values.entries) {
          store.apply(e.key, e.value, seq);
        }
      case 'cached':
        store.applyCached(values);
    }
  }

  void _record(ListMutation m) {
    if (_disposed) return;
    _mutations?.add(m);
    _summaries = applyMutation(_summaries, m);
    _publish();
  }

  void _publish() {
    list.set(
      SessionListSnapshot(
        items: [
          for (final s in _summaries)
            SessionListEntry(s, _stores[s.sessionId]?.get('title') as String?),
        ],
        state: _state,
        phase: _phase,
        error: _error,
      ),
    );
  }
}
