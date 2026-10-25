import 'dart:async';

import 'package:dsh_client/dsh_client.dart';

import 'observable.dart';

enum HostReadPhase { loading, ready, missing, error }

class HostRead<T> {
  const HostRead(this.phase, [this.value]);
  final HostReadPhase phase;
  final T? value;
}

/// Shared fetch-once records. Summary failures stay missing until a host
/// replacement; diff failures are retryable, while 404 is durable missing.
class DeliverablesReads<T> {
  DeliverablesReads({required this.read, required this.retryErrors});
  final Future<T> Function(
    String sessionId,
    num seq,
    int? index,
    DeliverablesCancel cancel,
  )
  read;
  final bool retryErrors;
  final state = Observable<Map<String, HostRead<T>>>({});
  final _pending = <String, Future<void>>{};
  final _cancels = <DeliverablesCancel>{};
  int _generation = 0;
  bool _disposed = false;
  String key(String sessionId, num seq, [int? index]) => Uri(
    queryParameters: {
      'sessionId': sessionId,
      'seq': '$seq',
      if (index != null) 'index': '$index',
    },
  ).query;
  HostRead<T>? get(String sessionId, num seq, [int? index]) =>
      state.value[key(sessionId, seq, index)];
  Future<void> load(String sessionId, num seq, [int? index]) {
    final id = key(sessionId, seq, index),
        current = state.value[key(sessionId, seq, index)];
    if (_disposed) return Future.value();
    if (_pending[id] case final pending?) return pending;
    if (current != null &&
        !(retryErrors && current.phase == HostReadPhase.error)) {
      return Future.value();
    }
    final generation = _generation, cancel = DeliverablesCancel();
    _cancels.add(cancel);
    state.set({...state.value, id: HostRead<T>(HostReadPhase.loading)});
    final task = () async {
      HostRead<T> next;
      try {
        next = HostRead(
          HostReadPhase.ready,
          await read(sessionId, seq, index, cancel),
        );
      } on Object catch (e) {
        next = HostRead(
          retryErrors && !(e is DeliverablesHttpFailure && e.status == 404)
              ? HostReadPhase.error
              : HostReadPhase.missing,
        );
      }
      if (!_disposed && generation == _generation) {
        state.set({...state.value, id: next});
      }
    }();
    _pending[id] = task;
    unawaited(
      task.whenComplete(() {
        _cancels.remove(cancel);
        if (identical(_pending[id], task)) _pending.remove(id);
      }),
    );
    return task;
  }

  void reset() {
    _generation++;
    for (final cancel in _cancels) {
      cancel.cancel();
    }
    _cancels.clear();
    _pending.clear();
    if (!_disposed) state.set({});
  }

  Future<void> dispose() async {
    _disposed = true;
    final tasks = _pending.values.toList();
    reset();
    await Future.wait(tasks);
    await state.dispose();
  }
}

enum NativeOpenPhase {
  opening,
  opened,
  revealing,
  revealed,
  error,
  revealError,
  nativeUnavailable,
}

enum NativeOpenFailure { openError, revealError }

/// One host scope owns all reads and gesture phases, shared by cards, Review
/// and inline mentions. Rendering never invokes a native-open action.
class DeliverablesModel {
  DeliverablesModel(
    this.client, {
    this.successDuration = const Duration(milliseconds: 5200),
  }) {
    summaries = DeliverablesReads(
      read: (id, seq, _, cancel) => client.summary(id, seq, cancel: cancel),
      retryErrors: false,
    );
    diffs = DeliverablesReads(
      read: (id, seq, index, cancel) =>
          client.diff(id, seq, index!, cancel: cancel),
      retryErrors: true,
    );
  }
  final DeliverablesClient client;
  final Duration successDuration;
  late final DeliverablesReads<ChangesSummary> summaries;
  late final DeliverablesReads<ChangesDiff> diffs;
  final phases = Observable<Map<String, NativeOpenPhase>>({});
  final host = Observable<HostRead<PresentedHost>?>(null);
  final _expiry = <String, Timer>{};
  final _applications = <String, FileApplicationsHandle>{};
  FileApplicationsHandle acquireApplications(DeliveryFile file) {
    final handle = _applications.putIfAbsent(
      file.actionKey,
      () => FileApplicationsHandle(file, client),
    );
    handle.users++;
    if (handle.users == 1) handle.refresh();
    return handle;
  }

  void releaseApplications(FileApplicationsHandle handle) {
    if (--handle.users > 0) return;
    _applications.remove(handle.file.actionKey);
    unawaited(handle.dispose());
  }

  final _requests = <DeliverablesCancel, Future<Object?>>{};
  DeliverablesCancel? _metadata;
  Future<void>? _loadingHost;
  bool _disposed = false;
  int _metadataGeneration = 0;

