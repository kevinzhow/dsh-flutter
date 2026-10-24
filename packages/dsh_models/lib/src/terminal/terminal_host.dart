import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_terminal.dart';

/// Opens the duplex `terminal/attach` stream of one terminal: output frames
/// down, input and resize commands up.
typedef TerminalAttach = GenerationStream Function(
  String sessionId,
  String terminalId,
);

/// Opens the `terminal/retain` stream of one terminal (a window hold).
typedef TerminalRetain = Stream<GenerationFrame> Function(
  String sessionId,
  String terminalId,
);

/// What the terminal models need from a host, as dsh's `ctx.remote.terminal`
/// and `ctx.remote.$stream` carry it: the generated unary methods, the two
/// stream openers, and the connection generations.
///
/// The real app builds it over its connection ([TerminalHost.over]); tests pass
/// a scripted caller and streams.
class TerminalHost {
  TerminalHost({
    required RemoteCaller caller,
    required this.attach,
    required this.retain,
    required this.generations,
    ConnectionGeneration? Function()? currentGeneration,
  }) : remote = TerminalRemote(caller),
       currentGeneration = currentGeneration ?? (() => null);

  /// The host over one connection.
  factory TerminalHost.over(DshConnection connection) => TerminalHost(
    caller: connection.caller,
    attach: (sessionId, id) => attachOn(connection, sessionId, id),
    retain: (sessionId, id) => retainOn(connection, sessionId, id),
    generations: connection.generations,
    currentGeneration: () => connection.generation,
  );

  /// `terminal/attach` on [connection] (the descriptor of the generated code).
  static GenerationStream attachOn(
    DshConnection connection,
    String sessionId,
    String terminalId,
  ) {
    final stream = connection.openDuplex(
      TerminalStreams.attach.endpoint,
      () => TerminalStreams.attach.encodeArgs((
        agentId: sessionId,
        id: terminalId,
      )),
    );
    return GenerationStream(
      stream.frames,
      send: (item) => stream.send(
        TerminalStreams.attach.encodeUplink!((item as TerminalInput)),
      ),
      end: stream.end,
    );
  }

  /// `terminal/retain` on [connection].
  static Stream<GenerationFrame> retainOn(
    DshConnection connection,
    String sessionId,
    String terminalId,
  ) => connection.openStream(
    TerminalStreams.retain.endpoint,
    () => TerminalStreams.retain.encodeArgs((
      sessionId: sessionId,
      id: terminalId,
    )),
  );

  /// The unary `terminal` methods (the Session id travels as `agentId`).
  final TerminalRemote remote;
  final TerminalAttach attach;
  final TerminalRetain retain;

  /// Publishes a generation when connected and null when it is invalidated.
  final Stream<ConnectionGeneration?> generations;

  /// The generation live now.
  final ConnectionGeneration? Function() currentGeneration;
}
