import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';
import 'support/self_signed.dart';

void main() {
  late TestCertificate certA;
  late TestCertificate certB;
  late HostTrust trust;
  FakeHost? host;
  final connections = <DshConnection>[];

  setUpAll(() async {
    certA = await TestCertificate.create('whalee-test-a.example');
    certB = await TestCertificate.create('whalee-test-b.example');
  });
  tearDownAll(() async {
    await certA.dispose();
    await certB.dispose();
  });
  setUp(() => trust = HostTrust());
  tearDown(() async {
    for (final c in connections) {
      await c.stop();
    }
    connections.clear();
    await host?.stop();
    host = null;
    await trust.dispose();
  });

  DshConnection connect(Uri origin, String token) {
    final c = DshConnection(
      origin: origin,
      trust: trust,
      pingInterval: const Duration(seconds: 30),
    );
    connections.add(c);
    c.start(token);
    return c;
  }

  test('fingerprint formatting equals openssl', () async {
    host = await FakeHost.start(tls: certA.context);
    final probe = await trust.probe(host!.origin);
    expect(probe, isA<ProbeUntrusted>());
    final cert = (probe as ProbeUntrusted).certificate;
    expect(cert.sha256, certA.fingerprint);
    expect(cert.selfSigned, isTrue);
    expect(cert.subject, contains('whalee-test-a.example'));
    expect(cert.expiredAt(DateTime.now()), isFalse);
    expect(
      cert.expiredAt(DateTime.now().add(const Duration(days: 30))),
      isTrue,
    );
    expect(
      cert.notYetValidAt(DateTime.now().subtract(const Duration(days: 30))),
      isTrue,
    );
  });

  test('probe sends no request: the host sees no pairing, no token', () async {
    host = await FakeHost.start(tls: certA.context);
    await trust.probe(host!.origin);
    expect(host!.pairings, 0);
  });

  test('a self-signed host is refused until the user pins it; the token is never sent', () async {
    host = await FakeHost.start(tls: certA.context);
    final c = connect(host!.origin, host!.token);
    await c.untilState((s) => s == ConnectionState.certificateRefused);
    final refusal = c.status.refusal!;
    expect(refusal.changed, isFalse);
    expect(refusal.presented.sha256, certA.fingerprint);
    expect(host!.pairings, 0, reason: 'refused during the handshake');
    expect(host!.connectInteractions, isEmpty);
    expect(c.generation, isNull);
  });

  test('after the user pins the fingerprint the connection comes up (pairing, mux, unary)', () async {
    host = await FakeHost.start(tls: certA.context);
    final probe = await trust.probe(host!.origin) as ProbeUntrusted;
    await trust.pin(host!.origin, probe.certificate);
    host!.unary['session/list'] = (_) => {'items': <Object?>[]};
    final c = connect(host!.origin, host!.token);
    final g = await c.untilConnected();
    expect(g.id, 1);
    expect(await c.caller.call('session', 'list', {'_request': {}}), {
      'items': [],
    });
    expect(trust.pinnedFingerprint(host!.origin), certA.fingerprint);
    expect(await trust.probe(host!.origin), isA<ProbePinned>());
  });

  test('a pin is per host and port', () async {
    host = await FakeHost.start(tls: certA.context);
    final probe = await trust.probe(host!.origin) as ProbeUntrusted;
    await trust.pin(host!.origin, probe.certificate);
    final otherPort = host!.origin.replace(port: host!.port + 1);
    expect(trust.pinnedFingerprint(otherPort), isNull);
    expect(authorityOf(host!.origin), '127.0.0.1:${host!.port}');
    expect(authorityOf(Uri.parse('https://Example.COM')), 'example.com:443');
    expect(authorityOf(Uri.parse('https://[::1]:9000')), '[::1]:9000');
  });

  test(
    'a swapped certificate is refused as changed, never accepted silently',
    () async {
      host = await FakeHost.start(tls: certA.context);
      final probe = await trust.probe(host!.origin) as ProbeUntrusted;
      await trust.pin(host!.origin, probe.certificate);
      final c = connect(host!.origin, host!.token);
      await c.untilConnected();
      final port = host!.port;
      await host!.stop();
      host = await FakeHost.start(port: port, tls: certB.context);
      // The old socket is gone; the connection retries and meets certificate B.
      await c.untilState(
        (s) => s == ConnectionState.certificateRefused,
        timeout: const Duration(seconds: 20),
      );
      final refusal = c.status.refusal!;
      expect(refusal.changed, isTrue);
      expect(refusal.pinned, certA.fingerprint);
      expect(refusal.presented.sha256, certB.fingerprint);
      expect(host!.pairings, 0, reason: 'no token for an impostor');
      final changed = await trust.probe(host!.origin);
      expect(changed, isA<ProbeChanged>());
      expect((changed as ProbeChanged).pinned, certA.fingerprint);
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test('forgetting the pin makes the host untrusted again; pinning the new one works', () async {
    host = await FakeHost.start(tls: certA.context);
    final probe = await trust.probe(host!.origin) as ProbeUntrusted;
    await trust.pin(host!.origin, probe.certificate);
    await trust.forget(host!.origin);
    expect(trust.pinnedFingerprint(host!.origin), isNull);
    expect(await trust.probe(host!.origin), isA<ProbeUntrusted>());
    final c = connect(host!.origin, host!.token);
    await c.untilState((s) => s == ConnectionState.certificateRefused);
    await trust.pin(host!.origin, probe.certificate);
    c.start(host!.token);
    await c.untilConnected();
  });

  test('plain http origins use no certificate policy', () async {
    host = await FakeHost.start();
    expect(await trust.probe(host!.origin), isA<ProbeNoTls>());
    final c = connect(host!.origin, host!.token);
    await c.untilConnected();
  });

  test(
    'probing a closed port reports unreachable, not a certificate verdict',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      final probe = await trust.probe(
        Uri.parse('https://127.0.0.1:$port'),
        timeout: const Duration(seconds: 3),
      );
      expect(probe, isA<ProbeUnreachable>());
    },
  );

  test('a pin is exact: even a certificate with the right name is refused when it differs', () async {
    host = await FakeHost.start(tls: certA.context);
    await trust.pin(
      host!.origin,
      CertificateInfo(
        sha256: certB.fingerprint,
        subject: 'x',
        issuer: 'x',
        notBefore: DateTime(2020),
        notAfter: DateTime(2100),
      ),
    );
    final c = connect(host!.origin, host!.token);
    await c.untilState((s) => s == ConnectionState.certificateRefused);
    expect(c.status.refusal!.pinned, certB.fingerprint);
    expect(c.status.refusal!.presented.sha256, certA.fingerprint);
  });

  test('MemoryPinStore round trip', () async {
    final store = MemoryPinStore({'a:1': 'X'});
    expect(store.pinFor('a:1'), 'X');
    await store.pin('b:2', 'Y');
    await store.forget('a:1');
    expect(store.pinFor('a:1'), isNull);
    expect(store.pinFor('b:2'), 'Y');
  });
}