  Future<void> loadHost() {
    if (_disposed) return Future.value();
    if (_loadingHost case final pending?) return pending;
    final cancel = DeliverablesCancel(), generation = _metadataGeneration;
    _metadata = cancel;
    host.set(const HostRead(HostReadPhase.loading));
    final task = () async {
      HostRead<PresentedHost> next;
      try {
        next = HostRead(HostReadPhase.ready, await client.host(cancel: cancel));
      } on Object {
        next = const HostRead(HostReadPhase.error);
      }
      if (!_disposed && generation == _metadataGeneration) host.set(next);
    }();
    _loadingHost = task;
    _requests[cancel] = task;
    unawaited(
      task.whenComplete(() {
        final _ = _requests.remove(cancel);
        if (identical(_loadingHost, task)) _loadingHost = null;
      }),
    );
    return task;
  }

  Future<NativeOpenFailure?> open(
    DeliveryFile file, {
    NativeFileAction action = NativeFileAction.open,
    String? application,
  }) async {
    final key = file.actionKey, current = phases.value[file.actionKey];
    if (_disposed ||
        current == NativeOpenPhase.opening ||
        current == NativeOpenPhase.revealing) {
      return null;
    }
    _expiry.remove(key)?.cancel();
    final revealing = action == NativeFileAction.reveal;
    phases.set({
      ...phases.value,
      key: revealing ? NativeOpenPhase.revealing : NativeOpenPhase.opening,
    });
    if (_disposed) return null;
    final cancel = DeliverablesCancel();
    final task = () async {
      var phase = revealing ? NativeOpenPhase.revealed : NativeOpenPhase.opened;
      try {
        await client.open(
          file,
          action: action,
          application: application,
          cancel: cancel,
        );
      } on Object catch (e) {
        phase = e is DeliverablesHttpFailure && e.status == 422
            ? NativeOpenPhase.nativeUnavailable
            : revealing
            ? NativeOpenPhase.revealError
            : NativeOpenPhase.error;
      }
      final success =
          phase == NativeOpenPhase.opened || phase == NativeOpenPhase.revealed;
      if (!_disposed) {
        phases.set({...phases.value, key: phase});
        if (success) {
          _expiry[key] = Timer(successDuration, () {
            _expiry.remove(key);
            if (!_disposed) phases.set({...phases.value}..remove(key));
          });
        }
      }
      return success
          ? null
          : revealing
          ? NativeOpenFailure.revealError
          : NativeOpenFailure.openError;
    }();
    _requests[cancel] = task;
    try {
      return await task;
    } finally {
      final _ = _requests.remove(cancel);
    }
  }

  /// A connection replacement invalidates read caches/metadata. Already
  /// acknowledged native gestures keep their feedback, matching the web UI.
  void reset() {
    for (final handle in _applications.values) {
      handle.refresh();
    }
    summaries.reset();
    diffs.reset();
    final loading = _loadingHost != null;
    _metadataGeneration++;
    _metadata?.cancel();
    _loadingHost = null;
    if (!_disposed) {
      host.set(null);
      if (loading) unawaited(loadHost());
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    final applications = _applications.values.toList();
    _applications.clear();
    _metadataGeneration++;
    _metadata?.cancel();
    for (final timer in _expiry.values) {
      timer.cancel();
    }
    _expiry.clear();
    final requests = _requests.values.toList();
    for (final cancel in _requests.keys.toList()) {
      cancel.cancel();
    }
    await Future.wait<Object?>([
      ...requests,
      ...applications.map((h) => h.dispose()),
      summaries.dispose(),
      diffs.dispose(),
    ]);
    await phases.dispose();
    await host.dispose();
  }
}

/// Mounted controls of the same event target retain one shared association
/// query; the last release cancels and forgets it. Explicit refresh retries.
class FileApplicationsHandle {
  FileApplicationsHandle(this.file, this.client);
  final DeliveryFile file;
  final DeliverablesClient client;
  int users = 0;
  final state = Observable<HostRead<List<NativeFileApplication>>>(
    const HostRead(HostReadPhase.loading),
  );
  DeliverablesCancel? _cancel;
  int _revision = 0;
  Future<void>? _pending;
  bool _disposed = false;
  void refresh() {
    if (_disposed) return;
    _cancel?.cancel();
    final cancel = _cancel = DeliverablesCancel(), rev = ++_revision;
    state.set(const HostRead(HostReadPhase.loading));
    _pending = () async {
      HostRead<List<NativeFileApplication>> next;
      try {
        next = HostRead(
          HostReadPhase.ready,
          await client.applications(file, cancel: cancel),
        );
      } on Object {
        next = const HostRead(HostReadPhase.error);
      }
      if (!_disposed && rev == _revision) state.set(next);
    }();
  }

  Future<void> dispose() async {
    _disposed = true;
    _revision++;
    _cancel?.cancel();
    await _pending;
    await state.dispose();
  }
}
