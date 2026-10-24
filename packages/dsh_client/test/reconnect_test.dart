import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';

/// A pairing that fails the first [failures] attempts like an unreachable host
/// would, then talks to the real fake host.
class FlakyPairing extends Pairing {
  FlakyPairing(this.failures);
  int failures;
  int calls = 0;

  @override
  Future<PairedCredential> pair(
    Uri origin,
    String launchToken, {
    Interactions interactions = Interactions.answer,
    HttpClient? client,
  }) async {
    calls++;
    if (failures > 0) {
      failures--;
      throw const SocketException('connection refused');
    }
    return super.pair(
      origin,
      launchToken,
      interactions: interactions,
      client: client,
    );
  }
}

class _ZeroRandom implements Random {
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

void main() {
  late FakeHost host;
  final connections = <DshConnection>[];

  setUp(() async => host = await FakeHost.start());
  tearDown(() async {
    for (final c in connections) {
      await c.stop();
    }
    connections.clear();
    await host.stop();
  });

  DshConnection make({
    Pairing? pairing,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? clock,
  }) {
    final c = DshConnection(
      origin: host.origin,
      pairing: pairing,
      random: _ZeroRandom(),
      sleep: sleep,
      clock: clock,
    );
    connections.add(c);
    return c;
  }

  test(
    'failed attempts back off 0.5s..10s (jittered) and count retry numbers',
    () async {
      final delays = <Duration>[];
      final c = make(
        pairing: FlakyPairing(6),
        sleep: (d) async {
          delays.add(d);
          await Future<void>.delayed(Duration.zero);
        },
      );
      final seen = <(ConnectionState, int)>[];
      c.statuses.listen((s) => seen.add((s.state, s.attempt)));
      c.start(host.token);
      await c.untilConnected();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Jitter 0 gives half of each cap: 500, 1000, 2000, 4000, 8000, 10000.
      expect(delays.map((d) => d.inMilliseconds), [
        250,
        500,
        1000,
        2000,
        4000,
        5000,
      ]);
      // Waiting for retry N, then retry N in flight, then back to zero.
      expect(
        seen.where((s) => s.$1 == ConnectionState.waiting).map((s) => s.$2),
        [1, 2, 3, 4, 5, 6],
      );
      expect(
        seen.where((s) => s.$1 == ConnectionState.pairing).map((s) => s.$2),
        [0, 1, 2, 3, 4, 5, 6],
      );
      expect(seen.last, (ConnectionState.connected, 0));
      expect(c.status.attempt, 0);
    },
  );

  test('after three failed retries the status says unreachable, and keeps retrying', () async {
    final gate = Completer<void>();
    final pairing = FlakyPairing(1000);
    final now = DateTime.utc(2026, 1, 1, 12);
    final c = make(
      pairing: pairing,
      clock: () => now,
      sleep: (d) async {
        if (pairing.calls >= 3) await gate.future;
      },
    );
    c.start(host.token);
    await c.untilState((s) => s == ConnectionState.waiting);
    expect(c.status.unreachable, isFalse);
    await _until(
      () => pairing.calls >= 3 && c.status.state == ConnectionState.waiting,
    );
    expect(c.status.attempt, 3);
    expect(c.status.unreachable, isTrue);
    expect(c.status.retryAt, now.add(const Duration(milliseconds: 1000)));
    expect(c.status.error, isA<SocketException>());
    gate.complete();
    await _until(() => pairing.calls > 3, reason: 'the loop goes on');
  });

  test('reconnectNow skips the wait and starts the retry count over', () async {
    final gate = Completer<void>();
    final pairing = FlakyPairing(2);
    final c = make(
      pairing: pairing,
      sleep: (d) => pairing.calls <= 2 ? gate.future : Future<void>.value(),
    );
    c.start(host.token);
    await _until(
      () => pairing.calls == 1 && c.status.state == ConnectionState.waiting,
    );
    c.reconnectNow();
    await _until(
      () => pairing.calls == 2 && c.status.state == ConnectionState.waiting,
    );
    expect(c.status.attempt, 1, reason: 'the retry number restarted from 0');
    c.reconnectNow();
    final g = await c.untilConnected();
    expect(g.id, 1);
    expect(c.status.attempt, 0);
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.state, ConnectionState.connected, reason: 'old loop stayed out');
    expect(host.pairings, 1);
  });

