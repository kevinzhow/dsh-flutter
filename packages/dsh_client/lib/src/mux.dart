import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ids.dart';
import 'pairing.dart';
import 'remote_caller.dart';

/// The physical socket under a logical stream was lost; the stream will not
/// continue. A new connection generation reopens it.
class CarrierLost extends RemoteException {
  CarrierLost([String why = 'mux socket closed'])
    : super('transport/carrier-lost', why);
}

/// One logical stream on a [MuxCarrier]: dsh frames `open`, `item`, `end`,
/// `cancel` (client to host) and `item`, `error`, `end` (host to client).
class MuxStream {
  MuxStream._(this._carrier, this.streamId, this.endpoint) {
    _controller = StreamController<Object?>(onCancel: cancel);
  }

  final MuxCarrier _carrier;
  final String streamId;
  final String endpoint;
  late final StreamController<Object?> _controller;
  bool _finished = false;

  /// Downlink items. Completes on host `end`; errors with [RemoteException]
  /// on host `error` or [CarrierLost].
  Stream<Object?> get items => _controller.stream;

  /// Uplink item (docs: `RemoteStream<Out, In>` uplink).
  void send(Object? value) =>
      _carrier._send({'type': 'item', 'streamId': streamId, 'value': value});

  /// Uplink half-close.
  void end() => _carrier._send({'type': 'end', 'streamId': streamId});

  /// Cancel the stream (sends `cancel` unless the host already ended it).
  Future<void> cancel() async {
    if (_finished) return;
    _finished = true;
    _carrier._streams.remove(streamId);
    _carrier._send({'type': 'cancel', 'streamId': streamId}, ifOpen: true);
    if (!_controller.isClosed) unawaited(_controller.close());
  }

  void _item(Object? v) {
    if (!_finished) _controller.add(v);
  }

  void _fail(Object error) {
    if (_finished) return;
    _finished = true;
    _carrier._streams.remove(streamId);
    _controller.addError(error);
    unawaited(_controller.close());
  }

  void _done() {
    if (_finished) return;
    _finished = true;
    _carrier._streams.remove(streamId);
    unawaited(_controller.close());
  }
}

/// One physical `/api/remote.mux` WebSocket. It belongs to one API Peer: when
/// it closes, every logical stream ends with [CarrierLost] and the host drops
/// the Peer (the cookie is then refused), so a replacement needs `/connect`.
class MuxCarrier {
  MuxCarrier._(this._socket) {
    _sub = _socket.listen(
      _onMessage,
      onDone: () => _lost(CarrierLost('socket closed (${_socket.closeCode})')),
      onError: (Object e) => _lost(CarrierLost('socket error: $e')),
      cancelOnError: true,
    );
  }

  /// Connect with the paired cookie. A host refusal (401/409) surfaces as
  /// [RemoteException] `transport/upgrade-refused`.
  ///
  /// [client] carries the certificate trust policy for `wss` (see
  /// `HostTrust.clientFor`).
  ///
  /// The socket pings the host every [pingInterval] and closes when no pong
  /// came back by the next ping, so a connection that died silently (a phone
  /// that changed networks) ends within about two intervals instead of
  /// whenever the operating system gives up on it.
  static Future<MuxCarrier> connect(
    PairedCredential credential, {
    Duration timeout = const Duration(seconds: 15),
    HttpClient? client,
    Duration pingInterval = const Duration(seconds: 6),
  }) async {
    try {
      final ws = await WebSocket.connect(
        credential.muxUri.toString(),
        headers: {HttpHeaders.cookieHeader: credential.cookieHeader},
        customClient: client,
      ).timeout(timeout);
      ws.pingInterval = pingInterval;
      return MuxCarrier._(ws);
    } on WebSocketException catch (e) {
      throw RemoteException('transport/upgrade-refused', e.message);
    }
  }

  final WebSocket _socket;
  late final StreamSubscription<Object?> _sub;
  final Map<String, MuxStream> _streams = {};
  final Completer<CarrierLost> _closed = Completer<CarrierLost>();
  bool _isClosed = false;

  /// Completes when the socket is gone (for any reason).
  Future<CarrierLost> get closed => _closed.future;
  bool get isOpen => !_isClosed;

  MuxStream open(String endpoint, Object? payload) {
    if (_isClosed) throw CarrierLost('socket already closed');
    final stream = MuxStream._(this, randomUuid(), endpoint);
    _streams[stream.streamId] = stream;
    _send({
      'type': 'open',
      'streamId': stream.streamId,
      'endpoint': endpoint,
      'payload': payload,
    });
    return stream;
  }

  void _send(Map<String, Object?> frame, {bool ifOpen = false}) {
    if (_isClosed) {
      if (ifOpen) return;
      throw CarrierLost('socket already closed');
    }
    _socket.add(jsonEncode(frame));
  }

  void _onMessage(Object? data) {
    if (data is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    final stream = _streams[decoded['streamId']];
    if (stream == null) return;
    switch (decoded['type']) {
      case 'item':
        stream._item(decoded['value']);
      case 'end':
        stream._done();
      case 'error':
        final e = decoded['error'];
        if (e is Map<String, Object?>) {
          final d = e['details'];
          stream._fail(
            RemoteException(
              '${e['code']}',
              '${e['message']}',
              d is Map<String, Object?> ? d : const {},
            ),
          );
        } else {
          stream._fail(RemoteException('transport/bad-frame', 'error frame'));
        }
    }
  }

  void _lost(CarrierLost why) {
    if (_isClosed) return;
    _isClosed = true;
    for (final s in _streams.values.toList()) {
      s._fail(why);
    }
    _streams.clear();
    if (!_closed.isCompleted) _closed.complete(why);
  }

  Future<void> close() async {
    _lost(CarrierLost('closed by client'));
    await _sub.cancel();
    await _socket.close(1000, 'client closing');
  }
}
