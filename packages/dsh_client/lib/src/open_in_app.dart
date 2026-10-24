import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'pairing.dart';
import 'remote_caller.dart';

/// What a client needs from the host's open-in-app routes (dsh
/// `host-open-in-app`): the installed application ids, one launch of an
/// application on a directory, and an application's icon. Every route sits
/// behind the host's trust fence, so each call carries the paired cookie.
abstract interface class OpenInAppClient {
  /// The catalog ids probed as installed on the host, in menu order. Empty when
  /// the host answers nothing usable (the control then shows no button).
  Future<List<String>> apps();

  /// Launch application [app] on the host directory [path]. Throws on any
  /// refusal or transport failure.
  Future<void> open(String app, String path);

  /// The PNG icon of [app], or null when the host has none.
  Future<Uint8List?> icon(String app);
}

/// `GET /open-in-app/apps`, `POST /open-in-app/open` and
/// `GET /open-in-app/icon/<id>` over the paired API cookie of the live
/// generation (dsh `OPEN_IN_APP_*_PATH`).
class HttpOpenInAppClient implements OpenInAppClient {
  HttpOpenInAppClient({
    required PairedCredential? Function() credential,
    HttpClient? httpClient,
    HttpClient Function(Uri origin)? clientFor,
  }) : _credential = credential,
       _clientFor = clientFor,
       _http = httpClient ?? HttpClient();

  final PairedCredential? Function() _credential;
  final HttpClient Function(Uri origin)? _clientFor;
  final HttpClient _http;

  static const String appsPath = '/open-in-app/apps';
  static const String openPath = '/open-in-app/open';
  static const String iconPrefixPath = '/open-in-app/icon';

  Future<HttpClientResponse> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final credential = _credential();
    if (credential == null) {
      throw RemoteException('connection/not-connected', 'no live generation');
    }
    final client = _clientFor?.call(credential.origin) ?? _http;
    final request = await client.openUrl(
      method,
      credential.origin.replace(path: path),
    );
    request.headers.set(HttpHeaders.cookieHeader, credential.cookieHeader);
    if (body != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode(body));
    }
    return request.close();
  }

  @override
  Future<List<String>> apps() async {
    try {
      final response = await _send('GET', appsPath);
      final text = await utf8.decodeStream(response);
      if (response.statusCode != HttpStatus.ok) return const [];
      final decoded = jsonDecode(text);
      final list = decoded is Map<String, Object?> ? decoded['apps'] : null;
      return list is List ? [...list.whereType<String>()] : const [];
    } on Object {
      // An unreachable host reads as no applications: no button, not a broken
      // one (dsh's controller does the same).
      return const [];
    }
  }

  @override
  Future<void> open(String app, String path) async {
    final response = await _send(
      'POST',
      openPath,
      body: {'app': app, 'path': path},
    );
    await response.drain<void>();
    if (response.statusCode != HttpStatus.ok) {
      throw RemoteException(
        'transport/http-${response.statusCode}',
        'open failed: HTTP ${response.statusCode}',
      );
    }
  }

  @override
  Future<Uint8List?> icon(String app) async {
    try {
      final response = await _send(
        'GET',
        '$iconPrefixPath/${Uri.encodeComponent(app)}',
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on Object {
      return null;
    }
  }

  void close() => _http.close(force: true);
}
