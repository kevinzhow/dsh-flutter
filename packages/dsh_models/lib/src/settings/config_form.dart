import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_client/generated_settings.dart' as wire;

import '../observable.dart';
import 'host_remotes.dart';
import 'schema.dart';
import 'settings_mirror.dart';

/// Sync state of one settings namespace as one client form sees it.
enum ConfigFormStatus { loading, ready, unavailable }

/// Client-side sync state of one settings namespace (dsh `ConfigFormSnapshot`).
class ConfigFormSnapshot {
  const ConfigFormSnapshot({
    this.status = ConfigFormStatus.loading,
    this.value,
    this.base,
    this.user,
    this.revision,
    this.writable = false,
  });

  /// `loading` until the first accepted section, `ready` while one stands, and
  /// `unavailable` when the namespace is not exposed to this client.
  final ConfigFormStatus status;

  /// Last accepted schema-resolved section; null before the first acceptance.
  final Map<String, Object?>? value;

  /// Composition layer the Host resolved [value] over: what a field reverts to
  /// once cleared.
  final Object? base;

  /// Raw user layer as stored. A field's PRESENCE here marks it overridden: an
  /// override equal to the composition default is still an override.
  final Object? user;

  /// Namespace revision fencing the next write; null before the first view.
  final int? revision;

  /// Whether the Host document accepts writes.
  final bool writable;
}

/// One path edit of an atomic namespace write.
sealed class SettingsOp {
  const SettingsOp(this.path);
  final List<String> path;
}

/// Write [value] at [path], creating intermediate objects.
class SetOp extends SettingsOp {
  const SetOp(super.path, this.value);
  final Object? value;
}

/// Remove the value at [path], so the field re-inherits the composition layer.
class UnsetOp extends SettingsOp {
  const UnsetOp(super.path);
}

/// Accepted values and serialized writes shared by editors of one Host entry
/// (dsh `ConfigForm`).
abstract interface class ConfigForm {
  ConfigFormSnapshot get snapshot;

  /// Observe snapshot replacements; returns the disposer.
  void Function() subscribe(void Function() listener);

  /// Queue one atomic namespace mutation. All operations share one revision
  /// fence, Host validation and recovery read. Supplying [expectedRevision]
  /// preserves an earlier read as the fence instead of the latest queued or
  /// mirrored revision. Resolves true for Host acceptance, false for refusal
  /// or skipped writes, after any latest-write recovery. Transport failures
  /// complete with an error.
  Future<bool> mutate(List<SettingsOp> ops, {int? expectedRevision});

  /// Queue one field write; ordering, revision fence and recovery as [mutate].
  Future<bool> set(String field, Object? value);

  /// Queue one field clear; ordering, revision fence and recovery as [mutate].
  Future<bool> unset(String field);
}

/// One namespace's derived view over the shared describe mirror, plus that
/// namespace's serialized Host writes (dsh `ConfigFormController`). Writes
/// carry the latest known namespace revision, fold their answers back into the
/// mirror, and teardown waits for the operation already crossing the wire.
class ConfigFormController implements ConfigForm {
  ConfigFormController({
    required this.namespace,
    required SettingsDescribeMirror mirror,
    required Future<wire.SettingsNamespaceView> Function(
      String ns,
      List<wire.SettingsPathOpView> ops,
      num? expectedRevision,
    )
    mutate,
    Map<String, Object?>? Function(wire.SettingsNamespaceView view)? decode,
  }) : _mirror = mirror,
       _mutate = mutate,
       _decode = decode {
    _unsubscribe = mirror.subscribe(_derive);
    _derive();
  }

  /// The settings namespace this form edits.
  final String namespace;
  final SettingsDescribeMirror _mirror;
  final Future<wire.SettingsNamespaceView> Function(
    String,
    List<wire.SettingsPathOpView>,
    num?,
  )
  _mutate;
  final Map<String, Object?>? Function(wire.SettingsNamespaceView)? _decode;
  final Observable<ConfigFormSnapshot> _store = Observable(
    const ConfigFormSnapshot(),
  );
  Future<void> _tail = Future.value();
  int _writeGeneration = 0;
  bool _disposed = false;
  late final void Function() _unsubscribe;

