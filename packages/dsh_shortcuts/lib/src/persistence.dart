/// Serialized preference transactions (dsh `shortcuts/src/persistence.ts`);
/// storage owners publish only accepted writes or read diagnostics.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'binding.dart';
import 'configuration.dart';

/// Read state retains the last accepted document on failure; loading does not
/// enable commands.
enum ShortcutConfigStatus { loading, ready, unreadable }

/// How a read failed.
enum ShortcutReadError { read, invalid, future }

/// Opaque accepted-state identity, invalidated by configuration and catalog changes.
class ShortcutConfigSnapshot {
  const ShortcutConfigSnapshot({
    required this.revision,
    required this.sequence,
    required this.document,
    required this.status,
    required this.error,
    required this.usingDefaults,
  });

  final String revision;

  /// Monotonic within one storage-owner lifetime; clients discard out-of-order replies.
  final int sequence;
  final ShortcutDocument document;
  final ShortcutConfigStatus status;
  final ShortcutReadError? error;
  final bool usingDefaults;

  ShortcutConfigSnapshot copyWith({
    String? revision,
    int? sequence,
    ShortcutDocument? document,
    ShortcutConfigStatus? status,
    Object? error = _keep,
    bool? usingDefaults,
  }) => ShortcutConfigSnapshot(
    revision: revision ?? this.revision,
    sequence: sequence ?? this.sequence,
    document: document ?? this.document,
    status: status ?? this.status,
    error: identical(error, _keep) ? this.error : error as ShortcutReadError?,
    usingDefaults: usingDefaults ?? this.usingDefaults,
  );
}

const Object _keep = Object();

/// Save failures never replace effective preferences.
enum ShortcutSaveStatus {
  saved,
  stale,
  unreadable,
  writeFailed,
  notReady,
  conflict,
}

/// The outcome of an edit and the currently accepted snapshot.
class ShortcutSaveResult {
  const ShortcutSaveResult(
    this.status,
    this.snapshot, {
    this.issue,
    this.conflicts,
  });

  final ShortcutSaveStatus status;
  final ShortcutConfigSnapshot snapshot;
  final BindingIssue? issue;
  final List<String>? conflicts;
}

/// Storage adapter owns path isolation and complete replacement on successful writes.
abstract interface class ShortcutStorage {
  FutureOr<String?> read();
  FutureOr<void> write(String raw);
}

final Random _random = Random.secure();

