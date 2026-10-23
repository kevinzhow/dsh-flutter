import 'dart:async';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';

/// Why [HostBackend.connect] failed, in terms the pairing screen explains.
enum ConnectFailure { rejected, unreachable }

class ConnectException implements Exception {
  const ConnectException(this.failure, [this.detail]);
  final ConnectFailure failure;
  final String? detail;
  @override
  String toString() =>
      'ConnectException($failure${detail == null ? '' : ': $detail'})';
}

/// What the app needs from a host connection. [LiveBackend] is the real one;
/// widget tests inject a fake. The launch token passes through [connect] and
/// is never logged by the app.
abstract interface class HostBackend {
  /// Live connection state of the current host (for the reconnect banner).
  Stream<ConnectionState> get states;

  /// Streams a file to the host's upload route (`session/uploadFileBinary`).
  FileUploadClient get uploader;

  /// The host's workspace file service (`workspaceFiles`).
  WorkspaceFilesRemote get files;

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
  LiveBackend({this.connectTimeout = const Duration(seconds: 12)});

  final Duration connectTimeout;
  DshConnection? _connection;
  DshSessionTransport? _transport;
  final StreamController<ConnectionState> _states =
      StreamController<ConnectionState>.broadcast();
  StreamSubscription<ConnectionState>? _stateSub;

  @override
  Stream<ConnectionState> get states => _states.stream;

  @override
  late final FileUploadClient uploader = HttpFileUploadClient(
    credential: () => _connection?.generation?.credential,
  );

  @override
  late final WorkspaceFilesRemote files = _LiveFiles(() => _connection);

  /// Unary calls through the live generation (used by tools that need host
  /// methods the app itself does not expose yet, such as the live test).
  RemoteCaller? get caller => _connection?.caller;

  @override
  Future<SessionTransport> connect(Uri origin, String token) async {
    final existing = _connection;
    final reuse = existing != null && existing.origin == origin;
    if (!reuse) {
      await _teardown();
      final connection = DshConnection(origin: origin);
      _connection = connection;
      _stateSub = connection.states.listen(_states.add);
      _transport = DshSessionTransport(connection);
    }
    final connection = _connection!;
    connection.start(token);
    try {
      await Future.any<Object?>([
        connection.untilConnected(timeout: connectTimeout),
        connection
            .untilState(
              (s) => s == ConnectionState.needsPairing,
              timeout: connectTimeout,
            )
            .then((_) => throw const ConnectException(ConnectFailure.rejected)),
      ]);
    } on ConnectException {
      rethrow;
    } on TimeoutException {
      final error = connection.lastError;
      await _teardown();
      throw ConnectException(
        ConnectFailure.unreachable,
        error is SocketException ? error.message : error?.toString(),
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
    await _states.close();
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
