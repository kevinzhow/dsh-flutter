import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_plugin_manager.dart';

import '../observable.dart';
import '../settings/host_remotes.dart';

const officialPluginRegistry = 'https://registry.npmjs.org/';
const mirrorPluginRegistry = 'https://registry.npmmirror.com/';

String pluginRegistryKey(String? registry, String? resolved) {
  final text = registry ?? resolved;
  if (text == null) return '';
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !uri.hasAuthority ||
      !const ['http', 'https'].contains(uri.scheme)) {
    return text;
  }
  return uri
      .replace(path: uri.path.endsWith('/') ? uri.path : '${uri.path}/')
      .toString();
}

List<String?> pluginRegistryOffers(PluginRegistries? registries) {
  final keys = <String>{};
  return [
    for (final registry in [
      if (registries != null) ...[
        registries.registry,
        ...registries.fallbackRegistries,
      ],
      null,
    ])
      if (keys.add(pluginRegistryKey(registry, registries?.resolved))) registry,
  ];
}

class PluginRegistryChoice {
  const PluginRegistryChoice.offered(this.registry) : custom = false;
  const PluginRegistryChoice.custom(this.registry) : custom = true;
  final String? registry;
  final bool custom;
}

enum PluginInstallPhase {
  idle,
  checking,
  starting,
  running,
  cancelling,
  applying,
  unconfirmed,
  unknown,
  done,
  failed;

  bool get pending => const {
    starting,
    running,
    cancelling,
    applying,
    unconfirmed,
  }.contains(this);
}

class PluginInstallSubject {
  const PluginInstallSubject({
    required this.spec,
    required this.inspection,
    this.selection,
    this.saveExact,
  });
  final String spec;
  final PluginSpecInspectionAccepted inspection;
  final bool? selection, saveExact;
}

class PluginInstallRun {
  PluginInstallRun({
    required this.id,
    required this.command,
    required this.cwd,
  });
  final String id, command, cwd;
  String output = '';
  int? exitCode;
  bool settled = false;
}

class _InstallRequest {
  _InstallRequest(this.id);
  final String id;
  bool acknowledged = false, replyLost = false, recovering = false;
  _Cancellation? cancellation;
}

class _Cancellation {
  bool waitingForStart = false;
}

/// The Host owns installation and restoration. A lost call leaves an uncertain
/// request; only a Host result or confirmed cancellation releases that request.
class PluginInstaller {
  PluginInstaller({
    required this.remotes,
    required this.reload,
    required this.listedAvailability,
    required this.notify,
    this.reportChange,
    this.readRemembered,
    this.remember,
    String Function()? newId,
  }) : _newId = newId ?? randomUuid;

  final HostRemotes remotes;
  final Future<void> Function() reload;
  final String? Function(String) listedAvailability;
  final void Function(String) notify;
  final void Function(ChangeResult)? reportChange;
  final PluginRegistryChoice? Function()? readRemembered;
  final void Function(PluginRegistryChoice)? remember;
  final String Function() _newId;
  final changed = Observable(0);
  PluginInstallPhase phase = PluginInstallPhase.idle;
  bool open = false,
      detailsOpen = false,
      registryError = false,
      enabling = false;
  String spec = '';
  PluginRegistryChoice registry = const PluginRegistryChoice.offered(null);
  PluginRegistries? registries;
  PluginInstallSubject? subject;
  PluginSpecInspectionRefused? inputError;
  String? error, uncertainty, installed, installedVersion, requestId;
  ChangeResult? result;
  List<PluginInstallRun> runs = [];
  List<String?> attemptedRegistries = [];
  int totalAttempts = 0;
  _InstallRequest? _request;
  int _inspect = 0, _registryRead = 0;
  bool _disposed = false, _transient = false, _confirmed = false;
  Future<void>? _readingRegistries;
  List<String> get pendingBuilds => result?.pendingBuilds ?? const [];
  bool get restartRequired =>
      result?.application == ChangeResultApplication.restartRequired;
  bool get cancellable => const {
    PluginInstallPhase.starting,
    PluginInstallPhase.running,
    PluginInstallPhase.unconfirmed,
  }.contains(phase);

  void _publish() {
    if (!_disposed) changed.set(changed.value + 1);
  }

  void _phase(PluginInstallPhase value) {
    phase = value;
    _publish();
  }

  bool _current(_InstallRequest request) =>
      !_disposed && identical(_request, request);