  test('reconnectNow does nothing while connected or before start', () async {
    final c = make();
    c.reconnectNow();
    expect(c.state, ConnectionState.idle);
    c.start(host.token);
    await c.untilConnected();
    c.reconnectNow();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(host.pairings, 1);
    expect(c.generation!.id, 1);
  });

  test(
    'a lost socket shows waiting with retry 1, then a new generation',
    () async {
      final c = make();
      c.start(host.token);
      await c.untilConnected();
      final seen = <ConnectionStatus>[];
      c.statuses.listen(seen.add);
      await host.dropSockets();
      await c.untilState((s) => s == ConnectionState.waiting);
      expect(c.status.attempt, 1);
      expect(c.status.retryAt, isNotNull);
      expect(c.generation, isNull);
      final g = await c.untilConnected();
      expect(g.id, 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seen.last.state, ConnectionState.connected);
      expect(seen.last.attempt, 0);
    },
  );

  test('token expiry (host restart): halts in needsPairing and stops retrying; a new token resumes', () async {
    final pairing = FlakyPairing(0);
    final c = make(pairing: pairing);
    c.start(host.token);
    await c.untilConnected();
    await host.restart('launch-token-2');
    await c.untilState(
      (s) => s == ConnectionState.needsPairing,
      timeout: const Duration(seconds: 20),
    );
    expect(c.lastError, isA<PairingRejected>());
    expect(c.status.retryAt, isNull);
    final calls = pairing.calls;
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(
      pairing.calls,
      calls,
      reason: 'no retry with a token the host refused',
    );
    c.reconnectNow();
    expect(
      c.state,
      ConnectionState.needsPairing,
      reason: 'retry cannot fix a refused token',
    );
    c.start('launch-token-2');
    final g = await c.untilConnected();
    expect(g.id, 2);
    expect(c.status.attempt, 0);
    expect(c.lastError, isNull);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('a host that is down for a while: waiting, then reachable again, same token still good', () async {
    final c = make();
    c.start(host.token);
    await c.untilConnected();
    final port = host.port;
    final token = host.token;
    await host.stop();
    await c.untilState((s) => s == ConnectionState.waiting);
    await _until(() => c.status.attempt >= 2);
    host = await FakeHost.start(port: port, token: token);
    final g = await c.untilConnected(timeout: const Duration(seconds: 25));
    expect(g.id, 2, reason: 'same host process: the token is still valid');
    expect(c.status.attempt, 0);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test(
    'streams resume on the next generation with the cursor of the moment',
    () async {
      host.streams['session/follow'] = (s) {
        final from = (s.payload as Map)['args'] as Map;
        s.item({'type': 'snapshot', 'from': from['after']});
      };
      final c = make();
      c.start(host.token);
      await c.untilConnected();
      var cursor = 0;
      final from = <Object?>[];
      final opened = <int>[];
      final sub = c
          .openStream('session/follow', () => {'after': cursor})
          .listen((f) {
            if (f is StreamOpened) opened.add(f.generation);
            if (f is StreamItem) {
              from.add((f.value as Map)['from']);
              cursor += 7;
            }
          });
      addTearDown(sub.cancel);
      await _until(() => from.length == 1);
      await host.dropSockets();
      await _until(() => from.length == 2, seconds: 10);
      expect(from, [0, 7]);
      expect(opened, [1, 2]);
    },
  );
}

Future<void> _until(
  bool Function() test, {
  int seconds = 5,
  String? reason,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!test()) {
    if (DateTime.now().isAfter(end)) {
      fail(reason ?? 'condition not met in ${seconds}s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
