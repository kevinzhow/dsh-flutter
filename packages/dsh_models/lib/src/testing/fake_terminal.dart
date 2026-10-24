import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_terminal.dart';

import '../../dsh_models.dart';
import 'fake_host.dart';

/// A screen snapshot frame as the Host sends it on `terminal/attach`.
Map<String, Object?> terminalSnapshot({
  int sequence = 0,
  String screen = '',
  Map<String, Object?>? info,
  bool writable = true,
  Map<String, Object?>? inputWindow,
}) => {
  'type': 'snapshot',
  'sequence': sequence,
  'screen': screen,
  'info': info ?? terminalInfo(),
  'writable': writable,
  'inputWindow': ?inputWindow,
};

Map<String, Object?> terminalOutput(int sequence, String data) => {
  'type': 'output',
  'sequence': sequence,
  'data': data,
};

Map<String, Object?> terminalState(
  Map<String, Object?> info, {
  bool writable = true,
}) => {'type': 'state', 'info': info, 'writable': writable};

Map<String, Object?> terminalAck(int sequence, {String? refusal}) => {
  'type': 'ack',
  'sequence': sequence,
  'refusal': ?refusal,
};

/// `WebTerminalInfo` JSON.
Map<String, Object?> terminalInfo({
  String id = 't1',
  String title = 'bash',
  String state = 'running',
  int? exitCode,
  int cols = 80,
  int rows = 24,
  String? error,
}) => {
  'id': id,
  'title': title,
  'shell': {
    'path': '/bin/bash',
    'args': ['-i'],
    'name': 'bash',
  },
  'cwd': '/ws',
  'cols': cols,
  'rows': rows,
  'state': state,
  'exitCode': exitCode,
  'error': ?error,
};

/// `TerminalEnvironment` JSON.
Map<String, Object?> terminalEnvironment({
  int maxInputBytes = 65536,
  int maxBufferedBytes = 2097152,
  int maxCols = 500,
  int maxRows = 200,
  int scrollback = 1000,
}) => {
  'cwd': '/ws',
  'maxInputBytes': maxInputBytes,
  'maxBufferedBytes': maxBufferedBytes,
  'maxCols': maxCols,
  'maxRows': maxRows,
  'scrollback': scrollback,
};

/// One open `terminal/attach` of a [FakeTerminalHost]: push frames as the Host
/// would, and read what the Client sent up.
class FakeAttach {
  FakeAttach(this.sessionId, this.terminalId);

  final String sessionId;
  final String terminalId;
  final StreamController<GenerationFrame> frames =
      StreamController<GenerationFrame>(sync: true);

  /// Every uplink command, decoded back from the wire form the Client sent.
  final List<TerminalInput> sent = [];
  bool cancelled = false;

  /// An end (clean or failed) was delivered: nothing more arrives.
  bool ended = false;

  /// When set, the next [send] throws it (a carrier that went away).
  Object? sendFailure;

  void open(int generation) => frames.add(StreamOpened(generation));

  /// One downlink item (a frame as JSON) of [generation].
  void emit(int generation, Map<String, Object?> frame) =>
      frames.add(StreamItem(generation, frame));

  /// The generation ended: [error] null is a clean Host `end`.
  void end(int generation, [Object? error]) {
    ended = true;
    frames.add(StreamEnded(generation, error));
  }

  /// Open and deliver the opening snapshot in one go.
  void start(int generation, [Map<String, Object?>? snapshot]) {
    open(generation);
    emit(generation, snapshot ?? terminalSnapshot());
  }

  /// Uplink commands of one kind, in order.
  List<T> sentOf<T extends TerminalInput>() => sent.whereType<T>().toList();
}

/// One open `terminal/retain` hold.
class FakeRetain {
  FakeRetain(this.sessionId, this.terminalId);
  final String sessionId;
  final String terminalId;
  final StreamController<GenerationFrame> frames =
      StreamController<GenerationFrame>(sync: true);
  bool cancelled = false;
  bool ended = false;

  void open(int generation) => frames.add(StreamOpened(generation));

  /// The hold's generation ended (a lost connection when [error] is a
  /// [CarrierLost]).
  void end(int generation, [Object? error]) {
    ended = true;
    frames.add(StreamEnded(generation, error));
  }

  /// The Host's acknowledgement of the hold on [generation].
  void ack(int generation) =>
      frames.add(StreamItem(generation, {'type': 'retained'}));
}

/// A scriptable terminal Host: unary calls answer from [host] (handlers for
/// `terminal/*` are preinstalled), the two streams are scripted by the test.
class FakeTerminalHost {
  FakeTerminalHost({bool autoAck = true}) : _autoAck = autoAck {
    host.handlers.addAll({
      'terminal/environment': (_) => terminalEnvironment(),
      'terminal/shells': (_) => [
        {
          'path': '/bin/bash',
          'args': ['-i'],
          'name': 'bash',
        },
        {
          'path': '/usr/bin/zsh',
          'args': ['-i'],
          'name': 'zsh',
        },
      ],
      'terminal/list': (_) => <Object?>[],
      'terminal/create': (args) {
        final request = args['request']! as Map<String, Object?>;
        return terminalInfo(id: '${request['id']}');
      },
      'terminal/rename': (_) => null,
      'terminal/close': (_) => null,
    });
  }

  final FakeHost host = FakeHost();
  final List<FakeAttach> attaches = [];
  final List<FakeRetain> retains = [];
  final bool _autoAck;

  /// The generation the fake connection is on.
  int generation = 1;

  FakeAttach get attach => attaches.last;
  FakeRetain get retain => retains.last;

  late final TerminalHost terminalHost = TerminalHost(
    caller: host,
    attach: (sessionId, id) {
      final fake = FakeAttach(sessionId, id);
      attaches.add(fake);
      return GenerationStream(
        fake.frames.stream,
        send: (item) {
          final failure = fake.sendFailure;
          if (failure != null) {
            fake.sendFailure = null;
            throw failure;
          }
          // The wire form, as the real descriptor encodes it.
          fake.sent.add(
            TerminalInput.fromJson((item as TerminalInput).toJson()),
          );
        },
        end: () {},
      );
    },
    retain: (sessionId, id) {
      final fake = FakeRetain(sessionId, id);
      retains.add(fake);
      late final StreamController<GenerationFrame> out;
      out = StreamController<GenerationFrame>(
        sync: true,
        onListen: () {
          fake.frames.stream.listen(out.add, onDone: out.close);
          if (_autoAck) {
            fake.open(generation);
            fake.ack(generation);
          }
        },
        onCancel: () => fake.cancelled = true,
      );
      return out.stream;
    },
    generations: host.gens.stream,
    currentGeneration: () => host.generation,
  );

  /// The connection went away and came back: ends the attachments, publishes the
  /// lost and then the new generation, and re-acks every hold on it as the Host does.
  void reconnect() {
    // The connection's streams end with the generation they were opened on.
    for (final a in attaches.where((a) => !a.cancelled && !a.ended)) {
      a.end(generation, CarrierLost('generation ended'));
    }
    for (final r in retains.where((r) => !r.cancelled && !r.ended)) {
      r.end(generation, CarrierLost('generation ended'));
    }
    host.gens.add(null);
    generation++;
    host.generation = FakeGeneration();
    host.gens.add(host.generation);
    if (_autoAck) {
      for (final r in retains.where((r) => !r.cancelled)) {
        r.ended = false;
        r.open(generation);
        r.ack(generation);
      }
    }
  }

  Future<void> close() => host.close();
}
