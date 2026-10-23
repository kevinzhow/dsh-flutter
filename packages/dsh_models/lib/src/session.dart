import 'dart:async';

import 'package:dsh_client/dsh_client.dart';

import 'assistant_stream.dart';
import 'event_window.dart';
import 'journal.dart';
import 'observable.dart';
import 'projection_store.dart';
import 'transport.dart';

/// History-open lifecycle of a Session event window.
enum OpenState { cold, loading, open, error }

/// Minimum message count for ordinary history windows (dsh `PAGE_MESSAGES`).
const int pageMessages = 50;

/// dsh `HISTORY_PAGE_OPTIONS`: the window requested by follow and by repairs.
const Map<String, Object?> historyPageOptions = {
  'maxMessages': 500,
  'turnWindow': {'minMessages': pageMessages, 'minTurns': 2},
};

/// A local prompt echo shown before durable admission (client memory only).
class PendingSubmission {
  const PendingSubmission(this.requestId, this.text, this.time);
  final String requestId;
  final String text;
  final DateTime time;
}

/// Immutable Session lifecycle and control snapshot (dsh `SessionSnapshot`).
class SessionSnapshot {
  const SessionSnapshot({
    required this.sessionId,
    this.pendingSubmissions = const [],
    this.running = false,
    this.removed = false,
    this.openState = OpenState.cold,
    this.openError,
    this.hasMore = false,
    this.loadingOlder = false,
    this.promptError,
    this.blank = true,
    this.lastAgentError,
    this.promptAttempted = false,
    this.awaitingFirstTurn = false,
  });

  final String sessionId;
  final List<PendingSubmission> pendingSubmissions;
  final bool running;
  final bool removed;
  final OpenState openState;
  final Object? openError;
  final bool hasMore;
  final bool loadingOlder;
  final Object? promptError;
  final bool blank;
  final String? lastAgentError;
  final bool promptAttempted;
  final bool awaitingFirstTurn;
}

/// Owns one session's contiguous event window, lifecycle state and observable
/// snapshot (dsh `Session`). Reached through `SessionManager`, which keeps it
/// resident so its follow stream keeps running off-screen.
class Session {
  Session(
    this.sessionId,
    this._transport, {
    ProjectionStore? projections,
    this.pageOptions = historyPageOptions,
    Map<String, Object?>? address,
  }) : _addressOverride = address,
       projections = projections ?? ProjectionStore() {
    _snapshot = Observable(_build());
  }

  final String sessionId;
  final SessionTransport _transport;

  /// The history window requested by follow and used for repairs and pages
  /// (dsh `HISTORY_PAGE_OPTIONS`); tests and vectors pick a small window.
  final Map<String, Object?> pageOptions;

  /// Manager-owned when created through `SessionManager` (control frames route
  /// there and values outlive instantiation).
  final ProjectionStore projections;

  /// Contiguous history and live tail consumed by conversation assembly.
  final MutableEventSource eventSource = MutableEventSource();

  late final Observable<SessionSnapshot> _snapshot;
  Observable<SessionSnapshot> get snapshot => _snapshot;

  final ClientAssistantStream _assistant = ClientAssistantStream();
  SessionJournal? _journal;
  Future<void>? _openFuture;
  int _openGeneration = 0;
  OpenState _openState = OpenState.cold;
  Object? _openError;
  bool _hasMore = false;
  bool _loadingOlder = false;
  bool _running = false;
  bool _removed = false;
  bool _blank = true;
  bool _promptAttempted = false;
  bool _firstPromptPendingTurn = false;
  Object? _promptError;
  String? _lastAgentError;
  List<PendingSubmission> _pending = const [];

  SessionSnapshot _build() => SessionSnapshot(
    sessionId: sessionId,
    pendingSubmissions: _pending,
    running: _running,
    removed: _removed,
    openState: _openState,
    openError: _openError,
    hasMore: _hasMore,
    loadingOlder: _loadingOlder,
    promptError: _promptError,
    blank: _blank,
    lastAgentError: _lastAgentError,
    promptAttempted: _promptAttempted,
    awaitingFirstTurn: _firstPromptPendingTurn,
  );

  void _dirty() => _snapshot.set(_build());

  final Map<String, Object?>? _addressOverride;

  /// The durable address this Session follows: the ordinary session, or one
  /// direct subagent child `{kind: 'subagent', parentSessionId,
  /// childSessionId, mode}`.
  Map<String, Object?> get _address =>
      _addressOverride ?? {'kind': 'session', 'sessionId': sessionId};

  /// Open follow: resolves when the first complete window is published
  /// (single-flight; later calls share the same future).
  Future<void> open() => _openFuture ??= _doOpen(++_openGeneration);

  Future<void> _doOpen(int generation) async {
    _openState = OpenState.loading;
    _openError = null;
    _dirty();
    late final SessionJournal journal;
    journal = SessionJournal(
      openFollow: () => _transport.follow(
        () => {'address': _address, 'assistantStream': true, ...pageOptions},
      ),
      readPage: (request) => _transport.page({'address': _address, ...request}),
      publish: (change) {
        if (generation != _openGeneration || _journal != journal) return;
        _accept(change);
      },
      failed: (error) {
        if (generation != _openGeneration || _journal != journal) return;
        _openState = OpenState.error;
        _openError = error;
        _dirty();
      },
    );
    _journal = journal;
    try {
      await journal.open(pageOptions);
      if (generation != _openGeneration || _journal != journal) return;
      _openState = OpenState.open;
    } on Object catch (e) {
      if (generation != _openGeneration || _journal != journal) return;
      _journal = null;
      _openState = OpenState.error;
      _openError = e;
      _openFuture = null;
    } finally {
      if (generation == _openGeneration) _dirty();
    }
  }