/// A fresh opaque revision.
String newShortcutRevision() => List.generate(
  16,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

/// A disabled initial snapshot for asynchronous adapter startup.
ShortcutConfigSnapshot initialShortcutConfig() => ShortcutConfigSnapshot(
  revision: newShortcutRevision(),
  sequence: 0,
  document: const ShortcutDocument.empty(),
  status: ShortcutConfigStatus.loading,
  error: null,
  usingDefaults: true,
);

/// Single-writer coordinator shared by every storage adapter.
class ShortcutPersistence {
  ShortcutPersistence(
    this._storage,
    this._runtime,
    this._platform,
    this._rereadBeforeWrite,
    this._publish, {
    void Function(Object error)? onSubscriberError,
  }) : _onSubscriberError = onSubscriberError ?? _logSubscriberError;

  final ShortcutStorage _storage;
  final ShortcutRuntime _runtime;
  final ShortcutPlatform _platform;
  final bool _rereadBeforeWrite;
  final void Function(ShortcutConfigSnapshot snapshot) _publish;
  final void Function(Object error) _onSubscriberError;

  static void _logSubscriberError(Object error) {
    // ignore: avoid_print
    print('Shortcut configuration subscriber failed: $error');
  }

  ShortcutConfigSnapshot _snapshot = initialShortcutConfig();
  Object? _raw = _unread;
  Future<Object?> _queue = Future<Object?>.value();
  List<ShortcutDefinition>? _definitions;
  bool _active = true;

  static const Object _unread = Object();

  /// The accepted snapshot.
  ShortcutConfigSnapshot get snapshot => _snapshot;

  /// Install or revoke a product catalog and invalidate drafts from its
  /// previous lifetime. Null while the product is not ready.
  void setDefinitions(List<ShortcutDefinition>? definitions) {
    _definitions = definitions;
    _accept(_snapshot);
  }

  /// Stop accepting edits or publishing late completions.
  void dispose() => _active = false;

  /// Read the current file; failures retain the last accepted document and
  /// disable ordinary writes.
  Future<ShortcutConfigSnapshot> readCurrent() => _serialize(_read);

  /// Compare the draft revision, validate the complete candidate, then persist
  /// before publishing. [revision] is the state against which the user
  /// reviewed the edit.
  Future<ShortcutSaveResult> edit(ShortcutEdit edit, String revision) {
    return _serialize(() async {
      if (_rereadBeforeWrite) await _read();
      ShortcutSaveResult result(ShortcutSaveStatus status) =>
          ShortcutSaveResult(status, _snapshot);
      final definitions = _definitions;
      if (!_active ||
          definitions == null ||
          _snapshot.status == ShortcutConfigStatus.loading) {
        return result(ShortcutSaveStatus.notReady);
      }
      if (revision != _snapshot.revision) {
        return result(ShortcutSaveStatus.stale);
      }
      if (_snapshot.status == ShortcutConfigStatus.unreadable) {
        return result(ShortcutSaveStatus.unreadable);
      }
      final targetId = switch (edit) {
        SetShortcut() => edit.id,
        ResetShortcut() => edit.id,
        ResetAllShortcuts() => null,
      };
      if (targetId != null &&
          !definitions.any((row) => row.id == targetId && row.fixed == null)) {
        return result(ShortcutSaveStatus.notReady);
      }
      final document = editShortcutDocument(
        _snapshot.document,
        edit,
        _runtime,
        _platform,
      );
      final rows = effectiveShortcuts(
        definitions,
        document,
        _runtime,
        _platform,
      );
      EffectiveShortcut? invalid;
      for (final row in rows) {
        if ((edit is ResetAllShortcuts || row.id == targetId) &&
            (row.issue != null || row.conflicts.isNotEmpty)) {
          invalid = row;
          break;
        }
      }
      // An explicit edit must not silently disable another command's default binding.
      EffectiveShortcut? displaced;
      if (edit is SetShortcut) {
        for (final row in rows) {
          if (row.conflicts.contains(edit.id)) {
            displaced = row;
            break;
          }
        }
      }
      if (invalid != null || displaced != null) {
        return ShortcutSaveResult(
          ShortcutSaveStatus.conflict,
          _snapshot,
          issue: invalid?.issue,
          conflicts: invalid != null && invalid.conflicts.isNotEmpty
              ? invalid.conflicts
              : displaced == null
              ? const []
              : [displaced.id],
        );
      }
      try {
        final raw =
            '${const JsonEncoder.withIndent('  ').convert(document.toJson())}\n';
        await _storage.write(raw);
        _raw = raw;
        _accept(
          _snapshot.copyWith(
            document: document,
            status: ShortcutConfigStatus.ready,
            error: null,
            usingDefaults: false,
          ),
        );
        return result(ShortcutSaveStatus.saved);
      } on Object {
        // The adapter retains the previous complete document when a write fails.
        return result(ShortcutSaveStatus.writeFailed);
      }
    });
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.then<Object?>((_) => null, onError: (_) => null);
    return next;
  }

  void _accept(ShortcutConfigSnapshot snapshot) {
    _snapshot = snapshot.copyWith(
      sequence: _snapshot.sequence + 1,
      revision: newShortcutRevision(),
    );
    if (!_active) return;
    try {
      _publish(_snapshot);
    } on Object catch (error) {
      _onSubscriberError(error);
    }
  }

  Future<ShortcutConfigSnapshot> _read() async {
    String? raw;
    try {
      raw = await _storage.read();
    } on Object {
      if (_snapshot.error != ShortcutReadError.read) {
        _accept(
          _snapshot.copyWith(
            status: ShortcutConfigStatus.unreadable,
            error: ShortcutReadError.read,
          ),
        );
      }
      return _snapshot;
    }
    if (!identical(_raw, _unread) &&
        raw == _raw &&
        _snapshot.error != ShortcutReadError.read) {
      return _snapshot;
    }
    _raw = raw;
    final parsed = parseShortcutDocument(raw);
    if (parsed.error != null) {
      _accept(
        _snapshot.copyWith(
          status: ShortcutConfigStatus.unreadable,
          error: parsed.error == ShortcutDocumentError.future
              ? ShortcutReadError.future
              : ShortcutReadError.invalid,
        ),
      );
    } else {
      _accept(
        _snapshot.copyWith(
          document: parsed.document,
          status: ShortcutConfigStatus.ready,
          error: null,
          usingDefaults: raw == null,
        ),
      );
    }
    return _snapshot;
  }
}
