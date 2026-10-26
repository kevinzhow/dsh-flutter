import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_plugin_inventory.dart' as inventory;
import 'package:dsh_client/generated_plugin_manager.dart';

import '../observable.dart';
import '../settings/host_remotes.dart';
import 'installer.dart';

String pluginShortName(String name) {
  final unscoped = name.startsWith('@')
      ? name.substring(name.indexOf('/') + 1)
      : name;
  return unscoped.replaceFirst(RegExp(r'^dsh-(?:host-|client-)?'), '');
}

class ManagedPluginRow {
  const ManagedPluginRow(this.declaration, this.live);
  final BundleRowInfo declaration;
  final PluginInfo? live;
  bool get enabled => live?.enabled ?? false;
  PluginFiberPhase? get phase => live?.fiberPhase;
  String? get readOnlyReason => live?.readOnlyReason as String?;
}

class ManagedPluginPackage {
  ManagedPluginPackage(this.bundle, List<PluginInfo> entries)
    : rows = List.unmodifiable([
        for (final row in bundle.rows)
          ManagedPluginRow(
            row,
            row.entryId == null
                ? null
                : entries.where((e) => e.entryId == row.entryId).firstOrNull,
          ),
      ]);
  final BundleInfo bundle;
  final List<ManagedPluginRow> rows;
}

enum PluginManagerStatus { idle, loading, ready, unavailable, error }

class PluginManagerNotice {
  const PluginManagerNotice({
    required this.kind,
    this.target,
    this.action,
    this.error,
    this.reason,
    this.restartReason,
  });
  final String kind;
  final String? target, action, reason;
  final ManagementError? error;
  final RestartReason? restartReason;
}

class PluginConfirmation {
  PluginConfirmation._(
    this.kind,
    this.target,
    this._action, {
    this.pendingBuilds = const [],
    this.incompatible = const [],
  });
  final String kind, target;
  final List<String> pendingBuilds;
  final List<IncompatiblePlugin> incompatible;
  final Future<void> Function() _action;
}

/// Current-profile manager. Cached cards survive refresh failures; independent
/// Host identity, availability, installation, selection and editability facts
/// are never inferred from one another.
class PluginManagerModel {
  PluginManagerModel({
    required this.remotes,
    PluginRegistryChoice? Function()? readRegistry,
    void Function(PluginRegistryChoice)? rememberRegistry,
    String Function()? newId,
  }) {
    installer = PluginInstaller(
      remotes: remotes,
      reload: load,
      listedAvailability: (name) => packages
          .where((p) => p.bundle.name == name)
          .firstOrNull
          ?.bundle
          .availability
          .value,
      notify: (outcome) => _notice(
        PluginManagerNotice(
          kind: outcome.startsWith('install:') || outcome == 'cancelled'
              ? outcome
              : 'failed',
          reason: outcome,
        ),
      ),
      reportChange: (answer) {
        _applied(answer, 'enable', answer.bundle ?? answer.target);
        if (answer.application != ChangeResultApplication.failed) {
          highlight = answer.bundle ?? answer.target;
        }
        _publish();
      },
      readRemembered: readRegistry,
      remember: rememberRegistry,
      newId: newId,
    );
    _installerSubscription = installer.changed.changes.listen(
      (_) => _publish(),
    );
    _events = remotes.hostEvents.listen((event) {
      if (event is! EmitEvent) return;
      if (event.event == 'plugin-manager/changed') {
        if (_loaded) unawaited(load());
      } else if (event.args.firstOrNull case final Map<Object?, Object?> data) {
        if (event.event == 'plugin-manager/install-state') {
          installer.progress(data.cast<String, Object?>());
        }
        if (event.event == 'plugin-manager/install-log') {
          installer.appendLog(data.cast<String, Object?>());
        }
      }
    });
    _generations = remotes.generations.listen((_) {
      _generation++;
      installer.resetConnection();
      if (_loaded) unawaited(load());
    });
  }
  final HostRemotes remotes;
  late final PluginInstaller installer;
  late final StreamSubscription<int> _installerSubscription;
  StreamSubscription<HostEvent>? _events;
  StreamSubscription<ConnectionGeneration?>? _generations;
  final changed = Observable(0);
  PluginManagerStatus status = PluginManagerStatus.idle;
  List<ManagedPluginPackage> packages = const [];
  inventory.PluginInventorySnapshot? inventorySnapshot;
  PluginManagerNotice? notice;
  PluginConfirmation? confirmation;
  String? highlight;
  final Set<String> busy = {};
  bool refreshing = false;
  String? loadError;
  bool _disposed = false, _loaded = false, _cached = false, _rerun = false;
  int _generation = 0;
  Future<void>? _loading;