  /// Revision answered by a superseded write still ahead of the mirror: the
  /// mirror only folds the LATEST settlement in, so a queued successor takes
  /// its fence from here first.
  int? _pendingRevision;

  Object? _decodedSchemaSource;
  SettingsSchema? _decodedSchema;

  @override
  ConfigFormSnapshot get snapshot => _store.value;

  @override
  void Function() subscribe(void Function() listener) {
    final sub = _store.changes.listen((_) => listener());
    return () => unawaited(sub.cancel());
  }

  @override
  Future<bool> set(String field, Object? value) => mutate([
    SetOp([field], value),
  ]);

  @override
  Future<bool> unset(String field) => mutate([
    UnsetOp([field]),
  ]);

  @override
  Future<bool> mutate(List<SettingsOp> ops, {int? expectedRevision}) {
    final owned = [
      for (final op in ops)
        switch (op) {
          SetOp() => wire.SettingsPathOpViewSet(
            path: List<String>.of(op.path),
            value: _deepCopy(op.value),
          ),
          UnsetOp() => wire.SettingsPathOpViewUnset(
            path: List<String>.of(op.path),
          ),
        },
    ];
    final generation = ++_writeGeneration;
    return _enqueue(() async {
      final revision =
          expectedRevision ?? _pendingRevision ?? snapshot.revision;
      final wire.SettingsNamespaceView answer;
      try {
        answer = await _mutate(namespace, owned, revision);
      } on RemoteException catch (error) {
        if (!isHostRefusal(error)) rethrow;
        await _recover(generation);
        return false;
      }
      if (_disposed) return true;
      if (generation == _writeGeneration) {
        _pendingRevision = null;
        _mirror.acceptView(answer);
      } else {
        _pendingRevision = answer.revision;
      }
      return true;
    });
  }

  /// Reload Host state for the latest failed write; superseded failures leave
  /// recovery to it.
  Future<void> _recover(int generation) async {
    if (_disposed || generation != _writeGeneration) return;
    _pendingRevision = null;
    await _mirror.load();
  }

  /// Stop queued operations, stop deriving, and wait for the current wire call
  /// to settle.
  Future<void> dispose() async {
    _disposed = true;
    _writeGeneration += 1;
    _unsubscribe();
    await _tail;
  }