  bool show({
    String? installSpec,
    String? transientRegistry,
    bool confirmed = false,
  }) {
    if (_disposed) return false;
    if (requestId != null) {
      open = true;
      _publish();
      unawaited(reconcile());
      return false;
    }
    _inspect++;
    _reset();
    open = true;
    spec = installSpec ?? '';
    _transient = transientRegistry != null;
    _confirmed = confirmed;
    registry = transientRegistry != null
        ? PluginRegistryChoice.custom(transientRegistry)
        : readRemembered?.call() ?? const PluginRegistryChoice.offered(null);
    final read = ++_registryRead;
    _readingRegistries = _readRegistries(read);
    _publish();
    return true;
  }

  Future<void> _readRegistries(int read) async {
    final initial = registry;
    bool current() => !_disposed && read == _registryRead && open;
    bool untouched() =>
        current() &&
        identical(registry, initial) &&
        (phase == PluginInstallPhase.idle ||
            phase == PluginInstallPhase.checking);
    try {
      final value = await remotes.pluginManager.registries();
      if (!current()) return;
      registries = value;
      final remembered = readRemembered?.call();
      if (!untouched() || _transient) {
        _publish();
        return;
      }
      if (remembered == null) {
        registry = PluginRegistryChoice.offered(value.registry);
      } else if (remembered.custom || remembered.registry == null) {
        registry = remembered;
      } else {
        final key = pluginRegistryKey(remembered.registry, value.resolved);
        final offers = pluginRegistryOffers(value);
        final matching = offers.where(
          (r) => pluginRegistryKey(r, value.resolved) == key,
        );
        registry = matching.isNotEmpty
            ? PluginRegistryChoice.offered(matching.first)
            : PluginRegistryChoice.custom(remembered.registry);
      }
      final assigned = registry;
      _publish();
      final mirror = value.fallbackRegistries
          .where((r) => r == mirrorPluginRegistry)
          .firstOrNull;
      if (remembered != null ||
          value.registry != null ||
          pluginRegistryKey(value.resolved, null) != officialPluginRegistry ||
          mirror == null) {
        return;
      }
      final fastest = await remotes.pluginRegistryProbe.fastest();
      if (!current() ||
          !identical(registry, assigned) ||
          (phase != PluginInstallPhase.idle &&
              phase != PluginInstallPhase.checking) ||
          fastest != mirror) {
        return;
      }
      registry = PluginRegistryChoice.offered(mirror);
      _publish();
    } catch (_) {
      // The default and a typed URL remain usable when the registry read fails.
    }
  }

  void chooseRegistry(PluginRegistryChoice value) {
    if (phase.pending || phase == PluginInstallPhase.checking) return;
    registry = value;
    _transient = false;
    registryError = false;
    _publish();
  }

  void edit(String value) {
    if (phase.pending || phase == PluginInstallPhase.checking) return;
    _backToSpec();
    subject = null;
    spec = value;
    _publish();
  }

  void setDetails(bool value) {
    detailsOpen = value;
    _publish();
  }

  Future<void> close() async {
    if (phase.pending) {
      open = false;
      _publish();
      await cancel();
    } else {
      _inspect++;
      _registryRead++;
      _reset();
      _publish();
    }
  }

  void hide() {
    open = false;
    _publish();
  }

