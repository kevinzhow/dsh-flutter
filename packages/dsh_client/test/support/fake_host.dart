import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A minimal in-process stand-in for a dsh host: `/connect` pairing with
/// per-socket Peers, unary `POST /api/<ns>/<method>`, and the
/// `/api/remote.mux` WebSocket with logical streams. Synthetic data only.
class FakeHost {
  FakeHost._(this._server, this.token, this.port);

  static Future<FakeHost> start({
    int port = 0,
    String token = 'launch-token-1',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final host = FakeHost._(server, token, server.port);
    host._listen();
    return host;
  }

  HttpServer _server;
  String token;
  final int port;
  Uri get origin => Uri.parse('http://127.0.0.1:$port');

  final Map<String, bool> _peers = {}; // peerId -> socket attached
  final Map<String, WebSocket> _sockets = {};
  final List<String> connectInteractions = [];
  int pairings = 0;

  /// `ns/method` -> handler returning the result `value` (or throwing
  /// [FakeRemoteError]).
  final Map<String, FutureOr<Object?> Function(Map<String, Object?> args)>
  unary = {};

  /// endpoint -> stream handler.
  final Map<String, void Function(FakeStream stream)> streams = {};

  /// Every `$events/result` args received.
  final List<Map<String, Object?>> eventResults = [];

  /// Open streams by endpoint, newest last.
  final Map<String, List<FakeStream>> openStreams = {};

  void _listen() {
    _server.listen((req) async {
      try {
        await _handle(req);
      } on Object {
        // ignore: the test asserts on outcomes
      }
    });
  }

  String? _peerOf(HttpRequest req) {
    final cookie = req.headers.value(HttpHeaders.cookieHeader);
    if (cookie == null) return null;
    for (final part in cookie.split(';')) {
      final p = part.trim();
      if (p.startsWith('dsh-fake=')) {
        final id = p.substring('dsh-fake='.length);
        return _peers.containsKey(id) ? id : null;
      }
    }
    return null;
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (path == '/connect') {
      final interactions = req.uri.queryParameters['interactions'] ?? 'none';
      if (req.uri.queryParameters['token'] != token) {
        req.response.statusCode = 401;
        await req.response.close();
        return;
      }
      connectInteractions.add(interactions);
      pairings++;
      final id = 'peer-$pairings';
      _peers[id] = false;
      req.response
        ..statusCode = 302
        ..headers.set(HttpHeaders.locationHeader, './api/remote.mux')
        ..headers.add(
          HttpHeaders.setCookieHeader,
          'dsh-fake=$id; Path=/; HttpOnly; SameSite=Strict',
        );
      await req.response.close();
      return;
    }
    final peer = _peerOf(req);
    if (peer == null) {
      req.response.statusCode = 401;
      await req.response.close();
      return;
    }
    if (path == '/api/remote.mux' &&
        WebSocketTransformer.isUpgradeRequest(req)) {
      if (_peers[peer]!) {
        req.response.statusCode = 409;
        await req.response.close();
        return;
      }
      _peers[peer] = true;
      final ws = await WebSocketTransformer.upgrade(req);
      _sockets[peer] = ws;
      ws.listen(
        (data) => _onFrame(
          peer,
          ws,
          jsonDecode(data as String) as Map<String, Object?>,
        ),
        onDone: () {
          _peers.remove(peer);
          _sockets.remove(peer);
        },
      );
      return;
    }
    if (req.method == 'POST' && path.startsWith('/api/')) {
      final body =
          jsonDecode(await utf8.decodeStream(req)) as Map<String, Object?>;
      final method = body['method'] as String;
      final args = ((body['payload'] as Map)['args'] as Map)
          .cast<String, Object?>();
      Map<String, Object?> result;
      if (method == r'$events/result') {
        eventResults.add(args);
        result = {'ok': true};
      } else {
        final handler = unary[method];
        if (handler == null) {
          result = {
            'ok': false,
            'error': {
              'code': 'gateway/not-found',
              'message': 'no $method',
              'details': {},
            },
          };
        } else {
          try {
            result = {'ok': true, 'value': await handler(args)};
          } on FakeRemoteError catch (e) {
            result = {
              'ok': false,
              'error': {'code': e.code, 'message': e.message, 'details': {}},
            };
          }
        }
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'type': 'server-response',
          'rpcId': body['rpcId'],
          'result': result,
        }),
      );
      await req.response.close();
      return;
    }
    req.response.statusCode = 404;
    await req.response.close();
  }

  void _onFrame(String peer, WebSocket ws, Map<String, Object?> frame) {
    final id = frame['streamId'] as String;
    switch (frame['type']) {
      case 'open':
        final endpoint = frame['endpoint'] as String;
        final stream = FakeStream._(ws, id, endpoint, frame['payload']);
        _streamsById['$peer/$id'] = stream;
        openStreams.putIfAbsent(endpoint, () => []).add(stream);
        if (endpoint == r'$events') {
          stream.item({
            'type': 'ready',
            'clientId': 'client-$peer',
            'host': {'home': '/home/test'},
          });
        }
        streams[endpoint]?.call(stream);
      case 'cancel':
        _streamsById.remove('$peer/$id')?.cancelled = true;
      case 'item':
        _streamsById['$peer/$id']?.uplink.add(frame['value']);
    }
  }

  final Map<String, FakeStream> _streamsById = {};

  /// Drop one peer's socket from the host side (network loss).
  Future<void> dropSockets() async {
    for (final ws in _sockets.values.toList()) {
      await ws.close(1001, 'test drop');
    }
  }

  /// Host restart: every peer dies and the launch token changes.
  Future<void> restart(String newToken) async {
    await _server.close(force: true);
    for (final ws in _sockets.values.toList()) {
      await ws.close(1001, 'restart');
    }
    _peers.clear();
    _sockets.clear();
    _streamsById.clear();
    openStreams.clear();
    token = newToken;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _listen();
  }

  Future<void> stop() async {
    await _server.close(force: true);
    for (final ws in _sockets.values.toList()) {
      await ws.close();
    }
  }
}

class FakeRemoteError implements Exception {
  FakeRemoteError(this.code, this.message);
  final String code;
  final String message;
}

class FakeStream {
  FakeStream._(this._ws, this.streamId, this.endpoint, this.payload);
  final WebSocket _ws;
  final String streamId;
  final String endpoint;
  final Object? payload;
  bool cancelled = false;
  final List<Object?> uplink = [];

  void item(Object? value) => _ws.add(
    jsonEncode({'type': 'item', 'streamId': streamId, 'value': value}),
  );
  void end() => _ws.add(jsonEncode({'type': 'end', 'streamId': streamId}));
  void error(String code, String message) => _ws.add(
    jsonEncode({
      'type': 'error',
      'streamId': streamId,
      'error': {
        'code': code,
        'message': message,
        'details': <String, Object?>{},
      },
    }),
  );
}
