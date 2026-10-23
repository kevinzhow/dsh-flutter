import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_client/generated.dart' as session_ns;
import 'package:dsh_models/dsh_models.dart';

enum ModelCatalogStatus { idle, loading, ready, error }

/// Observable lifecycle of the shared model catalog (dsh `ModelCatalogState`).
class ModelCatalogState {
  const ModelCatalogState({
    this.value,
    this.status = ModelCatalogStatus.idle,
    this.error,
  });

  final session_ns.ModelCatalog? value;
  final ModelCatalogStatus status;
  final String? error;
}

/// Loads at most one model catalog for the current Host generation and shares
/// it with every session's selector (dsh `ModelCatalogDirectory`). It reloads
/// when a Host-side model input changes: the adapters, the settings document,
/// the credentials.
class ModelCatalogDirectory {
  ModelCatalogDirectory(this._remotes) {
    _subs.add(
      _remotes.generations.where((g) => g != null).listen((_) {
        resetGeneration();
      }),
    );
    for (final event in const [
      'llm/adapters-updated',
      'settings/document-updated',
      'credentials/record-updated',
      'credentials/reference-updated',
    ]) {
      _subs.add(_remotes.emitted(event).listen((_) => refresh()));
    }
  }

  final HostRemotes _remotes;
  final List<StreamSubscription<Object?>> _subs = [];

  /// The current shared catalog value and load lifecycle.
  final Observable<ModelCatalogState> state = Observable(
    const ModelCatalogState(),
  );

  final Map<String, session_ns.ModelReasoning?> _reasoning = {};
  int _generation = 0;
  Future<session_ns.ModelCatalog>? _inflight;

  static String _key(String provider, String model) => '$provider\u0000$model';

  /// The last advertised reasoning metadata of [provider]/[model], including
  /// models that have left the catalog since.
  session_ns.ModelReasoning? reasoningFor(String provider, String model) =>
      _reasoning[_key(provider, model)];

  /// The current generation's catalog, sharing its one in-flight load.
  Future<session_ns.ModelCatalog> load() {
    final current = state.value;
    if (current.status == ModelCatalogStatus.ready && current.value != null) {
      return Future.value(current.value);
    }
    final running = _inflight;
    if (running != null) return running;
    final generation = _generation;
    state.set(
      ModelCatalogState(
        value: current.value,
        status: ModelCatalogStatus.loading,
      ),
    );
    late final Future<session_ns.ModelCatalog> operation;
    operation = _remotes.session
        .modelCatalog()
        .then((catalog) {
          if (generation == _generation) {
            for (final group in catalog.groups) {
              for (final model in group.models) {
                _reasoning[_key(group.id, model.id)] = model.reasoning;
              }
            }
            state.set(
              ModelCatalogState(
                value: catalog,
                status: ModelCatalogStatus.ready,
              ),
            );
          }
          return catalog;
        })
        .catchError((Object error) {
          if (generation == _generation) {
            state.set(
              ModelCatalogState(
                value: state.value.value,
                status: ModelCatalogStatus.error,
                error: _message(error),
              ),
            );
          }
          throw error;
        })
        .whenComplete(() {
          if (generation == _generation && identical(_inflight, operation)) {
            _inflight = null;
          }
        });
    _inflight = operation;
    return operation;
  }

  /// Invalidate the loaded catalog; the next explicit read reloads it. With
  /// [clear], the values of the previous Host generation are hidden.
  void _invalidate({bool clear = false}) {
    _generation += 1;
    _inflight = null;
    state.set(ModelCatalogState(value: clear ? null : state.value.value));
  }

  /// Invalidate and reload after a Host-side model input changes.
  void refresh() {
    _invalidate();
    unawaited(load().then<void>((_) {}, onError: (Object _) {}));
  }

  /// Clear Host-specific values and load the replacement Host generation.
  void resetGeneration() {
    _reasoning.clear();
    _invalidate(clear: true);
    unawaited(load().then<void>((_) {}, onError: (Object _) {}));
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await state.dispose();
  }

  static String _message(Object error) =>
      error is RemoteException ? '${error.code}: ${error.message}' : '$error';
}
