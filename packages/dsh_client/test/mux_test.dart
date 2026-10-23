import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';

void main() {
  late FakeHost host;
  late MuxCarrier carrier;

  setUp(() async {
    host = await FakeHost.start();
    final cred = await Pairing().pair(host.origin, host.token);
    carrier = await MuxCarrier.connect(cred);
  });

  tearDown(() async {
    await carrier.close();
    await host.stop();
  });

  test('items, end, uplink and cancel frames', () async {
    host.streams['t/echo'] = (s) {
      s.item(1);
      s.item({'a': 2});
      s.end();
    };
    final stream = carrier.open('t/echo', {
      'args': {'x': 1},
    });
    expect(await stream.items.toList(), [
      1,
      {'a': 2},
    ]);
    expect(host.openStreams['t/echo']!.single.payload, {
      'args': {'x': 1},
    });

    host.streams['t/open'] = (_) {};
    final s2 = carrier.open('t/open', {'args': {}});
    s2.send('up');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(host.openStreams['t/open']!.single.uplink, ['up']);
    await s2.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(host.openStreams['t/open']!.single.cancelled, isTrue);
  });

  test('a host error frame becomes a RemoteException on the stream', () async {
    host.streams['t/bad'] = (s) => s.error('gateway/input-invalid', 'nope');
    final stream = carrier.open('t/bad', {'args': {}});
    await expectLater(
      stream.items.drain<void>(),
      throwsA(
        isA<RemoteException>().having(
          (e) => e.code,
          'code',
          'gateway/input-invalid',
        ),
      ),
    );
  });

  test(
    'closing the socket fails every logical stream with CarrierLost',
    () async {
      host.streams['t/open'] = (_) {};
      final stream = carrier.open('t/open', {'args': {}});
      final failed = expectLater(
        stream.items.drain<void>(),
        throwsA(isA<CarrierLost>()),
      );
      await host.dropSockets();
      await failed;
      expect((await carrier.closed), isA<CarrierLost>());
      expect(() => carrier.open('t/x', {}), throwsA(isA<CarrierLost>()));
    },
  );

  test('a second socket for the same Peer is refused (409)', () async {
    final cred = await Pairing().pair(host.origin, host.token);
    final first = await MuxCarrier.connect(cred);
    addTearDown(first.close);
    await expectLater(
      MuxCarrier.connect(cred),
      throwsA(
        isA<RemoteException>().having(
          (e) => e.code,
          'code',
          'transport/upgrade-refused',
        ),
      ),
    );
  });
}