  void _publish() {
    if (!_disposed) changed.set(changed.value + 1);
  }

  void _notice(PluginManagerNotice value) {
    if (!_disposed) {
      notice = value;
      _publish();
    }
  }

  void dismissNotice() {
    notice = null;
    _publish();
  }

  void clearHighlight() {
    highlight = null;
    _publish();
  }

  void ensure() {
    if (!_loaded) unawaited(load());
  }

  Future<void> load() {
    if (_disposed) return Future.value();
    _loaded = true;
    unawaited(installer.reconcile());
    if (_loading != null) {
      _rerun = true;
      return _loading!;
    }
    final future = Future<void>.microtask(_read);
    _loading = future;
    return future;
  }

  Future<void> _read() async {
    try {
      do {
        _rerun = false;
        final generation = ++_generation;
        if (status == PluginManagerStatus.idle) {
          status = PluginManagerStatus.loading;
          _publish();
        }
        try {
          final snapshot = await remotes.pluginInventory.list();
          if (_disposed || generation != _generation) continue;
          inventorySnapshot = snapshot;
          if (snapshot.managementAvailable != true) {
            _cached = false;
            packages = const [];
            status = PluginManagerStatus.unavailable;
            _publish();
            continue;
          }
          final values = await Future.wait<Object>([
            remotes.pluginManager.listBundles(),
            remotes.pluginManager.listPlugins(),
          ]);
          if (_disposed || generation != _generation) continue;
          final entries = values[1] as List<PluginInfo>;
          final joined =
              [
                for (final bundle in values[0] as List<BundleInfo>)
                  ManagedPluginPackage(bundle, entries),
              ]..sort(
                (a, b) =>
                    pluginShortName(a.bundle.name)
                        .compareTo(pluginShortName(b.bundle.name)),
              );
          packages = List.unmodifiable(joined);
          _cached = true;
          loadError = null;
          status = PluginManagerStatus.ready;
          _publish();
        } catch (e) {
          if (_disposed || generation != _generation) continue;
          loadError = '$e';
          status = PluginManagerStatus.error;
          _publish();
        }
      } while (_rerun && !_disposed);
    } finally {
      _loading = null;
    }
  }

  Future<void> refresh() async {
    if (_disposed || refreshing) return;
    refreshing = true;
    _publish();
    final watch = Stopwatch()..start();
    await load();
    final remaining = 400 - watch.elapsedMilliseconds;
    if (remaining > 0) {
      await Future<void>.delayed(Duration(milliseconds: remaining));
    }
    if (_disposed) return;
    refreshing = false;
    if (status == PluginManagerStatus.error && _cached) {
      status = PluginManagerStatus.ready;
      notice = const PluginManagerNotice(kind: 'refresh-failed');
    }
    _publish();
  }

  Future<void> _run(
    String key,
    String action,
    Future<ChangeResult> Function() operation, {
    Future<void> Function(ChangeResult)? after,
    bool installOverRunning = false,
  }) async {
    if (_disposed || !busy.add(key)) return;
    notice = null;
    _publish();
    try {
      final answer = await operation();
      if (_disposed) return;
      final runningInstall =
          installOverRunning && answer.error?.code.value == 'stop-profile';
      if (!runningInstall) _applied(answer, action, key);
      if (after != null &&
          (answer.application != ChangeResultApplication.failed ||
              runningInstall)) {
        await after(answer);
      }
    } catch (e) {
      if (!_disposed) {
        _notice(
          PluginManagerNotice(
            kind: 'failed',
            target: key,
            action: action,
            reason: '$e',
          ),
        );
      }
    } finally {
      busy.remove(key);
      _publish();
    }
    if (!_disposed) await load();
  }

