import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'binary_response.dart';
import 'ids.dart';
import 'pairing.dart';
import 'remote_caller.dart';

/// The host answered 401: the cookie's Peer is gone (socket closed or host
/// restarted) or the cookie expired. The caller must pair again.
class UnauthorizedException extends RemoteException {
  UnauthorizedException(String where)
    : super('transport/unauthorized', 'HTTP 401 for $where');
}

/// `POST /api/<namespace>/<method>` with dsh's `client-request` envelope.
class HttpRemoteCaller implements RemoteCaller {
  HttpRemoteCaller(this.credential, {HttpClient? httpClient})
    : _http = httpClient ?? HttpClient();

  final PairedCredential credential;
  final HttpClient _http;

  @override
  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  ) async {
    final rpcId = randomUuid();
    final uri = credential.origin.replace(path: '/api/$namespace/$method');
    final request = await _http.postUrl(uri);
    request.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json')
      ..set(HttpHeaders.cookieHeader, credential.cookieHeader);
    request.add(
      utf8.encode(
        jsonEncode({
          'type': 'client-request',
          'rpcId': rpcId,
          'method': '$namespace/$method',
          'payload': {'args': args},
        }),
      ),
    );
    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (response.statusCode == HttpStatus.unauthorized) {
      throw UnauthorizedException('$namespace/$method');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw RemoteException(
        'transport/http-${response.statusCode}',
        'transport failure for $namespace/$method: HTTP ${response.statusCode}',
      );
    }
    final mime = response.headers.contentType?.mimeType;
    final Object? decoded;
    if (mime == 'multipart/form-data') {
      // A binary result (docs: connection README, binary Remote transfer):
      // JSON metadata plus raw byte parts; `Uint8Array` fields come back as
      // [Uint8List] values inside `value`.
      decoded = decodeBinaryResponse(
        response.headers.value(HttpHeaders.contentTypeHeader) ?? '',
        bytes,
      );
    } else {
      decoded = jsonDecode(utf8.decode(bytes));
    }
    if (decoded is! Map<String, Object?> || decoded['rpcId'] != rpcId) {
      throw RemoteException(
        'transport/bad-envelope',
        'unexpected response envelope for $namespace/$method',
      );
    }
    final result = decoded['result'];
    if (result is! Map<String, Object?>) {
      throw RemoteException('transport/bad-envelope', 'missing result');
    }
    if (result['ok'] == true) return result['value'];
    final error = result['error'];
    if (error is Map<String, Object?>) {
      final details = error['details'];
      throw RemoteException(
        '${error['code']}',
        '${error['message']}',
        details is Map<String, Object?> ? details : const {},
      );
    }
    throw RemoteException('transport/bad-envelope', 'malformed error result');
  }

  void close() => _http.close(force: true);
}
