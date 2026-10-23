import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_client/generated.dart' as session_ns;
import 'package:dsh_models/dsh_models.dart';

import 'model_catalog.dart';

enum ModelDirectoryStatus { idle, loading, ready, selecting, error }

/// Directory snapshot the selector renders from (dsh `ModelDirectoryState`).
class ModelDirectoryState {
  const ModelDirectoryState({
    this.current,
    this.retainedEffort,
    this.routable,
    this.groups = const [],
    this.failures = const [],
    this.status = ModelDirectoryStatus.idle,
    this.pending,
    this.error,
  });

  /// Saved selection, retained even when its provider or model leaves the
  /// catalog.
  final session_ns.ModelSelection? current;

  /// Saved effort caption retained when the selected model is unavailable.
  final String? retainedEffort;

  /// Whether the current selection is in the available catalog; null while
  /// unresolved.
  final bool? routable;

  /// Successfully loaded provider groups (the last good load).
  final List<session_ns.ModelProviderGroup> groups;

  /// Provider-local failures of the last load; usable groups stay usable.
  final List<session_ns.ModelCatalogFailure> failures;
  final ModelDirectoryStatus status;

  /// Selection submitted by the latest `select` until it settles.
  final session_ns.ModelSelection? pending;

  /// Whole-request or selection failure text.
  final String? error;
}

/// How a selection ended: `error` is the Host's refusal, null on success.
class ModelSelectOutcome {
  const ModelSelectOutcome.ok() : error = null;
  const ModelSelectOutcome.refused(RemoteException this.error);
  final RemoteException? error;
  bool get ok => error == null;
}

/// One session's model directory: the state the model seat shares (dsh
/// `ModelDirectory`). It joins the shared Host catalog with the session's
/// durable `modelSelection` projection and submits through `selectModel`. The
/// projection frame, not the call's answer, updates the current selection.
class ModelDirectory {
  ModelDirectory({
    required HostRemotes remotes,
    required String sessionId,
    required ModelCatalogDirectory catalog,
    required ProjectionStore projections,
  }) : _remotes = remotes,
       _sessionId = sessionId,
       _catalog = catalog,
       _projections = projections {
    _subs.add(catalog.state.changes.listen((_) => _syncInputs()));
    _subs.add(projections.changes.listen((_) => _syncInputs()));
    _syncInputs();
  }

  final HostRemotes _remotes;
  final String _sessionId;
  final ModelCatalogDirectory _catalog;
  final ProjectionStore _projections;
  final List<StreamSubscription<Object?>> _subs = [];

  final Observable<ModelDirectoryState> state = Observable(
    const ModelDirectoryState(),
  );

  /// Latest selection operation wins; an older response never overwrites a
  /// newer one.
  int _generation = 0;
  bool _disposed = false;

  /// Ensure the Host generation's shared catalog is loaded.
  Future<ModelDirectoryState> load() async {
    await _catalog.load();
    _syncInputs();
    return state.value;
  }

  /// Select the complete provider/model/effort. The durable projection frame
  /// updates the shared current selection; a failure surfaces on [state] and
  /// in the returned outcome.
  Future<ModelSelectOutcome> select(session_ns.ModelSelection selection) async {
    final generation = ++_generation;
    state.set(
      _copy(
        status: ModelDirectoryStatus.selecting,
        pending: selection,
        error: null,
      ),
    );
    RemoteException? refusal;
    try {
      await _remotes.session.selectModel(
        session_ns.SessionSelectModelRequest(
          sessionId: _sessionId,
          provider: selection.provider,
          model: selection.model,
          reasoningEffort: selection.reasoningEffort,
        ),
      );
    } on RemoteException catch (error) {
      refusal = error;
    }
    if (_disposed || generation != _generation) {
      return refusal == null
          ? const ModelSelectOutcome.ok()
          : ModelSelectOutcome.refused(refusal);
    }
    if (refusal != null) {
      state.set(
        _copy(
          status: ModelDirectoryStatus.error,
          pending: null,
          error: '${refusal.code}: ${refusal.message}',
        ),
      );
      return ModelSelectOutcome.refused(refusal);
    }
    state.set(
      _copy(status: ModelDirectoryStatus.ready, pending: null, error: null),
    );
    _syncInputs();
    return const ModelSelectOutcome.ok();
  }

  /// Invalidate an in-flight selection response from the previous Host
  /// generation.
  void resetConnected() {
    if (_disposed) return;
    _generation += 1;
    final s = state.value;
    state.set(
      _copy(
        status: s.status == ModelDirectoryStatus.selecting
            ? ModelDirectoryStatus.idle
            : s.status,
        pending: null,
        error: null,
      ),
    );
    _syncInputs();
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    await state.dispose();
  }

  ModelDirectoryState _copy({
    required ModelDirectoryStatus status,
    required session_ns.ModelSelection? pending,
    required String? error,
  }) {
    final s = state.value;
    return ModelDirectoryState(
      current: s.current,
      retainedEffort: s.retainedEffort,
      routable: s.routable,
      groups: s.groups,
      failures: s.failures,
      status: status,
      pending: pending,
      error: error,
    );
  }

  /// The projected selection `next` (dsh reads only that and falls back to the
  /// catalog default).
  static session_ns.ModelSelection? _projectedNext(Object? value) {
    if (value is! Map) return null;
    final next = value['next'];
    if (next is! Map ||
        next['provider'] is! String ||
        next['model'] is! String) {
      return null;
    }
    final effort = next['reasoningEffort'];
    return session_ns.ModelSelection(
      provider: next['provider']! as String,
      model: next['model']! as String,
      reasoningEffort: effort is String ? effort : null,
    );
  }

  void _syncInputs() {
    if (_disposed) return;
    final catalog = _catalog.state.value;
    final projection = _projections.get('modelSelection');
    final projected = projection == null ? null : _projectedNext(projection);
    final intended = projected ?? catalog.value?.defaultSelection;
    final reasoning = intended == null
        ? null
        : _catalog.reasoningFor(intended.provider, intended.model);
    final effort = intended?.reasoningEffort ?? reasoning?.defaultEffort;
    String? retained;
    if (effort != null) {
      retained = effort;
      for (final level
          in reasoning?.efforts ?? const <session_ns.ModelReasoningEffort>[]) {
        if (level.id == effort) retained = level.name;
      }
    }
    final before = state.value;
    if (catalog.status != ModelCatalogStatus.ready ||
        catalog.value == null ||
        projection == null) {
      state.set(
        ModelDirectoryState(
          current: catalog.value == null ? null : before.current,
          retainedEffort: retained,
          groups: catalog.value?.groups ?? const [],
          failures: catalog.value?.failures ?? const [],
          status: catalog.status == ModelCatalogStatus.error
              ? ModelDirectoryStatus.error
              : ModelDirectoryStatus.loading,
          pending: before.pending,
          error: catalog.error,
        ),
      );
      return;
    }
    final selection = projected ?? catalog.value!.defaultSelection;
    final routable = catalog.value!.groups.any(
      (g) =>
          g.id == selection.provider &&
          g.models.any((m) => m.id == selection.model),
    );
    state.set(
      ModelDirectoryState(
        current: selection,
        retainedEffort: retained,
        routable: routable,
        groups: catalog.value!.groups,
        failures: catalog.value!.failures,
        status: before.status == ModelDirectoryStatus.selecting
            ? ModelDirectoryStatus.selecting
            : ModelDirectoryStatus.ready,
        pending: before.pending,
      ),
    );
  }
}