  Future<void> install() async {
    if (_disposed ||
        phase.pending ||
        phase == PluginInstallPhase.checking ||
        spec.trim().isEmpty) {
      return;
    }
    final typed = spec.trim();
    if (typed == 'https://github.com/author/dsh-plugin' ||
        typed == '/Users/name/my-plugin') {
      error = typed.startsWith('https:') ? 'template-git' : 'template-path';
      inputError = null;
      _publish();
      return;
    }
    final catalog = subject?.selection != null && subject?.spec == typed
        ? subject
        : null;
    final availability = listedAvailability(typed);
    if (availability != null && availability != 'missing' && catalog == null) {
      inputError = PluginSpecInspectionRefused(
        problem: PluginInspectProblem.alreadyInstalled,
        reason: typed,
      );
      error = availability == 'installation' ? 'shipped' : 'already-installed';
      _publish();
      return;
    }
    final url = registry.registry?.trim();
    final uri = url == null ? null : Uri.tryParse(url);
    if (registry.custom &&
        (uri == null ||
            !const ['http', 'https'].contains(uri.scheme) ||
            !uri.hasAuthority)) {
      registryError = true;
      _publish();
      return;
    }
    final ticket = ++_inspect;
    inputError = null;
    error = null;
    uncertainty = null;
    result = null;
    runs = [];
    attemptedRegistries = [];
    totalAttempts = 0;
    _phase(PluginInstallPhase.checking);
    final reading = _readingRegistries;
    if (reading != null) await reading;
    if (_disposed || ticket != _inspect) return;
    final selected = registry.custom
        ? PluginRegistryChoice.custom(registry.registry!.trim())
        : registry;
    registry = selected;
    if (!_transient) remember?.call(selected);
    PluginSpecInspection inspection;
    try {
      inspection =
          catalog?.inspection ??
          await remotes.pluginManager.inspect(
            typed,
            InspectOptions(registry: selected.registry, registryPresent: true),
          );
    } catch (e) {
      if (!_disposed && ticket == _inspect) {
        error = '$e';
        _phase(PluginInstallPhase.idle);
      }
      return;
    }
    if (_disposed || ticket != _inspect) return;
    if (inspection is PluginSpecInspectionRefused) {
      inputError = inspection;
      _phase(PluginInstallPhase.idle);
      return;
    }
    if (inspection is! PluginSpecInspectionAccepted) {
      error = 'Unrecognized inspection result';
      _phase(PluginInstallPhase.idle);
      return;
    }
    await _start(
      PluginInstallSubject(
        spec: typed,
        inspection: PluginSpecInspectionAccepted(
          kind: inspection.kind,
          name: inspection.name,
          version: inspection.version,
          description: inspection.description,
          bundle: inspection.bundle,
          registry: catalog == null ? inspection.registry : selected.registry,
          host: inspection.host,
        ),
        selection: catalog?.selection,
        saveExact: catalog?.saveExact,
      ),
    );
  }

  ({String? registry})? get githubRecovery {
    if (_confirmed ||
        phase != PluginInstallPhase.failed ||
        result?.failedAt?.value != 'spec-host' ||
        !const [
          'network',
          'timeout',
        ].contains(result?.packageResult?.kind?.value)) {
      return null;
    }
    final host = subject?.inspection.host?.toLowerCase().split(':').first;
    if (host != 'github.com' && host?.endsWith('.github.com') != true) {
      return null;
    }
    for (final offer in pluginRegistryOffers(registries)) {
      if (pluginRegistryKey(offer, registries?.resolved) ==
          mirrorPluginRegistry) {
        return (registry: offer);
      }
    }
    return null;
  }

  void recoverGithub() {
    final recovery = githubRecovery;
    if (recovery == null) return;
    final wasMirror =
        pluginRegistryKey(registry.registry, registries?.resolved) ==
        mirrorPluginRegistry;
    _backToSpec();
    spec = '';
    subject = null;
    if (!wasMirror) {
      registry = PluginRegistryChoice.offered(recovery.registry);
      remember?.call(registry);
    }
    _publish();
  }

  Future<void> installCatalog(
    BundleInfo bundle, {
    required bool enabled,
  }) async {
    final target = bundle.installTarget;
    if (_disposed || target == null) return;
    if (phase.pending || phase == PluginInstallPhase.checking) {
      open = true;
      _publish();
      return;
    }
    show();
    spec = target.spec;
    subject = PluginInstallSubject(
      spec: target.spec,
      selection: enabled,
      saveExact: target.spec.startsWith('link:') ? null : true,
      inspection: PluginSpecInspectionAccepted(
        kind: target.spec.startsWith('link:')
            ? InstallSpecKind.path
            : InstallSpecKind.registry,
        name: bundle.name,
        version: target.version,
        bundle: true,
        registry: registry.registry,
      ),
    );
    await install();
  }

  Future<void> _start(
    PluginInstallSubject checked, {
    List<String>? approvedBuilds,
  }) async {
    final request = _InstallRequest(_newId());
    _request = request;
    requestId = request.id;
    subject = checked;
    runs = [];
    attemptedRegistries = [];
    totalAttempts = 0;
    result = null;
    error = null;
    uncertainty = null;
    installed = null;
    installedVersion = null;
    _phase(PluginInstallPhase.starting);
    try {
      final answer = await remotes.pluginManager.installBundle(
        checked.spec,
        InstallBundleOptions(
          enabled: checked.selection ?? false,
          requestId: request.id,
          registry: checked.inspection.registry,
          registryPresent: true,
          saveExact: checked.saveExact,
          approvedBuilds: approvedBuilds,
        ),
      );
      if (_current(request)) _settle(answer);
    } catch (e) {
      if (!_current(request)) return;
      request.replyLost = true;
      _uncertain('result', '$e');
      unawaited(reconcile());
    }
  }

