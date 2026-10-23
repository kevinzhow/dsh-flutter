import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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
}

/// Keeps nothing past the process; tests and platforms without storage.
class MemoryLocalPrefs implements LocalPrefs {
  MemoryLocalPrefs({
    this.locale,
    this.notificationsEnabled = true,
    this.themeCache,
  });

  @override
  String? locale;
  @override
  bool notificationsEnabled;
  @override
  Map<String, Object?>? themeCache;

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
}