  void _accept(JournalChange change) {
    switch (change) {
      case JournalReplace():
        final visible = _assistant.replace(
          change.entries,
          change.assistantStream,
        );
        _hasMore = change.hasMore;
        if (visible.any((e) => e.type == 'turn/start')) {
          _firstPromptPendingTurn = false;
        }
        final proj = change.projections;
        if (proj != null) {
          projections.seed(
            proj['asOfSeq']! as num,
            Map<String, Object?>.from(proj['values']! as Map),
          );
        }
        eventSource.replace(visible, change.hasMore);
        _observeEchoes(visible);
        _dirty();
      case JournalPrepend():
        _hasMore = change.hasMore;
        eventSource.prepend(change.entries, change.hasMore);
        _dirty();
      case JournalAppend():
        _applyAssistant(_assistant.acceptDurable(change.entry));
      case JournalNotification():
        _applyAssistant(_assistant.acceptFrame(change.frame));
    }
  }

  void _applyAssistant(AssistantResult? result) {
    switch (result) {
      case null:
        return;
      case Rebaseline():
        final journal = _journal;
        scheduleMicrotask(() {
          if (journal != null && _journal == journal) journal.restart();
        });
      case SettleAssistant(:final attemptId, :final entry):
        eventSource.settleAssistant(attemptId, entry);
        _observeEchoes([entry]);
        _dirty();
      case AbandonAttempt(:final attemptId):
        eventSource.settleAssistant(attemptId, null);
        _dirty();
      case PublishDurable(:final entry, :final retireAttemptId):
        if (entry.type == 'turn/start') _firstPromptPendingTurn = false;
        eventSource.append(entry);
        _observeEchoes([entry]);
        if (retireAttemptId != null) {
          eventSource.settleAssistant(retireAttemptId, null);
        }
        _dirty();
      case TransientChunk(:final entry):
        eventSource.append(entry);
        _dirty();
    }
  }

  /// A durable `user/message` echoing a `requestId` retires its local echo.
  void _observeEchoes(List<EventEntry> entries) {
    if (_pending.isEmpty) return;
    final seen = <String>{};
    for (final e in entries) {
      if (e.type != 'user/message') continue;
      final source = (e.data as Map<String, Object?>?)?['source'];
      if (source is Map<String, Object?> && source['rpcId'] is String) {
        seen.add(source['rpcId']! as String);
      }
    }
    if (seen.isEmpty) return;
    _pending = _pending.where((p) => !seen.contains(p.requestId)).toList();
  }

  /// Read and prepend one older message-aligned page.
  Future<void> loadOlder() async {
    final journal = _journal;
    if (journal == null || _loadingOlder || !_hasMore) return;
    final before = eventSource.window.entries
        .where((e) => !e.transient)
        .map((e) => e.seq)
        .fold<num?>(null, (a, b) => a == null || b < a ? b : a);
    _loadingOlder = true;
    _dirty();
    try {
      await journal.prepend({
        if (before != null) 'beforeSeq': before,
        ...pageOptions,
      });
    } finally {
      _loadingOlder = false;
      _dirty();
    }
  }

  /// `session/prompt` (mode `queue`, or `steer` to inject into the running
  /// turn). A local echo is shown until the durable `user/message` arrives.
  Future<void> prompt(String text, {String mode = 'queue'}) async {
    final requestId = 'req-${randomUuid()}';
    _promptAttempted = true;
    _promptError = null;
    _blank = false;
    if (_openState == OpenState.open && eventSource.window.entries.isEmpty) {
      _firstPromptPendingTurn = true;
    }
    _pending = [
      ..._pending,
      PendingSubmission(requestId, text, DateTime.now()),
    ];
    _dirty();
    try {
      await _transport.prompt({
        'requestId': requestId,
        'sessionId': sessionId,
        'mode': mode,
        'content': [
          {'type': 'text', 'text': text},
        ],
      });
    } on Object catch (e) {
      _promptError = e;
      _pending = _pending.where((p) => p.requestId != requestId).toList();
      _firstPromptPendingTurn = false;
      _dirty();
      rethrow;
    }
  }

  /// `session/cancel`: cancel the active turn without dropping the inbox.
  Future<void> cancel() async {
    try {
      await _transport.cancel(sessionId);
    } on Object catch (e) {
      _promptError = e;
      _dirty();
      rethrow;
    }
  }

  // ---- Manager-only entry points ----

  void handleRunning(bool running) {
    if (running && _blank) _blank = false;
    if (running) _firstPromptPendingTurn = false;
    if (_running == running) return;
    _running = running;
    _dirty();
  }

  void handleBlank(bool blank) {
    if (blank == _blank) return;
    if (blank && (_promptAttempted || _running)) return;
    _blank = blank;
    _dirty();
  }

  void handleRemoved() {
    _removed = true;
    _dirty();
  }

  void handleAgentError(String message) {
    _lastAgentError = message;
    _dirty();
  }

  Future<void> dispose() async {
    _openGeneration++;
    final journal = _journal;
    _journal = null;
    await journal?.dispose();
  }
}