  Future<void> reconcile() async {
    final request = _request;
    if (request == null ||
        !request.replyLost ||
        request.recovering ||
        _disposed) {
      return;
    }
    request.recovering = true;
    try {
      final answer = await remotes.pluginManager.waitForInstall(request.id);
      if (!_current(request)) return;
      if (answer != null) {
        _settle(answer);
        return;
      }
      _request = null;
      _settleRuns(null);
      error = null;
      uncertainty = null;
      _phase(PluginInstallPhase.unknown);
      _hidden('unknown');
      unawaited(reload());
    } catch (e) {
      if (_current(request)) _uncertain('result', '$e');
    } finally {
      request.recovering = false;
    }
  }

  void progress(Map<String, Object?> data) {
    final request = _request;
    if (request == null || data['requestId'] != request.id || !phase.pending) {
      return;
    }
    request.acknowledged = true;
    if (phase == PluginInstallPhase.applying) return;
    if (data['phase'] == 'installing' && request.cancellation != null) {
      if (request.cancellation!.waitingForStart) {
        unawaited(_sendCancellation(request, request.cancellation!));
      }
      return;
    }
    final next = switch (data['phase']) {
      'installing' => PluginInstallPhase.running,
      'cancelling' => PluginInstallPhase.cancelling,
      'applying' => PluginInstallPhase.applying,
      _ => null,
    };
    if (next == null) return;
    final attempt = data['attempt'];
    if (attempt is Map && attempt['total'] is num) {
      attemptedRegistries = [
        ...attemptedRegistries,
        attempt['registry'] as String?,
      ];
      totalAttempts = (attempt['total'] as num).toInt();
    }
    _phase(next);
  }

  void appendLog(Map<String, Object?> data) {
    if (data['requestId'] != requestId ||
        data['jobId'] is! String ||
        data['text'] is! String) {
      return;
    }
    if (const {
      PluginInstallPhase.starting,
      PluginInstallPhase.cancelling,
      PluginInstallPhase.unconfirmed,
    }.contains(phase)) {
      progress({'requestId': requestId, 'phase': 'installing'});
    }
    var run = runs.where((r) => r.id == data['jobId']).firstOrNull;
    if (run == null) {
      if (!phase.pending) return;
      run = PluginInstallRun(
        id: data['jobId'] as String,
        command: (data['argv'] as List? ?? []).join(' '),
        cwd: data['cwd'] as String? ?? '',
      );
      runs = [...runs, run];
    }
    run.output += data['text'] as String;
    if (data.containsKey('exitCode')) {
      run.exitCode = (data['exitCode'] as num?)?.toInt();
      run.settled = true;
    }
    _publish();
  }

  void _settleRuns(int? exitCode) {
    for (final run in runs) {
      if (!run.settled) {
        run.exitCode = exitCode;
        run.settled = true;
      }
    }
  }

  void _settle(ChangeResult answer) {
    _request = null;
    result = answer;
    error = null;
    uncertainty = null;
    if (answer.registries != null) {
      attemptedRegistries = answer.registries!;
      if (totalAttempts < attemptedRegistries.length) {
        totalAttempts = attemptedRegistries.length;
      }
    }
    final application = answer.application;
    if (application == ChangeResultApplication.cancelled) {
      _backToSpec();
      notify('cancelled');
    } else if (application == ChangeResultApplication.failed) {
      _settleRuns(answer.packageResult?.exitCode);
      _phase(PluginInstallPhase.failed);
      _hidden('failed');
    } else if ({
      ChangeResultApplication.applied,
      ChangeResultApplication.restartRequired,
      ChangeResultApplication.overridden,
    }.contains(application)) {
      _settleRuns(0);
      installed = answer.bundle;
      installedVersion = answer.version;
      _phase(PluginInstallPhase.done);
      if (subject?.selection != null && answer.bundle != null) {
        reportChange?.call(answer);
      }
      _hidden('done');
    } else {
      _settleRuns(null);
      _phase(PluginInstallPhase.unknown);
      _hidden('unknown');
    }
    unawaited(reload());
  }

  Future<void> cancel() async {
    if (_disposed) return;
    if (const {
      PluginInstallPhase.checking,
      PluginInstallPhase.failed,
      PluginInstallPhase.unknown,
    }.contains(phase)) {
      _inspect++;
      _backToSpec();
      return;
    }
    final request = _request;
    if (!cancellable || request == null) return;
    if (request.cancellation != null &&
        !request.cancellation!.waitingForStart) {
      return;
    }
    final cancellation = _Cancellation();
    request.cancellation = cancellation;
    await _sendCancellation(request, cancellation);
  }

