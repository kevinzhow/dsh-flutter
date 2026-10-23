import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A host the user paired with: its origin and the launch token (valid until
/// the host restarts).
class SavedHost {
  const SavedHost(this.origin, this.token);
  final String origin;
  final String token;
}

/// Where the paired host is remembered between runs.
abstract interface class ConnectionStore {
  Future<SavedHost?> load();
  Future<void> save(SavedHost host);
  Future<void> clear();
}

/// Keeps nothing; used by tests and platforms without secure storage.
class MemoryConnectionStore implements ConnectionStore {
  SavedHost? _host;
  @override
  Future<SavedHost?> load() async => _host;
  @override
  Future<void> save(SavedHost host) async => _host = host;
  @override
  Future<void> clear() async => _host = null;
}

/// The token is a credential, so it goes to the platform keystore (Android
/// Keystore, iOS/macOS Keychain, libsecret on Linux), never to plain files.
class SecureConnectionStore implements ConnectionStore {
  SecureConnectionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _originKey = 'host.origin';
  static const _tokenKey = 'host.token';
  final FlutterSecureStorage _storage;

  @override
  Future<SavedHost?> load() async {
    try {
      final origin = await _storage.read(key: _originKey);
      final token = await _storage.read(key: _tokenKey);
      if (origin == null || token == null) return null;
      return SavedHost(origin, token);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(SavedHost host) async {
    try {
      await _storage.write(key: _originKey, value: host.origin);
      await _storage.write(key: _tokenKey, value: host.token);
    } on Object {
      // Storing is a convenience; the app works without it.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _originKey);
      await _storage.delete(key: _tokenKey);
    } on Object {
      // Nothing was stored.
    }
  }
}
