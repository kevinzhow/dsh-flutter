import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_credentials.dart';
import 'package:dsh_client/generated_llm.dart';
import 'package:dsh_client/generated_settings.dart';

import '../observable.dart';
import 'host_remotes.dart';
import 'schema.dart';
import 'settings_mirror.dart';

/// Configurable declarations first, live-only routes appended, with account
/// and official routes first. Original order is retained within each group.
List<ProviderEntry> joinProviderDirectory(
  List<LlmProviderInfo> live,
  List<LlmConfigurableProvider> directory,
) {
  final active = {for (final row in live) row.id};
  final declared = {for (final row in directory) row.provider};
  final rows = [
    for (final row in directory)
      ProviderEntry(row, active.contains(row.provider)),
    for (final row in live)
      if (!declared.contains(row.id))
        ProviderEntry(
          LlmConfigurableProvider(
            provider: row.id,
            displayName: row.name,
            settingsNs: '',
            settingsPath: const [],
          ),
          true,
        ),
  ];
  int rank(ProviderEntry row) => switch (row.directory.provider) {
    'deepseek-account' => 0,
    'deepseek-official' => 1,
    _ => 2,
  };
  return [
    for (var rankValue = 0; rankValue < 3; rankValue++)
      ...rows.where((row) => rank(row) == rankValue),
  ];
}

class ProviderEntry {
  const ProviderEntry(this.directory, this.active);
  final LlmConfigurableProvider directory;
  final bool active;
}

String deriveKeyRef(String provider) =>
    '${provider.toUpperCase().replaceAll(RegExp('[^A-Z0-9]+'), '_')}_API_KEY';

/// Empty keeps the stored key. Whitespace-only, pasted assignments, wrapped
/// quotes and non-printable/space characters are field failures.
String? apiKeyFailure(String draft) {
  if (draft.isEmpty) return null;
  final value = _modelTrim(draft);
  if (value.isEmpty) return 'keyBlank';
  final quoted =
      value.length > 1 &&
      const ['"', "'", '`'].contains(value[0]) &&
      value.endsWith(value[0]);
  return quoted ||
          RegExp(r'^[A-Z][A-Z0-9_]*=[^=]').hasMatch(value) ||
          !RegExp(r'^[\x21-\x7E]+$').hasMatch(value)
      ? 'keyIllegalCharacters'
      : null;
}