  Future<void> _sendCancellation(
    _InstallRequest request,
    _Cancellation cancellation,
  ) async {
    final acknowledged = request.acknowledged;
    cancellation.waitingForStart = false;
    error = null;
    _phase(PluginInstallPhase.cancelling);
    try {
      final answer = await remotes.pluginManager.cancelInstall(request.id);
      if (!_current(request) ||
          !identical(request.cancellation, cancellation)) {
        return;
      }
      if (answer.status == PluginInstallCancellationStatus.cancelled) {
        _backToSpec();
        notify('cancelled');
        unawaited(reload());
      } else if (answer.status == PluginInstallCancellationStatus.tooLate) {
        request.acknowledged = true;
        request.cancellation = null;
        _phase(PluginInstallPhase.applying);
        _hidden('applying');
        unawaited(reconcile());
      } else if (request.replyLost) {
        request.cancellation = null;
        _uncertain('result', '');
        unawaited(reconcile());
      } else if (!acknowledged && phase != PluginInstallPhase.applying) {
        if (request.acknowledged) {
          await _sendCancellation(request, cancellation);
        } else {
          cancellation.waitingForStart = true;
          _uncertain('acceptance', '');
        }
      } else {
        request.cancellation = null;
        _uncertain('cancellation', '');
      }
    } catch (e) {
      if (!_current(request) ||
          !identical(request.cancellation, cancellation)) {
        return;
      }
      cancellation.waitingForStart = !request.acknowledged;
      if (request.acknowledged) request.cancellation = null;
      _uncertain(request.replyLost ? 'result' : 'cancellation', '$e');
    }
  }

  void _uncertain(String kind, String message) {
    uncertainty = kind;
    error = message;
    if (phase != PluginInstallPhase.applying) {
      phase = PluginInstallPhase.unconfirmed;
    }
    _publish();
    _hidden('unconfirmed');
  }

  void _hidden(String outcome) {
    if (!open) notify('install:$outcome');
  }

  void _backToSpec() {
    final oldSubject = subject;
    final visible = open,
        value = spec,
        choices = registries,
        selected = registry;
    _reset();
    open = visible;
    spec = value;
    registries = choices;
    registry = selected;
    if (oldSubject?.selection != null) subject = oldSubject;
    _publish();
  }

  void _reset() {
    _request = null;
    requestId = null;
    phase = PluginInstallPhase.idle;
    open = false;
    spec = '';
    subject = null;
    result = null;
    runs = [];
    error = null;
    uncertainty = null;
    inputError = null;
    registries = null;
    registryError = false;
    detailsOpen = false;
    enabling = false;
    installed = null;
    installedVersion = null;
    attemptedRegistries = [];
    totalAttempts = 0;
  }

  /// UI must explicitly confirm the exact pending package names. Rechecking the
  /// result identity prevents an old confirmation from authorizing a later run.
  Future<void> approveBuildsAndRetry(ChangeResult confirmed) async {
    if (_disposed ||
        !identical(result, confirmed) ||
        phase != PluginInstallPhase.failed ||
        subject == null ||
        pendingBuilds.isEmpty) {
      return;
    }
    await _start(subject!, approvedBuilds: [...pendingBuilds]);
  }

  Future<void> enableInstalled() async {
    if (_disposed ||
        phase != PluginInstallPhase.done ||
        enabling ||
        installed == null) {
      return;
    }
    enabling = true;
    _publish();
    try {
      final answer = await remotes.pluginManager.setBundleEnabled(
        installed!,
        true,
      );
      if (_disposed) return;
      if (reportChange != null) {
        reportChange!(answer);
      } else if (answer.application != ChangeResultApplication.applied) {
        notify(answer.application.value);
      }
    } catch (e) {
      if (!_disposed) notify('$e');
    }
    if (_disposed) return;
    final name = installed;
    _reset();
    _publish();
    if (name != null) await reload();
  }

  void resetConnection() {
    _inspect++;
    if (phase == PluginInstallPhase.checking) {
      _phase(PluginInstallPhase.idle);
    }
    final request = _request;
    if (request != null) {
      request.replyLost = true;
      _uncertain('result', '');
      unawaited(reconcile());
    }
  }

  void dispose() {
    _disposed = true;
    _inspect++;
    _registryRead++;
    _request = null;
  }
}
