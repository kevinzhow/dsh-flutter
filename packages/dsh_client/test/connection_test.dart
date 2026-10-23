import 'dart:math';
import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';

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

  test(
    'pairing asks for interactions=answer and publishes generation 1',
    () async {
      conn.start(host.token);
      final g = await conn.untilConnected();
      expect(g.id, 1);
      expect(g.clientId, 'client-peer-1');
      expect(g.hostHome, '/home/test');
      expect(conn.state, ConnectionState.connected);
      expect(host.connectInteractions, ['answer']);
    },
  );

  test('a wrong launch token halts in needsPairing', () async {
    conn.start('wrong');
    await conn.untilState((s) => s == ConnectionState.needsPairing);
    expect(conn.lastError, isA<PairingRejected>());
    expect(conn.generation, isNull);
  });

  test('interactions none connects without \$events', () async {
    final none = DshConnection(
      origin: host.origin,
      interactions: Interactions.none,
    );
    addTearDown(none.stop);
    none.start(host.token);
    final g = await none.untilConnected();
    expect(g.clientId, isEmpty);
    expect(host.connectInteractions, ['none']);
    expect(host.openStreams[r'$events'], isNull);
  });

  test(
    'unary call uses the named-args envelope and decodes value/error',
    () async {
      host.unary['session/list'] = (args) {
        expect(args, {'_request': <String, Object?>{}});
        return {'items': <Object?>[]};
      };
      host.unary['session/cancel'] = (args) =>
          throw FakeRemoteError('session/not-found', 'gone');
      conn.start(host.token);
      await conn.untilConnected();
      expect(await conn.caller.call('session', 'list', {'_request': {}}), {
        'items': [],
      });
      await expectLater(
        conn.caller.call('session', 'cancel', {'request': {}}),
        throwsA(
          isA<RemoteException>().having(
            (e) => e.code,
            'code',
            'session/not-found',
          ),
        ),
      );
    },
  );

  test('unary call without a generation throws NotConnected', () {
    expect(
      () => conn.caller.call('session', 'list', {}),
      throwsA(isA<NotConnected>()),
    );
  });

  test(
    'openStream reopens on the next generation after the socket drops',
    () async {
      host.streams['session/control'] = (s) => s.item({
        'type': 'baseline',
        'gen': host.openStreams['session/control']!.length,
      });
      conn.start(host.token);
      await conn.untilConnected();
      final frames = <GenerationFrame>[];
      final sub = conn
          .openStream('session/control', () => {})
          .listen(frames.add);
      addTearDown(sub.cancel);
      await _until(() => frames.whereType<StreamItem>().isNotEmpty);
      await host.dropSockets();
      await _until(
        () => frames.whereType<StreamItem>().length >= 2,
        seconds: 8,
      );
      final kinds = frames
          .map((f) => '${f.runtimeType}@${f.generation}')
          .toList();
      expect(kinds.first, 'StreamOpened@1');
      expect(kinds, contains('StreamEnded@1'));
      expect(kinds, contains('StreamOpened@2'));
      expect(conn.generation!.id, 2);
      expect(
        host.pairings,
        2,
        reason: 'a lost socket loses the Peer; re-/connect with the same token',
      );
      final ended = frames.whereType<StreamEnded>().first;
      expect(ended.error, isA<CarrierLost>());
    },
  );

  test(
    'host restart: token refused, needsPairing, then a new token reconnects',
    () async {
      conn.start(host.token);
      await conn.untilConnected();
      await host.restart('launch-token-2');
      await conn.untilState(
        (s) => s == ConnectionState.needsPairing,
        timeout: const Duration(seconds: 40),
      );
      expect(conn.generation, isNull);
      conn.start('launch-token-2');
      final g = await conn.untilConnected();
      expect(g.id, 2);
      expect(conn.state, ConnectionState.connected);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'forwarded emit and waterfall reach hostEvents; answer posts the outcome',
    () async {
      conn.start(host.token);
      await conn.untilConnected();
      final events = <HostEvent>[];
      final sub = conn.hostEvents.listen(events.add);
      addTearDown(sub.cancel);
      final ev = host.openStreams[r'$events']!.single;
      ev.item({
        'type': 'emit',
        'event': 'api-session/status',
        'args': ['s1', true],
      });
      ev.item({
        'type': 'waterfall',
        'event': 'approval/request',
        'eventId': 'e1',
        'agentId': 's1',
        'request': {'toolName': 'shell'},
      });
      ev.item({'type': 'cancel', 'eventId': 'e0'});
      await _until(() => events.length == 3);
      expect((events[0] as EmitEvent).args, ['s1', true]);
      final w = events[1] as WaterfallEvent;
      expect(w.request['toolName'], 'shell');
      await conn.answer(w, const WaterfallResult('allowed-once'));
      expect(host.eventResults.single, {
        'clientId': 'client-peer-1',
        'eventId': 'e1',
        'outcome': {'kind': 'result', 'value': 'allowed-once'},
      });
      expect((events[2] as CancelEvent).eventId, 'e0');
    },
  );

  test('answering on a stale generation fails', () async {
    conn.start(host.token);
    await conn.untilConnected();
    const stale = WaterfallEvent(
      generation: 99,
      event: 'approval/request',
      eventId: 'e',
      agentId: 'a',
      request: {},
    );
    await expectLater(
      conn.answer(stale, const WaterfallNext()),
      throwsA(isA<NotConnected>()),
    );
  });

  test('retry delays follow 500ms..10s with 50-100% jitter', () {
    final r = _FixedRandom(0);
    expect(reconnectDelay(0, r), const Duration(milliseconds: 250));
    expect(reconnectDelay(5, r), const Duration(milliseconds: 5000));
    expect(reconnectDelay(40, r), const Duration(milliseconds: 5000));
    final hi = _FixedRandom(0.9999999);
    expect(reconnectDelay(2, hi).inMilliseconds, inInclusiveRange(1990, 2000));
  });

  test('parseLaunchUrl reads origin and token', () {
    final p = parseLaunchUrl('http://127.0.0.1:18700/?token=abc');
    expect(p.origin, Uri.parse('http://127.0.0.1:18700'));
    expect(p.token, 'abc');
    expect(() => parseLaunchUrl('http://127.0.0.1:1/'), throwsFormatException);
  });
}

class _FixedRandom implements Random {
  _FixedRandom(this.v);
  final double v;
  @override
  double nextDouble() => v;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

Future<void> _until(bool Function() test, {int seconds = 5}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!test()) {
    if (DateTime.now().isAfter(end)) fail('condition not met in ${seconds}s');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
