import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_agent_presets.dart';

import '../observable.dart';
import '../settings/config_form.dart';
import '../settings/host_remotes.dart';

const agentPresetNamespace = 'agent-preset-registry';
bool presetNeedsCodingTools(AgentPresetRow row) =>
    row.name == null && const ['ptc', 'minimal'].contains(row.id);

typedef PresetSession = ({String id, bool blank, String? preset});

/// Host roster, read-only declared composition, default and one-shot next-session
/// choice. Session callbacks are evaluated again after each asynchronous wait.
class AgentPresetsModel {
  AgentPresetsModel({
    required this.remotes,
    required this.settings,
    required this.tools,
    required this.currentSession,
  }) {
    _offs.add(settings.subscribe(_settingsChanged));
    _offs.add(tools.subscribe(_toolsChanged));
    _events = remotes.hostEvents.listen((event) {
      if (event is EmitEvent &&
          event.event == 'settings/document-updated' &&
          event.args.firstOrNull == agentPresetNamespace) {
        if (_loaded) unawaited(load());
      }
    });
    _generations = remotes.generations.listen((_) {
      _generation++;
      _loadRequest++;
      _viewRequest++;
      document = null;
      if (_loaded) unawaited(load());
    });
  }

  final HostRemotes remotes;
  final ConfigForm settings, tools;
  final PresetSession? Function() currentSession;
  final changed = Observable(0);
  List<AgentPresetRow> rows = const [];
  AgentPresetDocument? document;
  String? error, selectionError, staged;
  String current = '';
  bool loading = false, saving = false, selecting = false, introduce = false;
  bool _loaded = false, _disposed = false;
  int _loadRequest = 0, _viewRequest = 0, _generation = 0;
  Future<void>? _save, _selection, _reconciling;
  final _offs = <void Function()>[];
  StreamSubscription<HostEvent>? _events;
  StreamSubscription<ConnectionGeneration?>? _generations;

  bool get codingEnabled => tools.snapshot.value?['enabled'] == true;
  List<AgentPresetRow> get visibleRows => [
    for (final row in rows)
      if (codingEnabled || !presetNeedsCodingTools(row)) row,
  ];
  List<AgentPresetRow> get options => [
    for (final row in visibleRows)
      if (row.broken == null) row,
  ];
  String get _fallback =>
      rows.where((r) => r.isDefault).firstOrNull?.id ??
      rows.firstOrNull?.id ??
      '';
  void _notify() {
    if (!_disposed) changed.set(changed.value + 1);
  }

  Future<void> load() async {
    if (_disposed) return;
    _loaded = true;
    final request = ++_loadRequest;
    loading = true;
    _notify();
    try {
      List<AgentPresetRow> next;
      try {
        next = (await remotes.agentPresets.list()).presets;
      } on RemoteException catch (e) {
        if (e.code != 'gateway/invocation-unavailable') rethrow;
        next = const [];
      }
      if (_disposed || request != _loadRequest) return;
      rows = List.unmodifiable(next);
      error = null;
      final session = currentSession();
      current = staged ?? (session == null ? _fallback : session.preset ?? '');
    } on Object catch (e) {
      if (!_disposed && request == _loadRequest) error = _message(e);
    } finally {
      if (!_disposed && request == _loadRequest) {
        loading = false;
        _notify();
      }
    }
    if (!_disposed && request == _loadRequest) await apply();
  }

  Future<void> view(String id) async {
    final request = ++_viewRequest;
    document = null;
    error = null;
    _notify();
    try {
      final result = await remotes.agentPresets.read(id);
      if (!_disposed && request == _viewRequest) document = result;
    } on Object catch (e) {
      if (!_disposed && request == _viewRequest) error = _message(e);
    }
    if (request == _viewRequest) _notify();
  }

  void closeView({bool announce = true}) {
    _viewRequest++;
    document = null;
    if (announce) _notify();
  }

  void stage(String id, {bool announce = false}) {
    if (_disposed) return;
    staged = id;
    current = id;
    selectionError = null;
    introduce = announce;
    _notify();
  }

