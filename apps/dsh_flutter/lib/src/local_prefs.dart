import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart' show PinStore;
import 'package:dsh_models/dsh_models.dart'
    show TerminalCloseRequest, TerminalPrefs;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dsh_feature_sidebar_right/dsh_feature_sidebar_right.dart'
    show SidebarPersistence;

/// What the app keeps on the device itself, apart from the host's settings
/// document: the interface language and the theme last seen (so the app draws
/// the right palette before the host answers, and on the pairing screen), and
/// whether to notify.
abstract interface class LocalPrefs {
  /// `en` or `zh`, or null to follow the device.
  String? get locale;
  Future<void> setLocale(String? locale);

  /// Whether to post a notification when a session needs the user while the
  /// app is in the background. On by default.
  bool get notificationsEnabled;
  Future<void> setNotificationsEnabled(bool enabled);

  /// The last durable `ui-theme` section the host reported.
  Map<String, Object?>? get themeCache;
  Future<void> setThemeCache(Map<String, Object?> section);

  /// Certificates the user confirmed: `host:port` to SHA-256 fingerprint.
  /// Fingerprints are public, so they are plain preferences.
  Map<String, String> get certificatePins;
  Future<void> setCertificatePins(Map<String, String> pins);

  /// The shell last chosen for a new terminal (dsh keeps it in `localStorage`).
  String? get terminalShell;
  Future<void> setTerminalShell(String path);

  /// The manual plugin installation registry choice.
  String? get pluginInstallRegistry;
  Future<void> setPluginInstallRegistry(String json);

  String? get sidebarLayouts;
  Future<void> setSidebarLayouts(String json);

  /// The workspace browser's viewing state as JSON (dsh's `dsh.workspace.view`).
  String? get workspaceView;
  Future<void> setWorkspaceView(String json);

  /// The application last chosen to open a workspace in (desktop, local host;
  /// dsh keeps it in `localStorage`).
  String? get openInAppChoice;
  Future<void> setOpenInAppChoice(String id);

  /// Terminal close requests the host has not confirmed: `{sessionId, id,
  /// title}` each, retried at the next start.
  List<Map<String, Object?>> get terminalCloses;
  Future<void> setTerminalCloses(List<Map<String, Object?>> requests);
}

/// Keeps nothing past the process; tests and platforms without storage.
class MemoryLocalPrefs implements LocalPrefs {
  MemoryLocalPrefs({
    this.locale,
    this.notificationsEnabled = true,
    this.themeCache,
    Map<String, String>? certificatePins,
    this.terminalShell,
    this.openInAppChoice,
    this.workspaceView,
    this.pluginInstallRegistry,
    this.sidebarLayouts,
  }) : certificatePins = {...?certificatePins};

  @override
  String? locale;
  @override
  bool notificationsEnabled;
  @override
  Map<String, Object?>? themeCache;
  @override
  Map<String, String> certificatePins;
  @override
  String? terminalShell;
  @override
  String? openInAppChoice;
  @override
  String? workspaceView;
  @override
  String? sidebarLayouts;
  @override
  Future<void> setSidebarLayouts(String json) async => sidebarLayouts = json;
  @override
  String? pluginInstallRegistry;
  @override
  Future<void> setPluginInstallRegistry(String json) async =>
      pluginInstallRegistry = json;
  @override
  List<Map<String, Object?>> terminalCloses = [];

  @override
  Future<void> setCertificatePins(Map<String, String> pins) async =>
      certificatePins = {...pins};

  @override
  Future<void> setTerminalShell(String path) async => terminalShell = path;

  @override
  Future<void> setOpenInAppChoice(String id) async => openInAppChoice = id;

  @override
  Future<void> setWorkspaceView(String json) async => workspaceView = json;

  @override
  Future<void> setTerminalCloses(List<Map<String, Object?>> requests) async =>
      terminalCloses = [...requests];

  @override
  Future<void> setLocale(String? value) async => locale = value;
  @override
  Future<void> setNotificationsEnabled(bool value) async =>
      notificationsEnabled = value;
  @override
  Future<void> setThemeCache(Map<String, Object?> section) async =>
      themeCache = section;
}

/// [LocalPrefs] over the platform's key-value store.
class SharedLocalPrefs implements LocalPrefs {
  SharedLocalPrefs._(this._prefs);

  static Future<SharedLocalPrefs> load() async =>
      SharedLocalPrefs._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _locale = 'whalee.locale';
  static const _notifications = 'whalee.notifications';
  static const _theme = 'whalee.themeCache';
  static const _pins = 'whalee.certificatePins';
  static const _terminalShell = 'whalee.terminalShell';
  static const _terminalCloses = 'whalee.terminalCloses';
  static const _openInApp = 'whalee.openInAppChoice';
  static const _workspaceView = 'whalee.workspaceView';
  static const _sidebarLayouts = 'whalee.sidebarLayouts.v1';
  @override
  String? get sidebarLayouts => _prefs.getString(_sidebarLayouts);
  @override
  Future<void> setSidebarLayouts(String json) async {
    await _prefs.setString(_sidebarLayouts, json);
  }

  static const _pluginRegistry = 'whalee.pluginInstallRegistry';
  @override
  String? get pluginInstallRegistry => _prefs.getString(_pluginRegistry);
  @override
  Future<void> setPluginInstallRegistry(String json) async {
    await _prefs.setString(_pluginRegistry, json);
  }

  @override
  String? get locale => _prefs.getString(_locale);