  void _applied(ChangeResult answer, String action, String key) {
    final application = answer.application;
    if (application == ChangeResultApplication.failed) {
      _notice(
        PluginManagerNotice(
          kind: 'failed',
          target: key,
          action: action,
          error: answer.error,
          reason: answer.error?.diagnostic,
        ),
      );
    } else if (application != ChangeResultApplication.applied) {
      _notice(
        PluginManagerNotice(
          kind: application.value,
          target: key,
          action: action,
          restartReason: answer.restartReason,
        ),
      );
    }
  }

  Future<void> setEnabled(String name, bool enabled) async {
    final bundle = packages
        .where((p) => p.bundle.name == name)
        .firstOrNull
        ?.bundle;
    if (enabled &&
        bundle?.availability == BundleInfoAvailability.missing &&
        bundle?.installTarget != null) {
      await installer.installCatalog(bundle!, enabled: true);
      return;
    }
    await _run(
      name,
      enabled ? 'enable' : 'disable',
      () => remotes.pluginManager.setBundleEnabled(name, enabled),
    );
  }

  Future<void> setRowEnabled(String entryId, bool enabled) => _run(
    'row:$entryId',
    enabled ? 'rowEnable' : 'rowDisable',
    () => remotes.pluginManager.setPluginEnabled(entryId, enabled),
  );

  void requestRemoval(String name) {
    if (_disposed) return;
    confirmation = PluginConfirmation._(
      'uninstall',
      name,
      () => _run(
        name,
        'uninstall',
        () => remotes.pluginManager.removeBundle(name),
      ),
    );
    _publish();
  }

  void requestBuildApproval() {
    final answer = installer.result;
    if (_disposed ||
        answer == null ||
        installer.phase != PluginInstallPhase.failed ||
        installer.pendingBuilds.isEmpty) {
      return;
    }
    confirmation = PluginConfirmation._(
      'builds',
      installer.subject?.spec ?? '',
      () => installer.approveBuildsAndRetry(answer),
      pendingBuilds: List.unmodifiable(installer.pendingBuilds),
    );
    _publish();
  }

  void requestVersionExemption(List<IncompatiblePlugin> plugins) {
    if (_disposed || plugins.isEmpty) return;
    final frozen = List<IncompatiblePlugin>.unmodifiable(plugins);
    confirmation = PluginConfirmation._(
      'version',
      frozen.map((p) => '${p.name}@${p.version}').join(', '),
      () async {
        for (final plugin in frozen) {
          await _run(
            plugin.name,
            'exemption',
            () => remotes.pluginManager.setVersionExemption(
              '${plugin.name}@${plugin.version}',
              plugin.runtimeVersion,
              true,
              true,
            ),
          );
        }
      },
      incompatible: frozen,
    );
    _publish();
  }

  Future<void> confirm(
    PluginConfirmation expected, {
    bool acceptRisk = false,
  }) async {
    if (_disposed ||
        !identical(confirmation, expected) ||
        (expected.kind == 'version' && !acceptRisk)) {
      return;
    }
    confirmation = null;
    _publish();
    await expected._action();
  }

  void cancelConfirmation() {
    confirmation = null;
    _publish();
  }

  Future<void> update(String name) async {
    final bundle = packages
        .where((p) => p.bundle.name == name)
        .firstOrNull
        ?.bundle;
    if (bundle == null ||
        bundle.installTarget == null ||
        bundle.availability == BundleInfoAvailability.installation) {
      return;
    }
    if (!bundle.installed) {
      await installer.installCatalog(bundle, enabled: bundle.enabled);
      return;
    }
    await _run(
      name,
      'uninstall',
      () => remotes.pluginManager.removeBundle(name),
      installOverRunning: true,
      after: (_) => installer.installCatalog(bundle, enabled: bundle.enabled),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    confirmation = null;
    installer.dispose();
    await _installerSubscription.cancel();
    await _events?.cancel();
    await _generations?.cancel();
  }
}