num? parseModelCapacity(String text) {
  final value = _modelTrim(text);
  if (value.isEmpty) return null;
  final m = RegExp(
    r'^(\d+(?:\.\d+)?)([km])?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (m == null) return double.nan;
  final scale = switch (m[2]?.toLowerCase()) {
    'k' => 1000,
    'm' => 1000000,
    _ => 1,
  };
  final result = double.parse(m[1]!) * scale;
  if (!result.isFinite) return result;
  return (result - result.round()).abs() < 1e-6 ? result.round() : result;
}

String formatModelCapacity(num value) {
  if (value > 0 && value.isFinite && value == value.truncateToDouble()) {
    if (value % 1000000 == 0) return '${value ~/ 1000000}M';
    if (value % 1000 == 0) return '${value ~/ 1000}K';
    return '${value.toInt()}';
  }
  return '$value';
}

typedef ModelValidationFailure = ({int index, String key});
List<Map<String, Object?>> modelDrafts(Object? value) => value is List
    ? [
        for (final row in value)
          row is Map ? Map<String, Object?>.from(row) : {},
      ]
    : [];

ModelValidationFailure? validateProviderModels(Object? value) {
  final seen = <String>{};
  final models = modelDrafts(value);
  for (var i = 0; i < models.length; i++) {
    final row = models[i];
    final id = row['id'];
    if (id is! String || _modelTrim(id).isEmpty) {
      return (index: i, key: 'modelIdRequired');
    }
    if (!seen.add(_modelTrim(id))) return (index: i, key: 'modelIdDuplicate');
    if (row.containsKey('name') &&
        (row['name'] is! String || (row['name'] as String).isEmpty)) {
      return (index: i, key: 'modelNameInvalid');
    }
    for (final field in ['contextWindow', 'maxTokens']) {
      if (!row.containsKey(field)) continue;
      final number = row[field];
      if (number is! num ||
          !number.isFinite ||
          number <= 0 ||
          number != number.truncateToDouble()) {
        return (
          index: i,
          key: field == 'contextWindow'
              ? 'modelContextInvalid'
              : 'modelMaxTokensInvalid',
        );
      }
    }
  }
  return null;
}

ModelValidationFailure? validateModelReasoning(Object? value) {
  final models = modelDrafts(value);
  for (var i = 0; i < models.length; i++) {
    final row = models[i];
    final efforts = row['reasoningEfforts'];
    if (!row.containsKey('reasoningEfforts') ||
        efforts is! Map && efforts != null) {
      continue;
    }
    final entries = efforts is Map ? efforts : const <String, Object?>{};
    if (entries.entries.any(
      (e) => e.value is String
          ? (e.value as String).isEmpty
          : e.key != 'off' || e.value != null,
    )) {
      return (index: i, key: 'modelReasoningValueRequired');
    }
    if (!entries.keys.any((key) => key != 'off')) {
      return (index: i, key: 'modelReasoningNeedsLevel');
    }
  }
  return null;
}

List<String> providerProtocols(SettingsNamespaceView? view) => view == null
    ? []
    : SettingsSchema.rehydrate(view.schema)
              .nodeAtPath(['providers', '\u0000probe', 'api'])
              ?.choices
              .whereType<String>()
              .toList() ??
          [];

List<String> providerReasoningLevels(SettingsNamespaceView? view) {
  if (view == null) return [];
  final node = SettingsSchema.rehydrate(
    view.schema,
  ).nodeAtPath(['providers', '\u0000probe', 'models', '0', 'reasoningEfforts']);
  for (final branch in node?.list ?? <SettingsSchema>[]) {
    if (branch.type == 'dict') {
      return branch.sKey?.choices.whereType<String>().toList() ?? [];
    }
  }
  return [];
}

class ModelProviderRow {
  const ModelProviderRow({
    required this.entry,
    required this.configured,
    required this.removable,
    this.apiKeyEnv,
    this.credential,
    this.derivedCredential,
    this.credentialChecks,
    this.accountAvailable = false,
  });
  final ProviderEntry entry;
  final bool configured;
  final bool removable;
  final String? apiKeyEnv;
  final CredentialInfo? credential;
  final CredentialInfo? derivedCredential;
  final Map<String, CredentialInfo>? credentialChecks;
  final bool accountAvailable;
  bool get usable =>
      entry.active &&
      (entry.directory.provider == 'deepseek-account'
          ? accountAvailable
          : apiKeyEnv == null || credential?.configured == true);
}

enum ModelsSettingsStatus { idle, loading, ready, error }

class ModelsSettingsSnapshot {
  const ModelsSettingsSnapshot({
    this.status = ModelsSettingsStatus.idle,
    this.error,
    this.credentialError,
    this.writable = false,
    this.rows = const [],
    this.namespaces = const {},
  });
  final ModelsSettingsStatus status;
  final String? error;
  final String? credentialError;
  final bool writable;
  final List<ModelProviderRow> rows;
  final Map<String, SettingsNamespaceView> namespaces;
}

/// Lazy page store using the shared settings mirror. Latest refresh owns all
/// callers; credentials failure only degrades badges, retaining usable rows.
class ModelsSettingsStore {
  ModelsSettingsStore(this.remotes, this.mirror) {
    for (final event in const [
      'llm/adapters-updated',
      'settings/document-updated',
      'credentials/record-updated',
      'credentials/reference-updated',
    ]) {
      _subscriptions.add(
        remotes.emitted(event).listen((_) => _refreshIfLoaded()),
      );
    }
    _subscriptions.add(
      remotes.generations.listen((_) {
        if (!_loaded) return;
        state.set(const ModelsSettingsSnapshot());
        _refreshIfLoaded();
      }),
    );
  }
  final HostRemotes remotes;
  final SettingsDescribeMirror mirror;
  final Observable<ModelsSettingsSnapshot> state = Observable(
    const ModelsSettingsSnapshot(),
  );
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final List<Completer<void>> _pending = [];
  int _generation = 0;
  bool _loaded = false;
  bool get disposed => _disposed;
  bool _disposed = false;

  void _refreshIfLoaded() {
    if (_loaded && !_disposed) unawaited(load());
  }

  Future<void> load() {
    if (_disposed) return Future.value();
    _loaded = true;
    final completer = Completer<void>();
    _pending.add(completer);
    final generation = ++_generation;
    unawaited(
      _read(generation).whenComplete(() {
        if (_disposed || generation != _generation) return;
        for (final pending in _pending.toList()) {
          pending.complete();
        }
        _pending.clear();
      }),
    );
    return completer.future;
  }

  bool _owns(int generation) => !_disposed && generation == _generation;
  void _fail(Object error) {
    final previous = state.value;
    state.set(
      ModelsSettingsSnapshot(
        status: ModelsSettingsStatus.error,
        error: settingsError(error),
        credentialError: previous.credentialError,
        writable: previous.writable,
        rows: previous.rows,
        namespaces: previous.namespaces,
      ),
    );
  }

  Future<void> _read(int generation) async {
    final previous = state.value;
    state.set(
      ModelsSettingsSnapshot(
        status: ModelsSettingsStatus.loading,
        rows: previous.rows,
        namespaces: previous.namespaces,
        writable: previous.writable,
      ),
    );
    try {
      final values = await Future.wait<Object?>([
        remotes.llm.listProviders(),
        remotes.llm.listConfigurableProviders(),
        mirror.ensure(),
      ]);
      if (!_owns(generation)) return;
      final view = mirror.snapshot.view;
      if (view == null) {
        _fail(mirror.snapshot.error ?? 'settings unavailable');
        return;
      }
      final entries = joinProviderDirectory(
        values[0] as List<LlmProviderInfo>,
        values[1] as List<LlmConfigurableProvider>,
      );
      final namespaces = {for (final v in view.namespaces) v.ns: v};
      var accountAvailable = false;
      if (entries.any((e) => e.directory.provider == 'deepseek-account')) {
        try {
          final catalog = await remotes.session.modelCatalog();
          accountAvailable = catalog.groups.any(
            (g) => g.id == 'deepseek-account' && g.models.isNotEmpty,
          );
        } on Object {
          /* Account capability read does not hide other providers. */
        }
      }
      if (!_owns(generation)) return;
      final refs = <String>{};
      for (final entry in entries) {
        final d = entry.directory;
        if (d.provider == 'deepseek-account') continue;
        final ref = _keyRef(namespaces[d.settingsNs], d.settingsPath);
        refs.addAll(
          ref == null
              ? [deriveKeyRef(d.provider), ...?d.nativeAuth?.env]
              : [ref],
        );
      }
      final checks = <String, CredentialInfo>{};
      String? credentialError;
      final list = refs.toList();
      for (var i = 0; i < list.length; i += 64) {
        try {
          checks.addAll(
            await remotes.credentials.describe(
              list.sublist(i, i + 64 > list.length ? list.length : i + 64),
            ),
          );
        } on Object catch (error) {
          credentialError = settingsError(error);
          break;
        }
        if (!_owns(generation)) return;
      }
      if (!_owns(generation)) return;
      final rows = <ModelProviderRow>[];
      for (final entry in entries) {
        final d = entry.directory;
        final namespace = namespaces[d.settingsNs];
        final account = d.provider == 'deepseek-account';
        if (account && !accountAvailable) continue;
        final ref = account ? null : _keyRef(namespace, d.settingsPath);
        rows.add(
          ModelProviderRow(
            entry: entry,
            configured:
                namespace != null &&
                (d.settingsPath.isEmpty ||
                    SettingsSchema.getPath(namespace.value, d.settingsPath) !=
                        null),
            removable:
                namespace != null &&
                d.settingsPath.isNotEmpty &&
                SettingsSchema.hasPath(namespace.user, d.settingsPath) &&
                !SettingsSchema.hasPath(namespace.base, d.settingsPath),
            apiKeyEnv: ref,
            credential: checks[ref],
            derivedCredential: ref == null
                ? checks[deriveKeyRef(d.provider)]
                : null,
            accountAvailable: account && accountAvailable,
            credentialChecks: credentialError != null
                ? null
                : {
                    for (final key
                        in ref == null
                            ? d.nativeAuth?.env ?? <String>[]
                            : [ref])
                      if (checks[key] != null) key: checks[key]!,
                  },
          ),
        );
      }
      state.set(
        ModelsSettingsSnapshot(
          status: ModelsSettingsStatus.ready,
          writable: view.writable,
          credentialError: credentialError,
          rows: List.unmodifiable(rows),
          namespaces: Map.unmodifiable(namespaces),
        ),
      );
    } on Object catch (error) {
      if (_owns(generation)) _fail(error);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    for (final c in _pending) {
      c.complete();
    }
    _pending.clear();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await state.dispose();
  }
}

String? _keyRef(SettingsNamespaceView? view, List<String> path) {
  final ref = SettingsSchema.getPath(view?.value, [...path, 'apiKeyEnv']);
  return ref is String && ref.isNotEmpty ? ref : null;
}

String settingsError(Object error) =>
    error is RemoteException ? error.message : '$error';

/// Edits only fields observed by the editor, preserving unknown stored fields.
List<SettingsPathOpView> providerPathOps(
  List<String> base,
  Object? beforeValue,
  Map<String, Object?> after,
) {
  final before = beforeValue is Map ? beforeValue : const <String, Object?>{};
  return [
    for (final entry in after.entries)
      if (!before.containsKey(entry.key) ||
          jsonEncode(before[entry.key]) != jsonEncode(entry.value))
        SettingsPathOpViewSet(path: [...base, entry.key], value: entry.value),
    for (final key in before.keys.cast<String>())
      if (!after.containsKey(key))
        SettingsPathOpViewUnset(path: [...base, key]),
  ];
}

/// One opened provider draft. A successful profile write advances the baseline
/// immediately; a subsequent credential failure retries only that write.
class ProviderSettingsDraft {
  ProviderSettingsDraft({
    required this.remotes,
    required this.mirror,
    required this.namespace,
    required this.provider,
    required List<String> path,
    this.creating = false,
    this.declared = false,
  }) : _path = path,
       revision = namespace.revision,
       original = creating
           ? {}
           : _mapCopy(SettingsSchema.getPath(namespace.user, path)),
       draft = creating
           ? {}
           : _mapCopy(SettingsSchema.getPath(namespace.user, path)),
       _ownerGeneration = remotes.currentGeneration();
  final HostRemotes remotes;
  final SettingsDescribeMirror mirror;
  final ConnectionGeneration? _ownerGeneration;
  bool get ownsConnection =>
      !_disposed && identical(_ownerGeneration, remotes.currentGeneration());
  final SettingsNamespaceView namespace;
  String provider;
  final List<String> _path;
  List<String> get path => creating ? ['providers', provider] : _path;
  final bool creating;
  final bool declared;
  int revision;
  Map<String, Object?> original;
  Map<String, Object?> draft;
  String keyDraft = '';
  String? error;
  bool busy = false;
  bool discovering = false;
  bool profileCommitted = false;
  bool _disposed = false;
  int _discovery = 0;

  Object? get effective => SettingsSchema.getPath(namespace.value, path);
  String get keyRef {
    final value = SettingsSchema.getPath(effective, ['apiKeyEnv']);
    return value is String && value.isNotEmpty ? value : deriveKeyRef(provider);
  }

  Object? field(String key) => draft.containsKey(key)
      ? draft[key]
      : SettingsSchema.getPath(effective, [key]);
  List<Map<String, Object?>> get models => modelDrafts(
    draft.containsKey('models')
        ? draft['models']
        : SettingsSchema.getPath(namespace.base, [...path, 'models']) ??
              SettingsSchema.rehydrate(namespace.schema)
                  .nodeAtPath([...path, 'models'])
                  ?.defaultValue,
  );

  void setField(String key, Object? value) {
    if (busy || creating && profileCommitted || _disposed) return;
    if (value == null || value is String && _modelTrim(value).isEmpty) {
      draft.remove(key);
    } else {
      draft[key] = value;
    }
    _discovery++;
  }

  String? validate() {
    final keyError = apiKeyFailure(keyDraft);
    if (keyError != null) return keyError;
    final failure =
        validateProviderModels(draft['models']) ??
        (declared ? validateModelReasoning(draft['models']) : null);
    if (failure != null) return '${failure.index + 1}:${failure.key}';
    if (creating) {
      if (!RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$').hasMatch(provider)) {
        return 'customRouteInvalid';
      }
      final baseURL = draft['baseURL'];
      final uri = baseURL is String ? Uri.tryParse(_modelTrim(baseURL)) : null;
      if (uri == null ||
          !const ['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        return 'customBaseUrlInvalid';
      }
      if (!providerProtocols(namespace).contains(draft['api'])) {
        return 'customApiUnset';
      }
      if (modelDrafts(draft['models']).isEmpty) return 'customNeedsModels';
    }
    return null;
  }

  Future<bool> save({bool writable = true}) async {
    if (!ownsConnection || busy || discovering || !writable) return false;
    final validation = validate();
    if (validation != null) {
      error = validation;
      return false;
    }
    busy = true;
    error = null;
    final key = _modelTrim(keyDraft);
    try {
      final next = _mapCopy(draft);
      final named = SettingsSchema.getPath(effective, ['apiKeyEnv']);
      if (namespace.ns == 'llm-pi-ai' &&
          next['apiKeyEnv'] == null &&
          named == null &&
          key.isNotEmpty) {
        next['apiKeyEnv'] = keyRef;
      }
      final materializesNative =
          namespace.ns == 'llm-pi-ai' &&
          effective == null &&
          original.isEmpty &&
          next.isEmpty;
      final ops = creating && !profileCommitted || materializesNative
          ? <SettingsPathOpView>[SettingsPathOpViewSet(path: path, value: next)]
          : providerPathOps(path, original, next);
      if (ops.isNotEmpty && !(creating && profileCommitted)) {
        final answer = await remotes.settings.mutate(
          namespace.ns,
          ops,
          revision,
        );
        // Even when the UI was closed, record that the Host accepted the write.
        original = _mapCopy(SettingsSchema.getPath(answer.user, path));
        revision = answer.revision;
        draft = next;
        profileCommitted = true;
        if (!ownsConnection) return false;
        mirror.acceptView(answer);
      }
      if (!ownsConnection) return false;
      if (key.isNotEmpty) await remotes.credentials.set(keyRef, key);
      keyDraft = '';
      return true;
    } on Object catch (failure) {
      if (!_disposed) {
        error =
            failure is RemoteException && failure.code == 'settings/conflict'
            ? 'conflict'
            : settingsError(failure)
                  .replaceAll(key.isEmpty ? '\u0000' : key, '[redacted]');
      }
      return false;
    } finally {
      busy = false;
    }
  }

  /// Discovery never saves the key or the draft. Stale edited responses and
  /// responses after disposal cannot replace the model list on screen.
  Future<List<LlmDiscoveredModel>?> discover() async {
    if (!ownsConnection ||
        busy ||
        discovering ||
        apiKeyFailure(keyDraft) != null) {
      return null;
    }
    final generation = ++_discovery;
    discovering = true;
    error = null;
    final key = _modelTrim(keyDraft);
    try {
      final models = await remotes.llm.discoverModels(
        namespace.ns,
        LlmModelDiscoveryRequest(
          provider: creating ? null : provider,
          api: field('api') is String ? field('api') as String : null,
          baseURL: field('baseURL') is String
              ? field('baseURL') as String
              : null,
          apiKey: key.isEmpty ? null : key,
        ),
      );
      return _disposed || generation != _discovery ? null : models;
    } on Object catch (failure) {
      if (!_disposed && generation == _discovery) {
        error = settingsError(failure)
            .replaceAll(key.isEmpty ? '\u0000' : key, '[redacted]');
      }
      return null;
    } finally {
      discovering = false;
    }
  }

  void dispose() {
    _disposed = true;
    _discovery++;
    keyDraft = '';
  }
}

Map<String, Object?> _mapCopy(Object? value) => value is Map
    ? Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map)
    : {};

String _modelTrim(String value) => value.replaceAll(
  RegExp(
    r'^[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+|[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+$',
  ),
  '',
);
