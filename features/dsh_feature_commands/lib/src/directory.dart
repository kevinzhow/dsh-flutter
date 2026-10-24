import 'dart:async';

import 'package:dsh_client/generated_commands.dart' show CommandDescriptor;
import 'package:dsh_conversation/dsh_conversation.dart';

import 'resolution.dart';

export 'package:dsh_client/generated_commands.dart' show CommandDescriptor;

/// cold = never pulled; pending = pull in flight with nothing servable; ready =
/// snapshot serving (a soft-invalidate repull keeps this status); failed = the
/// last winning pull rejected, snapshot dropped.
enum DirectoryStatus { cold, pending, ready, failed }

/// Injected pull (the runtime binds `commands/list`).
typedef FetchCommands = Future<List<CommandDescriptor>> Function(
  String sessionId,
);

class _Entry {
  DirectoryStatus state = DirectoryStatus.cold;
  List<CommandDescriptor> commands = const [];
  int epoch = 0;
  Object? lastError;
  List<void Function()> waiters = [];
}

/// The command-directory cache keyed by session (dsh `CommandDirectory`): one
/// entry per served catalog with single-flight pulls, soft and hard
/// invalidation and an epoch guard, so only the latest pull publishes.
class CommandDirectory {
  CommandDirectory(this._fetch);

  final FetchCommands _fetch;
  final Map<String, _Entry> _entries = {};

  _Entry _entry(String sessionId) =>
      _entries.putIfAbsent(sessionId, _Entry.new);

  DirectoryStatus status(String sessionId) =>
      _entries[sessionId]?.state ?? DirectoryStatus.cold;

  /// Synchronous lookup over one session's ready catalog; exact names precede
  /// localized aliases. Null when absent or the entry is not ready.
  CommandDescriptor? resolve(String sessionId, String name) {
    final entry = _entries[sessionId];
    if (entry == null || entry.state != DirectoryStatus.ready) return null;
    return resolveCommand(name, entry.commands);
  }

  /// Soft invalidation (`commands/change`): a background repull on every
  /// touched key; ready snapshots keep serving.
  void invalidateAll() {
    for (final key in _entries.keys.toList()) {
      unawaited(refresh(key));
    }
  }

  /// Drop one session's composition-specific snapshot and prewarm its
  /// replacement (the agent preset changed).
  void resetSession(String sessionId) {
    final entry = _entry(sessionId);
    entry
      ..state = DirectoryStatus.cold
      ..commands = const []
      ..lastError = null;
    unawaited(refresh(sessionId));
  }

  /// Hard reset on reconnect: every entry drops its snapshot and prewarms.
  void resetConnected() {
    for (final MapEntry(:key, :value) in _entries.entries.toList()) {
      value
        ..state = DirectoryStatus.cold
        ..commands = const [];
      unawaited(refresh(key));
    }
  }

  /// Fire-and-forget prewarm of one session.
  void warm(String sessionId) {
    final entry = _entry(sessionId);
    if (entry.state == DirectoryStatus.cold ||
        entry.state == DirectoryStatus.failed) {
      unawaited(refresh(sessionId));
    }
  }

  /// Start one pull for one session. It publishes ready or failed only while it
  /// is still the key's latest pull; a ready snapshot is not demoted while the
  /// pull flies.
  Future<void> refresh(String sessionId) async {
    final entry = _entry(sessionId);
    final epoch = ++entry.epoch;
    if (entry.state != DirectoryStatus.ready) {
      entry.state = DirectoryStatus.pending;
    }
    try {
      final commands = await _fetch(sessionId);
      if (epoch != entry.epoch) return;
      entry
        ..commands = commands
        ..state = DirectoryStatus.ready
        ..lastError = null;
    } on Object catch (error) {
      if (epoch != entry.epoch) return;
      entry
        ..commands = const []
        ..state = DirectoryStatus.failed
        ..lastError = error;
    } finally {
      if (epoch == entry.epoch) {
        final woken = entry.waiters;
        entry.waiters = [];
        for (final w in woken) {
          w();
        }
      }
    }
  }

  /// Strong-wait until one session's catalog is servable (the enter-adjudication
  /// rule: the directory must be reached): ready returns at once; cold and
  /// failed launch a fresh pull; pending joins the flying one. Rejects when the
  /// awaited pull fails or [signal] aborts.
  Future<List<CommandDescriptor>> ensureReady(
    String sessionId,
    AbortSignal signal,
  ) async {
    final entry = _entry(sessionId);
    while (true) {
      if (entry.state == DirectoryStatus.ready) return entry.commands;
      if (entry.state != DirectoryStatus.pending) unawaited(refresh(sessionId));
      await _settled(entry, signal);
      if (entry.state == DirectoryStatus.failed) {
        throw StateError('command directory warmup failed: ${entry.lastError}');
      }
      // Still pending (the awaited pull was superseded): wait for the winner.
    }
  }
}

Future<void> _settled(_Entry entry, AbortSignal signal) {
  if (signal.aborted) {
    return Future.error(signal.reason ?? const AbortedException());
  }
  final done = Completer<void>();
  late final void Function() waiter;
  void onAbort() {
    if (done.isCompleted) return;
    entry.waiters.remove(waiter);
    done.completeError(signal.reason ?? const AbortedException());
  }

  waiter = () {
    if (done.isCompleted) return;
    signal.removeListener(onAbort);
    done.complete();
  };
  signal.onAbort(onAbort);
  entry.waiters.add(waiter);
  return done.future;
}