  Future<void> select(String id) async {
    if (selecting || _disposed) return;
    stage(id);
    await apply();
  }

  /// A running session's composition is immutable. The Host independently
  /// enforces this rule; a stale blank summary can only produce a refusal.
  Future<void> apply() async {
    if (_disposed || selecting) return;
    final id = staged;
    final session = currentSession();
    if (id == null) {
      current = session == null ? _fallback : session.preset ?? '';
      _notify();
      return;
    }
    if (session == null) return;
    staged = null;
    if (!session.blank || session.preset == id) {
      introduce = false;
      _notify();
      return;
    }
    final generation = _generation;
    final done = Completer<void>();
    _selection = done.future;
    selecting = true;
    selectionError = null;
    _notify();
    try {
      final accepted = await remotes.agentPresets.select(session.id, id);
      if (_disposed ||
          generation != _generation ||
          currentSession()?.id != session.id) {
        return;
      }
      current = staged ?? accepted;
    } on Object catch (e) {
      if (!_disposed &&
          generation == _generation &&
          currentSession()?.id == session.id) {
        selectionError = e is RemoteException && e.details['reason'] is String
            ? e.details['reason']! as String
            : _message(e);
        current = staged ?? session.preset ?? '';
      }
    } finally {
      selecting = false;
      if (!_disposed && currentSession()?.id != session.id) {
        final now = currentSession();
        current = staged ?? (now == null ? _fallback : now.preset ?? '');
      }
      _selection = null;
      done.complete();
      _notify();
    }
  }

  Future<void> makeDefault(String id) async {
    if (_disposed || saving) return;
    final session = currentSession();
    final captured = session?.blank == true ? session!.id : null;
    await _writeDefault(id);
    if (_disposed || captured == null || error != null) return;
    while (_selection != null) {
      await _selection;
    }
    final now = currentSession();
    if (now?.id != captured || now?.blank != true) return;
    final accepted = rows.where((r) => r.isDefault).firstOrNull;
    if (accepted == null) return;
    await select(accepted.id);
  }

  Future<void> _writeDefault(String id, {int? revision}) async {
    if (_disposed || saving) return;
    final generation = _generation;
    final done = Completer<void>();
    _save = done.future;
    saving = true;
    error = null;
    _notify();
    try {
      final accepted = await settings.mutate([
        SetOp(const ['selectedDefault'], id),
      ], expectedRevision: revision);
      if (_disposed || generation != _generation) return;
      await load();
      if (!accepted) error = 'presetSaveRefused';
    } on Object catch (e) {
      if (!_disposed && generation == _generation) error = _message(e);
    } finally {
      saving = false;
      _save = null;
      done.complete();
      _notify();
    }
  }

  void _settingsChanged() {
    _notify();
    _reconcile();
  }

  void _toolsChanged() {
    if (!codingEnabled) {
      staged = null;
      introduce = false;
      unawaited(apply());
    }
    _notify();
    _reconcile();
  }

  void _reconcile() {
    if (_disposed || codingEnabled || _reconciling != null) return;
    _reconciling = Future<void>.microtask(() async {
      while (_save != null) {
        await _save;
      }
      if (_disposed || codingEnabled) return;
      final form = settings.snapshot;
      if (form.status != ConfigFormStatus.ready ||
          !form.writable ||
          form.revision == null) {
        return;
      }
      await load();
      if (_disposed || codingEnabled || error != null) return;
      final row = rows.where((r) => r.isDefault).firstOrNull;
      if (row == null || !presetNeedsCodingTools(row)) return;
      if (!rows.any((r) => r.id == 'standard' && r.broken == null)) {
        error = 'standardUnavailable';
        _notify();
        return;
      }
      await _writeDefault('standard', revision: form.revision);
    }).whenComplete(() => _reconciling = null);
  }

  Future<void> dispose() async {
    _disposed = true;
    _loadRequest++;
    _viewRequest++;
    for (final off in _offs) {
      off();
    }
    await _events?.cancel();
    await _generations?.cancel();
    await changed.dispose();
  }
}

String _message(Object e) => e is RemoteException ? e.message : '$e';