  @override
  Future<void> setLocale(String? locale) async {
    if (locale == null) {
      await _prefs.remove(_locale);
    } else {
      await _prefs.setString(_locale, locale);
    }
  }

  @override
  bool get notificationsEnabled => _prefs.getBool(_notifications) ?? true;

  @override
  Future<void> setNotificationsEnabled(bool enabled) async {
    await _prefs.setBool(_notifications, enabled);
  }

  @override
  Map<String, Object?>? get themeCache {
    final raw = _prefs.getString(_theme);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> setThemeCache(Map<String, Object?> section) async {
    await _prefs.setString(_theme, jsonEncode(section));
  }

  @override
  Map<String, String> get certificatePins {
    final raw = _prefs.getString(_pins);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? {
              for (final e in decoded.entries)
                if (e.value is String) '${e.key}': e.value as String,
            }
          : {};
    } on FormatException {
      return {};
    }
  }

  @override
  Future<void> setCertificatePins(Map<String, String> pins) async {
    await _prefs.setString(_pins, jsonEncode(pins));
  }

  @override
  String? get terminalShell => _prefs.getString(_terminalShell);

  @override
  String? get workspaceView => _prefs.getString(_workspaceView);

  @override
  Future<void> setWorkspaceView(String json) async {
    await _prefs.setString(_workspaceView, json);
  }

  @override
  String? get openInAppChoice => _prefs.getString(_openInApp);

  @override
  Future<void> setOpenInAppChoice(String id) async {
    await _prefs.setString(_openInApp, id);
  }

  @override
  Future<void> setTerminalShell(String path) async {
    await _prefs.setString(_terminalShell, path);
  }

  @override
  List<Map<String, Object?>> get terminalCloses {
    final raw = _prefs.getString(_terminalCloses);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List
          ? [
              for (final e in decoded)
                if (e is Map) e.cast<String, Object?>(),
            ]
          : [];
    } on FormatException {
      return [];
    }
  }

  @override
  Future<void> setTerminalCloses(List<Map<String, Object?>> requests) async {
    await _prefs.setString(_terminalCloses, jsonEncode(requests));
  }
}

/// [TerminalPrefs] over [LocalPrefs]: the shell choice and the close requests
/// the host has not confirmed survive restarts.
class PrefsTerminalPrefs implements TerminalPrefs {
  PrefsTerminalPrefs(this._prefs)
    : _closes = {
        for (final json in _prefs.terminalCloses)
          if (TerminalCloseRequest.tryParse(json) case final request?)
            request.id: request,
      };

  final LocalPrefs _prefs;
  final Map<String, TerminalCloseRequest> _closes;

  @override
  String? get preferredShell => _prefs.terminalShell;

  @override
  void rememberShell(String path) => unawaited(_prefs.setTerminalShell(path));

  @override
  List<TerminalCloseRequest> get pendingCloses => _closes.values.toList();

  @override
  void saveClose(TerminalCloseRequest request) {
    _closes[request.id] = request;
    _write();
  }

  @override
  void removeClose(String terminalId) {
    if (_closes.remove(terminalId) != null) _write();
  }

  void _write() => unawaited(
    _prefs.setTerminalCloses([for (final r in _closes.values) r.toJson()]),
  );
}

/// [PinStore] over [LocalPrefs]: the pins survive restarts.
class PrefsPinStore implements PinStore {
  PrefsPinStore(this._prefs) : _pins = {..._prefs.certificatePins};

  final LocalPrefs _prefs;
  final Map<String, String> _pins;

  @override
  String? pinFor(String authority) => _pins[authority];

  @override
  Future<void> pin(String authority, String fingerprint) async {
    _pins[authority] = fingerprint;
    await _prefs.setCertificatePins(_pins);
  }

  @override
  Future<void> forget(String authority) async {
    _pins.remove(authority);
    await _prefs.setCertificatePins(_pins);
  }
}

/// Bounded device-local sidebar layouts. Captured Host scopes prevent a late
/// write from a retired connection from being assigned to its replacement.
class PrefsSidebarPersistence implements SidebarPersistence {
  PrefsSidebarPersistence(this.prefs) {
    final raw = prefs.sidebarLayouts;
    if (raw != null && raw.length <= 1024 * 1024) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) {
          for (final e in decoded.entries) {
            if (e.value is String && (e.value as String).length <= 512 * 1024) {
              _values[e.key] = e.value as String;
              if (_values.length > 64) {
                _values.remove(_values.keys.first);
              }
            }
          }
        }
      } on FormatException {
        /* Invalid device data starts a fresh layout. */
      }
    }
  }
  final LocalPrefs prefs;
  final _values = <String, String>{};
  Future<void> _saving = Future<void>.value();
  String _key(String scope, String sessionId) => jsonEncode([scope, sessionId]);
  @override
  String? read(String scope, String sessionId) =>
      _values[_key(scope, sessionId)];
  @override
  void write(String scope, String sessionId, String value) {
    if (value.length > 512 * 1024) return;
    final key = _key(scope, sessionId);
    _values.remove(key);
    _values[key] = value;
    while (_values.length > 64 || jsonEncode(_values).length > 1024 * 1024) {
      _values.remove(_values.keys.first);
    }
    final encoded = jsonEncode(_values);
    _saving = _saving
        .then((_) => prefs.setSidebarLayouts(encoded))
        .catchError((Object _) {});
  }

  Future<void> flush() => _saving;
}
