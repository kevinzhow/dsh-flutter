import 'dart:async';

import 'package:dsh_client/generated_settings.dart' as wire;

import '../observable.dart';

/// Lifecycle of the mirror: `idle` means no answer is held and no read is
/// running, so [SettingsDescribeMirror.ensure] will start one; `ready`
/// persists across later failed refreshes (the held view keeps serving).
enum MirrorStatus { idle, loading, ready }

/// Mirror state every derived settings surface renders from.
class SettingsMirrorSnapshot {
  const SettingsMirrorSnapshot({
    this.status = MirrorStatus.idle,
    this.view,
    this.error,
  });

  final MirrorStatus status;

  /// The last good `settings.describe` answer; null until the first success.
  final wire.SettingsDescribeValue? view;

  /// The latest refresh failure message, cleared by the next success.
  final String? error;
}

/// Client mirror of the Host settings document: the one `settings.describe`
/// reader of the app (dsh `SettingsDescribeMirror`, ui-settings). Every
/// settings consumer derives from this store, so startup cost and freshness
/// are properties of this class, not of how many features own a preference.
///
/// Concurrent [load] calls fold into the in-flight read plus one rerun, so an
/// invalidation arriving mid-read is never lost and never duplicated, and a
/// write answer folded in through [acceptView] invalidates a read that started
/// before the write committed.
class SettingsDescribeMirror {
  /// [describe] performs one `settings.describe` read; a refusal throws.
  SettingsDescribeMirror(this._describe);

  final Future<wire.SettingsDescribeValue> Function() _describe;
  final Observable<SettingsMirrorSnapshot> store = Observable(
    const SettingsMirrorSnapshot(),
  );
  Future<void>? _inFlight;
  bool _rerun = false;
  int _generation = 0;

  SettingsMirrorSnapshot get snapshot => store.value;

  /// Observe snapshot replacements; returns the disposer.
  void Function() subscribe(void Function() listener) {
    final sub = store.changes.listen((_) => listener());
    return () => unawaited(sub.cancel());
  }

  /// Refresh from the Host. A call during an in-flight read marks one rerun
  /// after it settles instead of racing a second wire read.
  Future<void> load() {
    final running = _inFlight;
    if (running != null) {
      _rerun = true;
      return running;
    }
    // Own the slot before the loading publication can synchronously re-enter.
    final run = Future<void>.microtask(_run);
    _inFlight = run;
    return run;
  }

  /// Resolve once an answer is held, reading only from `idle`.
  Future<void> ensure() {
    final running = _inFlight;
    if (running != null) return running;
    if (snapshot.status == MirrorStatus.idle) return load();
    return Future.value();
  }

  /// Fold one write answer's namespace view into the held view without a wire
  /// read, and invalidate any read still in flight. With no held document the
  /// answer is not published as a partial document; an in-flight read reruns
  /// so it cannot publish a document fetched before the write committed.
  void acceptView(wire.SettingsNamespaceView view) {
    final before = snapshot;
    _generation += 1;
    if (_inFlight != null) _rerun = true;
    final held = before.view;
    if (held == null) return;
    final known = held.namespaces.any((row) => row.ns == view.ns);
    final namespaces = known
        ? [for (final row in held.namespaces) row.ns == view.ns ? view : row]
        : [...held.namespaces, view];
    store.set(
      SettingsMirrorSnapshot(
        status: before.status,
        view: wire.SettingsDescribeValue(
          writable: held.writable,
          hasDocument: held.hasDocument,
          namespaces: namespaces,
        ),
        error: before.error,
      ),
    );
  }

  /// The namespace row on the held view, or null while unanswered or unserved.
  wire.SettingsNamespaceView? namespace(String ns) {
    final view = snapshot.view;
    if (view == null) return null;
    for (final row in view.namespaces) {
      if (row.ns == ns) return row;
    }
    return null;
  }

  Future<void> _run() async {
    try {
      do {
        final before = snapshot;
        if (before.status == MirrorStatus.idle) {
          store.set(
            SettingsMirrorSnapshot(
              status: MirrorStatus.loading,
              view: before.view,
              error: before.error,
            ),
          );
        }
        // Cleared immediately before the wire read goes out: a load() marked
        // earlier is covered by this very read, one landing after needs the
        // rerun.
        _rerun = false;
        final generation = ++_generation;
        wire.SettingsDescribeValue? view;
        String? failure;
        try {
          view = await _describe();
        } on Object catch (error) {
          failure = _message(error);
        }
        // A write answer invalidates a document read before that write committed.
        if (generation != _generation) continue;
        if (view != null) {
          store.set(
            SettingsMirrorSnapshot(status: MirrorStatus.ready, view: view),
          );
        } else {
          final held = snapshot;
          // No answer yet: fall back to idle so `ensure` retries; with one, the
          // held view keeps serving and only the error field reports the miss.
          store.set(
            SettingsMirrorSnapshot(
              status: held.view == null
                  ? MirrorStatus.idle
                  : MirrorStatus.ready,
              view: held.view,
              error: failure,
            ),
          );
        }
      } while (_rerun);
    } finally {
      _inFlight = null;
    }
  }

  static String _message(Object error) {
    final text = '$error';
    return text.startsWith('RemoteException(') ? text : text;
  }
}
