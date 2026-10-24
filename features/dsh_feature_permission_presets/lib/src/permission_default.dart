import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_client/generated_permission_presets.dart' as perm;
import 'package:dsh_client/generated_settings.dart' as wire;
import 'package:dsh_models/dsh_models.dart';

import 'permission_catalog.dart';

/// Permission's settings namespace on the host wire.
const String permissionSettingsNs = 'permission';

/// One selectable new-session default.
class PermissionDefaultOption {
  const PermissionDefaultOption(this.id, this.label);

  /// Preset key written to Settings.
  final String id;

  /// The host's name for the preset (display text is derived from it).
  final String label;
}

enum PermissionRowStatus { idle, loading, ready, saving, unavailable, error }

/// Permission settings-row snapshot (dsh `PermissionSettingsState`).
class PermissionSettingsState {
  const PermissionSettingsState({
    this.status = PermissionRowStatus.idle,
    this.error,
    this.writable = false,
    this.currentValue = '',
    this.options = const [],
    this.revision = 0,
  });

  final PermissionRowStatus status;
  final String? error;
  final bool writable;
  final String currentValue;
  final List<PermissionDefaultOption> options;
  final int revision;

  PermissionSettingsState copyWith({
    PermissionRowStatus? status,
    Object? error = _keep,
    bool? writable,
    String? currentValue,
    List<PermissionDefaultOption>? options,
    int? revision,
  }) => PermissionSettingsState(
    status: status ?? this.status,
    error: identical(error, _keep) ? this.error : error as String?,
    writable: writable ?? this.writable,
    currentValue: currentValue ?? this.currentValue,
    options: options ?? this.options,
    revision: revision ?? this.revision,
  );
}

const Object _keep = Object();

/// Resolve the new-session choices from the permission domain's catalog (dsh
/// `permissionDefaultOf`): the current choice and the allowed options. Throws
/// when the catalog does not advertise the current default.
({String currentValue, List<PermissionDefaultOption> options})
permissionDefaultOf(
  wire.SettingsNamespaceView view,
  perm.PermissionCatalog catalog,
) {
  final value = view.value;
  final stored = value is Map ? value['defaultPreset'] : null;
  final currentValue = stored is String ? stored : catalog.defaultPreset;
  final options = [
    for (final o in catalog.defaultOptions)
      PermissionDefaultOption(o.value, o.name),
  ];
  if (!options.any((o) => o.id == currentValue)) {
    throw StateError(
      'permission catalog does not advertise its current default',
    );
  }
  return (currentValue: currentValue, options: options);
}

/// What the Settings row needs of the default: its state and its two verbs.
/// [PermissionDefaultController] is the implementation; the parity tool and
/// tests supply fixed ones.
abstract interface class PermissionDefaults {
  /// Row snapshot.
  Observable<PermissionSettingsState> get state;

  /// Begin following the host and reflect its answer.
  Future<void> load();

  /// Persist one preset as the default of new sessions.
  Future<void> select(String preset);
}

/// Controller deriving the General row from the shared mirror and the
/// permission catalog and writing the default through the mirror (dsh
/// `PermissionPresetSettingsController`). Writes target only `defaultPreset`,
/// carry the descriptor revision, and fold their answer back into the mirror.
class PermissionDefaultController implements PermissionDefaults {
  PermissionDefaultController({
    required SettingsDescribeMirror mirror,
    required HostRemotes remotes,
    required PermissionCatalogDirectory catalog,
  }) : _mirror = mirror,
       _remotes = remotes,
       _catalog = catalog;

  final SettingsDescribeMirror _mirror;
  final HostRemotes _remotes;
  final PermissionCatalogDirectory _catalog;

  @override
  final Observable<PermissionSettingsState> state = Observable(
    const PermissionSettingsState(),
  );

  void Function()? _following;
  StreamSubscription<Object?>? _followingCatalog;
  bool _saving = false;
  bool _disposed = false;

  /// Begin following the mirror and the catalog (idempotent) and reflect
  /// their current answers.
  @override
  Future<void> load() async {
    if (_disposed) return;
    _following ??= _mirror.subscribe(_derive);
    _followingCatalog ??= _catalog.value.changes.listen((_) => _derive());
    state.set(
      state.value.copyWith(status: PermissionRowStatus.loading, error: null),
    );
    await _mirror.ensure();
    try {
      await _catalog.load();
    } on Object catch (error) {
      _fail(error);
      return;
    }
    _derive();
  }

  /// Persist one preset as the default for subsequently created sessions. A
  /// selection while one is saving is ignored (the control is disabled
  /// meanwhile, so this only drops programmatic double-submits).
  @override
  Future<void> select(String preset) async {
    final view = _mirror.namespace(permissionSettingsNs);
    if (view == null || !state.value.writable || _saving) return;
    _saving = true;
    state.set(
      state.value.copyWith(status: PermissionRowStatus.saving, error: null),
    );
    wire.SettingsNamespaceView? answer;
    Object? failure;
    try {
      answer = await _remotes.settings.mutate(permissionSettingsNs, [
        wire.SettingsPathOpViewSet(
          path: const ['defaultPreset'],
          value: preset,
        ),
      ], view.revision);
    } on Object catch (error) {
      failure = error;
    } finally {
      // Cleared before the fold below, whose publish reaches `_derive` through
      // this row's own subscription and is skipped while a save is pending.
      _saving = false;
    }
    if (_disposed) return;
    if (answer == null) {
      _fail(failure ?? StateError('write failed'));
      return;
    }
    // The mirror publish reaches this row's own subscription, so the fold is
    // also what republishes the accepted value here.
    _mirror.acceptView(answer);
  }

  void _derive() {
    if (_disposed || _saving) return;
    final snapshot = _mirror.snapshot;
    final held = snapshot.view;
    if (held == null) {
      // A held failure with no answer is a failed row; without one the read is
      // still in flight and the row keeps its loading state.
      if (snapshot.error != null) _fail(StateError(snapshot.error!));
      return;
    }
    final view = _mirror.namespace(permissionSettingsNs);
    if (view == null) {
      state.set(
        state.value.copyWith(
          status: PermissionRowStatus.unavailable,
          writable: false,
          currentValue: '',
          options: const [],
        ),
      );
      return;
    }
    try {
      final catalog = _catalog.value.value;
      if (catalog == null) return;
      final resolved = permissionDefaultOf(view, catalog);
      state.set(
        PermissionSettingsState(
          status: PermissionRowStatus.ready,
          writable: held.writable,
          currentValue: resolved.currentValue,
          options: resolved.options,
          revision: view.revision,
        ),
      );
    } on Object catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    final text = error is RemoteException ? error.message : '$error';
    state.set(
      state.value.copyWith(status: PermissionRowStatus.error, error: text),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    _following?.call();
    _following = null;
    await _followingCatalog?.cancel();
    _followingCatalog = null;
    await state.dispose();
  }
}
