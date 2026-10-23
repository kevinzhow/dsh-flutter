import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';

/// What the debug UI needs from a host connection. [LiveBackend] is the real
/// one; widget tests inject a fake. The launch token passes through [connect]
/// and is never stored or logged by the app.
abstract interface class DebugBackend {
  /// Short human-readable state (`idle`, `connecting`, `connected (generation 2)`,
  /// `needs pairing`, ...).
  Stream<String> get status;

  /// Pair with `http://host:port/?token=...` (or a bare origin plus [token])
  /// and return the transport once the first generation is up. A second call
  /// with a new token re-pairs (after a host restart).
  Future<SessionTransport> connect(String hostUrl, String token);

  /// Answer a pending waterfall on the live generation.
  Future<void> answer(WaterfallEvent event, WaterfallOutcome outcome);

  Future<void> dispose();
}

class LiveBackend implements DebugBackend {
  DshConnection? _connection;
  DshSessionTransport? _transport;
  final StreamController<String> _status = StreamController<String>.broadcast();
  StreamSubscription<ConnectionState>? _stateSub;

  @override
  Stream<String> get status => _status.stream;

  @override
  Future<SessionTransport> connect(String hostUrl, String token) async {
    var origin = Uri.parse(hostUrl.trim());
    var launchToken = token.trim();
    if (launchToken.isEmpty) {
      final parsed = parseLaunchUrl(hostUrl);
      origin = parsed.origin;
      launchToken = parsed.token;
    } else {
      origin = Uri(
        scheme: origin.scheme.isEmpty ? 'http' : origin.scheme,
        host: origin.host,
        port: origin.hasPort ? origin.port : null,
      );
    }
    final existing = _connection;
    if (existing != null && existing.origin == origin) {
      // Re-pair on the same host (restart): reuse the connection and models.
      existing.start(launchToken);
      await existing.untilConnected();
      return _transport!;
    }
    await existing?.stop();
    await _stateSub?.cancel();
    final connection = DshConnection(origin: origin);
    _connection = connection;
    _stateSub = connection.states.listen(
      (s) => _status.add(_describe(s, connection)),
    );
    _status.add('connecting');
    connection.start(launchToken);
    await connection.untilConnected();
    return _transport = DshSessionTransport(connection);
  }

  String _describe(ConnectionState s, DshConnection c) => switch (s) {
    ConnectionState.connected => 'connected (generation ${c.generation?.id})',
    ConnectionState.needsPairing =>
      'needs pairing: host refused the token (restarted?)',
    _ => s.name,
  };

  @override
  Future<void> answer(WaterfallEvent event, WaterfallOutcome outcome) =>
      _connection!.answer(event, outcome);

  @override
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _connection?.stop();
    await _status.close();
  }
}
