import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';

/// Why [HostBackend.connect] failed, in terms the pairing screen explains.
enum ConnectFailure {
  /// The host refused the launch token.
  rejected,

  /// Nothing answered.
  unreachable,

  /// The TLS handshake was refused by the trust policy ([ConnectException.refusal]).
  certificate,
}

class ConnectException implements Exception {
  const ConnectException(this.failure, [this.detail, this.refusal]);
  final ConnectFailure failure;
  final String? detail;
  final CertificateRefusal? refusal;
  @override
  String toString() =>
      'ConnectException($failure${detail == null ? '' : ': $detail'})';
}

/// What the app needs from a host connection. [LiveBackend] is the real one;
/// widget tests inject a fake. The launch token passes through [connect] and
/// is never logged by the app.
abstract interface class HostBackend {
  /// Live connection status of the current host: state, retry number and next
  /// retry time (for the connection indicator).
  Stream<ConnectionStatus> get statuses;

  /// Certificate trust of https hosts: probing, the pins the user confirmed.
  HostTrust get trust;

  /// Retry now instead of waiting out the backoff (dsh's "reconnect now").
  void reconnectNow();

  /// Streams a file to the host's upload route (`session/uploadFileBinary`).
  FileUploadClient get uploader;

  /// The host's workspace file service (`workspaceFiles`).
  WorkspaceFilesRemote get files;

  /// Unary calls through whatever connection is live now (a re-pair replaces
  /// the connection; the caller handed out earlier keeps working). Calls with
  /// no live generation fail with [NotConnected].
  RemoteCaller get remoteCaller;

  /// Pair with [origin] using [token] and return the transport once the first
  /// generation is up. Calling again re-pairs (after a host restart) and
  /// reuses the connection when the origin is unchanged.
  Future<SessionTransport> connect(Uri origin, String token);

  /// Answer a pending waterfall on the live generation.
  Future<void> answer(WaterfallEvent event, WaterfallOutcome outcome);

  /// Stop the connection and forget the host.
  Future<void> disconnect();

  Future<void> dispose();
}

class LiveBackend implements HostBackend {
  LiveBackend({
    this.connectTimeout = const Duration(seconds: 12),
    HostTrust? trust,
  }) : trust = trust ?? HostTrust();

  final Duration connectTimeout;
  @override
  final HostTrust trust;
  DshConnection? _connection;
  DshSessionTransport? _transport;
  final StreamController<ConnectionStatus> _statuses =
      StreamController<ConnectionStatus>.broadcast();
  StreamSubscription<ConnectionStatus>? _stateSub;

  @override
  Stream<ConnectionStatus> get statuses => _statuses.stream;

  @override
  void reconnectNow() => _connection?.reconnectNow();

  @override
  late final FileUploadClient uploader = HttpFileUploadClient(
    credential: () => _connection?.generation?.credential,
    clientFor: trust.clientFor,
  );

  @override
  late final WorkspaceFilesRemote files = _LiveFiles(() => _connection);

  @override
  late final RemoteCaller remoteCaller = _LiveCaller(() => _connection);

  /// Unary calls through the live generation (used by tools that need host
  /// methods the app itself does not expose yet, such as the live test).
  RemoteCaller? get caller => _connection?.caller;

  @override
  Future<SessionTransport> connect(Uri origin, String token) async {
    final existing = _connection;
    final reuse = existing != null && existing.origin == origin;
    if (!reuse) {
      await _teardown();
      final connection = DshConnection(origin: origin, trust: trust);
      _connection = connection;
      _stateSub = connection.statuses.listen(_statuses.add);
      _transport = DshSessionTransport(connection);
    }
    final connection = _connection!;
    connection.start(token);
    try {
      await Future.any<Object?>([
        connection.untilConnected(timeout: connectTimeout),
        connection
            .untilState(
              (s) =>
                  s == ConnectionState.needsPairing ||
                  s == ConnectionState.certificateRefused,
              timeout: connectTimeout,
            )
            .then((state) {
              if (state == ConnectionState.certificateRefused) {
                throw ConnectException(
                  ConnectFailure.certificate,
                  null,
                  connection.status.refusal,
                );
              }
              throw const ConnectException(ConnectFailure.rejected);
            }),
      ]);
    } on ConnectException {
      rethrow;
    } on TimeoutException {
      final detail = describeTransportError(connection.lastError);
      // A first connection that never came up is dropped. An existing one
      // (a re-pair after a restart) keeps retrying in the background with the
      // new token: the sessions it serves are still on screen.
      if (!reuse) await _teardown();
      throw ConnectException(
        ConnectFailure.unreachable,
        detail.isEmpty ? null : detail,
      );
    }
    return _transport!;
  }

  Future<void> _teardown() async {
    await _stateSub?.cancel();
    _stateSub = null;
    await _connection?.stop();
    _connection = null;
    _transport = null;
  }

  @override
  Future<void> answer(WaterfallEvent event, WaterfallOutcome outcome) {
    final c = _connection;
    if (c == null) throw NotConnected();
    return c.answer(event, outcome);
  }

  @override
  Future<void> disconnect() => _teardown();

  @override
  Future<void> dispose() async {
    await _teardown();
    await _statuses.close();
    await trust.dispose();
  }
}

/// The workspace file service of whatever connection is live now (a re-pair
/// replaces the connection; the services handed out earlier keep working).
class _LiveFiles implements WorkspaceFilesRemote {
  _LiveFiles(this._connection);

  final DshConnection? Function() _connection;

  WorkspaceFilesRemote get _live {
    final c = _connection();
    if (c == null) throw NotConnected();
    return DshWorkspaceFiles(c);
  }

  @override
  Future<WorkspaceFileStat> stat(String sessionId, String path) =>
      _live.stat(sessionId, path);

  @override
  Future<WorkspaceFileText> read(
    String sessionId,
    String path, {
    int? offset,
    int? limit,
  }) => _live.read(sessionId, path, offset: offset, limit: limit);

  @override
  Future<WorkspaceFileBytes> readBytes(
    String sessionId,
    String path, {
    ByteRange? range,
    String? baseFile,
  }) => _live.readBytes(sessionId, path, range: range, baseFile: baseFile);

  @override
  Future<WorkspaceDirectoryListing> list(String sessionId, String path) =>
      _live.list(sessionId, path);

  @override
  Stream<WorkspaceWatchEvent> changes(String sessionId, String path) =>
      _live.changes(sessionId, path);
}

/// [RemoteCaller] over whichever [DshConnection] is current.
class _LiveCaller implements RemoteCaller {
  _LiveCaller(this._connection);

  final DshConnection? Function() _connection;

  @override
  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  ) {
    final c = _connection();
    if (c == null) throw NotConnected();
    return c.caller.call(namespace, method, args);
  }
}