  Future<bool> _enqueue(Future<bool> Function() operation) {
    if (_disposed) return Future.value(false);
    final task = _tail.then((_) async {
      if (_disposed) return false;
      return operation();
    });
    // The returned task carries its own settlement to the caller; the queue
    // tail is kept fulfilled so one failed writer cannot strand later ones.
    _tail = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  void _derive() {
    if (_disposed) return;
    final mirrored = _mirror.snapshot;
    final view = mirrored.view;
    if (view == null) return;
    final before = snapshot;
    final row = _mirror.namespace(namespace);
    if (row == null) {
      _publish(
        ConfigFormSnapshot(
          status: ConfigFormStatus.unavailable,
          value: before.value,
          base: before.base,
          user: before.user,
          revision: before.revision,
          writable: view.writable,
        ),
      );
      return;
    }
    final decoded = _decodeView(row);
    _publish(
      ConfigFormSnapshot(
        status: decoded == null ? before.status : ConfigFormStatus.ready,
        value: decoded ?? before.value,
        base: row.base,
        user: row.user,
        revision: row.revision,
        writable: view.writable,
      ),
    );
  }

  void _publish(ConfigFormSnapshot next) {
    final before = snapshot;
    if (before.status == next.status &&
        before.writable == next.writable &&
        before.revision == next.revision &&
        _jsonEqual(before.value, next.value) &&
        _jsonEqual(before.base, next.base) &&
        _jsonEqual(before.user, next.user)) {
      return;
    }
    _store.set(next);
  }

  Map<String, Object?>? _decodeView(wire.SettingsNamespaceView row) {
    final custom = _decode;
    if (custom != null) return custom(row);
    // Sections are plain objects by construction; the schema alone would
    // resolve null or an array through object defaults instead of refusing.
    final value = row.value;
    if (value is! Map) return null;
    if (!identical(_decodedSchemaSource, row.schema)) {
      _decodedSchemaSource = row.schema;
      _decodedSchema = SettingsSchema.rehydrate(row.schema);
    }
    final failure = _decodedSchema!.validate(value);
    return failure == null ? value.cast<String, Object?>() : null;
  }
}

/// The settings domain's base service (dsh `ConfigForms`): the shared describe
/// mirror, kept fresh by the forwarded `settings/document-updated` event and
/// by every new connection generation, and one [ConfigForm] per Host entry.
class ConfigForms {
  ConfigForms(HostRemotes remotes)
    : mirror = SettingsDescribeMirror(() => remotes.settings.describe()),
      _mutate = remotes.settings.mutate {
    _subscriptions.add(
      remotes.emitted('settings/document-updated').listen((_) {
        unawaited(mirror.load());
      }),
    );
    _subscriptions.add(
      remotes.generations.where((g) => g != null).listen((_) {
        unawaited(mirror.load());
      }),
    );
    // The first connection also emits a generation, so startup normally costs
    // two reads; the in-flight fold keeps at most one pending at a time.
    unawaited(mirror.ensure());
  }

  /// The shared mirror every form derives from.
  final SettingsDescribeMirror mirror;
  final Future<wire.SettingsNamespaceView> Function(
    String,
    List<wire.SettingsPathOpView>, [
    num?,
  ])
  _mutate;
  final Map<String, ConfigFormController> _forms = {};
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// Get the shared form values and write queue for one Host plugin entry.
  /// [decode] narrows a wire section beyond the namespace's own schema.
  ConfigFormController get(
    String entryId, {
    Map<String, Object?>? Function(wire.SettingsNamespaceView view)? decode,
  }) {
    final existing = _forms[entryId];
    if (existing != null) return existing;
    final form = ConfigFormController(
      namespace: entryId,
      mirror: mirror,
      mutate: (ns, ops, revision) => _mutate(ns, ops, revision),
      decode: decode,
    );
    _forms[entryId] = form;
    unawaited(mirror.ensure());
    return form;
  }

  /// Keep a registration alive while the Host serves any of [namespaces]:
  /// [register] runs once one of them is in the describe mirror and returns
  /// its disposer, which runs when none is served any more or when the
  /// returned disposer runs. A page that edits a namespace another plugin owns
  /// registers through this, so a deployment that never composed the owner
  /// shows no trace of the page.
  void Function() whileServed(
    List<String> namespaces,
    void Function() Function(Set<String> served) register,
  ) {
    void Function()? off;
    void sync() {
      final served = {
        for (final row
            in mirror.snapshot.view?.namespaces ??
                const <wire.SettingsNamespaceView>[])
          row.ns,
      };
      final watched = namespaces.any(served.contains);
      if (watched && off == null) {
        off = register(served);
      } else if (!watched && off != null) {
        off!();
        off = null;
      }
    }

    final unsubscribe = mirror.subscribe(sync);
    unawaited(mirror.ensure());
    sync();
    return () {
      unsubscribe();
      off?.call();
      off = null;
    };
  }

  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await Future.wait([for (final f in _forms.values) f.dispose()]);
    _forms.clear();
  }
}

Object? _deepCopy(Object? v) {
  if (v is List) return [for (final e in v) _deepCopy(e)];
  if (v is Map) {
    return {for (final e in v.entries) '${e.key}': _deepCopy(e.value)};
  }
  return v;
}

bool _jsonEqual(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_jsonEqual(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
