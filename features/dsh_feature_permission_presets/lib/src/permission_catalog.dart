import 'dart:async';

import 'package:dsh_client/generated_permission_presets.dart' as wire;
import 'package:dsh_models/dsh_models.dart';

/// Identity-stable process permission catalog shared by both selection
/// surfaces (dsh `PermissionCatalogDirectory`): one latest-result-wins reader
/// for the whole app, fenced by the connection generation.
class PermissionCatalogDirectory {
  PermissionCatalogDirectory(this._remotes) {
    // Subscribe before the first read, closing the install/read race.
    _subs.add(
      _remotes.emitted('permission-presets/catalog-changed').listen((_) {
        _invalidate();
        refresh();
      }),
    );
    _subs.add(_remotes.generations.listen((_) => _syncGeneration()));
    _syncGeneration();
  }

  final HostRemotes _remotes;
  final List<StreamSubscription<Object?>> _subs = [];

  /// The last complete catalog of this generation, or null before one
  /// succeeds. Both the Settings row and the composer chip read it.
  final Observable<wire.PermissionCatalog?> value = Observable(null);

  /// One tick per invalidation (a catalog notification or a connection
  /// generation change), published before the replacement read starts.
  /// Consumers holding displayed options drop them on this, not on [value],
  /// whose publications also settle a read a displayed surface waits for.
  final Observable<int> invalidations = Observable(0);

  Object? _generation;
  bool _initialized = false;
  int _epoch = 0;
  Future<void>? _pending;
  Object _failure = StateError('permission catalog has no complete value');
  bool _disposed = false;

  void _invalidate() => invalidations.set(invalidations.value + 1);

  /// Force a fresh complete read for the active connection generation.
  void refresh() {
    if (_disposed) return;
    final generation = _remotes.currentGeneration();
    if (generation == null) return;
    if (!identical(generation, _generation)) {
      _syncGeneration();
      return;
    }
    _startRead(generation);
  }

  /// Resolve a complete current-generation catalog for an imperative open. An
  /// active refresh settles before a retained value can be reused.
  Future<wire.PermissionCatalog> load() async {
    if (_pending == null && value.value == null) refresh();
    while (!_disposed) {
      final generation = _remotes.currentGeneration();
      if (generation == null) {
        throw StateError('permission catalog has no active Host connection');
      }
      if (!identical(generation, _generation)) _syncGeneration();
      final pending = _pending;
      if (pending != null) {
        await pending;
        continue;
      }
      final catalog = value.value;
      if (catalog != null) return catalog;
      throw _failure;
    }
    throw StateError('permission catalog directory is disposed');
  }

  /// Observe generation loss/replacement and hard-clear the old Host value.
  void _syncGeneration() {
    if (_disposed) return;
    final generation = _remotes.currentGeneration();
    if (_initialized && identical(generation, _generation)) return;
    // Only an actual change withdraws displayed options: the first sync, and a
    // notification repeating the generation already published, leave them alone.
    if (_initialized) _invalidate();
    _initialized = true;
    _generation = generation;
    _epoch += 1;
    _pending = null;
    _failure = StateError('permission catalog has no complete value');
    value.set(null);
    if (generation != null) _startRead(generation);
  }

  void _startRead(Object generation) {
    final epoch = ++_epoch;
    _failure = StateError('permission catalog has no complete value');
    late final Future<void> operation;
    operation = _remotes.permissionPresets
        .catalog()
        .then<void>((catalog) {
          if (!_accepts(epoch, generation)) return;
          value.set(catalog);
        })
        .catchError((Object error) {
          if (!_accepts(epoch, generation)) return;
          _failure = error;
          value.set(null);
        })
        .whenComplete(() {
          if (identical(_pending, operation)) _pending = null;
        });
    _pending = operation;
  }

  /// Fence by disposal, refresh epoch and the actual connection generation.
  bool _accepts(int epoch, Object generation) =>
      !_disposed &&
      epoch == _epoch &&
      identical(generation, _generation) &&
      identical(_remotes.currentGeneration(), generation);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _epoch += 1;
    _pending = null;
    for (final s in _subs) {
      await s.cancel();
    }
    await value.dispose();
    await invalidations.dispose();
  }
}
