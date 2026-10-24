import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_terminal.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';

Future<void> _until(bool Function() test, {int seconds = 5}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!test()) {
    if (DateTime.now().isAfter(end)) fail('condition not met in ${seconds}s');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late FakeHost host;
  late DshConnection conn;

  setUp(() async {
    host = await FakeHost.start();
    conn = DshConnection(origin: host.origin);
  });

  tearDown(() async {
    await conn.stop();
    await host.stop();
  });

  test('uplink items reach the stream that is open, in order', () async {
    host.streams['terminal/attach'] = (s) => s.item({'type': 'ack'});
    conn.start(host.token);
    await conn.untilConnected();
    final duplex = conn.openDuplex(
      'terminal/attach',
      () => {'agentId': 's1', 'id': 't1'},
    );
    final frames = <GenerationFrame>[];
    final sub = duplex.frames.listen(frames.add);
    addTearDown(sub.cancel);
    await _until(() => frames.whereType<StreamItem>().isNotEmpty);
    final open = host.openStreams['terminal/attach']!.single;
    expect(open.payload, {
      'args': {'agentId': 's1', 'id': 't1'},
    });
    duplex.send({'type': 'write', 'sequence': 1, 'data': 'a'});
    duplex.send({'type': 'resize', 'sequence': 2, 'cols': 90, 'rows': 30});
    await _until(() => open.uplink.length == 2);
    expect(open.uplink, [
      {'type': 'write', 'sequence': 1, 'data': 'a'},
      {'type': 'resize', 'sequence': 2, 'cols': 90, 'rows': 30},
    ]);
  });

  test('an item sent while no stream is open throws and is not kept', () async {
    host.streams['terminal/attach'] = (s) {};
    conn.start(host.token);
    await conn.untilConnected();
    final duplex = conn.openDuplex('terminal/attach', () => {});
    final frames = <GenerationFrame>[];
    final sub = duplex.frames.listen(frames.add);
    addTearDown(sub.cancel);
    await _until(() => host.openStreams['terminal/attach']?.length == 1);
    await host.dropSockets();
    await _until(() => frames.whereType<StreamEnded>().isNotEmpty);
    expect(
      () => duplex.send({'type': 'write', 'sequence': 1, 'data': 'lost'}),
      throwsA(isA<NotConnected>()),
    );
    // The next generation opens a fresh stream that never sees the lost item.
    await _until(
      () => host.openStreams['terminal/attach']!.length == 2,
      seconds: 10,
    );
    expect(host.openStreams['terminal/attach']!.last.uplink, isEmpty);
  });

  test('the generated terminal descriptor encodes arguments and uplink', () {
    final attach = TerminalStreams.attach;
    expect(attach.endpoint, 'terminal/attach');
    expect(attach.encodeArgs((agentId: 's1', id: 't1')), {
      'agentId': 's1',
      'id': 't1',
    });
    expect(
      attach.encodeUplink!(const TerminalInputWrite(sequence: 3, data: 'ls\r')),
      {'type': 'write', 'sequence': 3, 'data': 'ls\r'},
    );
    expect(
      attach.encodeUplink!(
        const TerminalInputResize(sequence: 4, cols: 100, rows: 40),
      ),
      {'type': 'resize', 'sequence': 4, 'cols': 100, 'rows': 40},
    );
    final snapshot = attach.decodeFrame({
      'type': 'snapshot',
      'sequence': 7,
      'screen': 'x',
      'writable': true,
      'inputWindow': {'maxBytes': 1024, 'frameOverheadBytes': 40},
      'info': {
        'id': 't1',
        'title': 'bash',
        'shell': {
          'path': '/bin/bash',
          'args': ['-i'],
          'name': 'bash',
        },
        'cwd': '/w',
        'cols': 80,
        'rows': 24,
        'state': 'running',
        'exitCode': null,
      },
    });
    expect(snapshot, isA<TerminalFrameSnapshot>());
    expect((snapshot as TerminalFrameSnapshot).inputWindow!.maxBytes, 1024);
    expect(
      attach.decodeFrame({'type': 'wat'}),
      isA<TerminalFrameUnrecognized>(),
    );
    expect(TerminalStreams.retain.encodeArgs((sessionId: 's1', id: 't1')), {
      'sessionId': 's1',
      'id': 't1',
    });
  });
}
