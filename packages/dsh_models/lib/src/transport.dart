import 'package:dsh_client/dsh_client.dart';

/// Everything the models need from a host. The real implementation is
/// [DshSessionTransport] (over `dsh_client`); tests inject a fake that replays
/// recorded frames. Mirrors dsh's `SessionRemotes` seam.
abstract interface class SessionTransport {
  /// `session/list` -> `{items: [SessionSummary...]}`.
  Future<Map<String, Object?>> list();

  /// `session/create` -> `{sessionId, agentPreset?}`.
  Future<Map<String, Object?>> create(Map<String, Object?> request);

  /// `session/prompt` -> `{accepted: true}`.
  Future<void> prompt(Map<String, Object?> request);

  /// `session/cancel`.
  Future<void> cancel(String sessionId);

  /// `session/page`.
  Future<Map<String, Object?>> page(Map<String, Object?> request);

  /// `session/follow` logical stream (reopens per connection generation;
  /// [request] is evaluated at every open).
  Stream<GenerationFrame> follow(Map<String, Object?> Function() request);

  /// `session/control` logical stream (baseline + projection frames).
  Stream<GenerationFrame> control();

  /// Forwarded host events (`api-session/*`, `approval/request`, ...).
  Stream<HostEvent> get hostEvents;

  /// Publishes a generation when connected and null when it is invalidated.
  Stream<ConnectionGeneration?> get generations;

  /// The live generation, if any.
  ConnectionGeneration? get generation;
}

/// [SessionTransport] over a [DshConnection]; argument names are the Host
/// parameter names verbatim (`_request` for `session/list`).
class DshSessionTransport implements SessionTransport {
  DshSessionTransport(this.connection);

  final DshConnection connection;

  Future<Map<String, Object?>> _map(
    String method,
    Map<String, Object?> args,
  ) async {
    final v = await connection.caller.call('session', method, args);
    return v is Map<String, Object?> ? v : <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> list() =>
      _map('list', {'_request': <String, Object?>{}});

  @override
  Future<Map<String, Object?>> create(Map<String, Object?> request) =>
      _map('create', {'request': request});

  @override
  Future<void> prompt(Map<String, Object?> request) async {
    await _map('prompt', {'request': request});
  }

  @override
  Future<void> cancel(String sessionId) async {
    await _map('cancel', {
      'request': {'sessionId': sessionId},
    });
  }

  @override
  Future<Map<String, Object?>> page(Map<String, Object?> request) =>
      _map('page', {'request': request});

  @override
  Stream<GenerationFrame> follow(Map<String, Object?> Function() request) =>
      connection.openStream('session/follow', () => {'request': request()});

  @override
  Stream<GenerationFrame> control() =>
      connection.openStream('session/control', () => <String, Object?>{});

  @override
  Stream<HostEvent> get hostEvents => connection.hostEvents;

  @override
  Stream<ConnectionGeneration?> get generations => connection.generations;

  @override
  ConnectionGeneration? get generation => connection.generation;
}
