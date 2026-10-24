@Tags(['live'])
library;

// Live check of the connection experience against real `dsh web` hosts.
//
// Not run by `flutter test` alone (tag `live`). The test starts its own hosts
// and stops them by the PIDs it started:
//   - one plain http host on loopback, one https host with a self-signed
//     certificate (made here with openssl), both with an isolated DSH_HOME
//     and workspace in a scratch directory under the system temp directory
//     (never ~/.dsh, never another agent's instance);
//   - ports come from DSH_LIVE_PORT_BASE (default 18941; base+1 is used for
//     the TLS host).
// It drives the real AppController with the real LiveBackend: pairing,
// certificate trust (pin, swap, refuse), host restart and re-pair, drafts. No
// model is configured in the isolated home and no prompt is sent.
// The launch links hold the tokens: they are read from the hosts' output into
// memory and never printed. DSH_LIVE_RESULT names the JSON result table.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_test/flutter_test.dart';

final results = <Map<String, Object?>>[];

Future<T> step<T>(
  String name,
  Future<T> Function() body, {
  String Function(T)? detail,
}) async {
  final sw = Stopwatch()..start();
  try {
    final value = await body();
    results.add({
      'check': name,
      'state': 'pass',
      'ms': sw.elapsedMilliseconds,
      'detail': detail?.call(value) ?? '',
    });
    return value;
  } on Object catch (e) {
    results.add({
      'check': name,
      'state': 'FAIL',
      'ms': sw.elapsedMilliseconds,
      'detail': '${e.runtimeType}',
    });
    rethrow;
  }
}

Future<void> until(
  String what,
  bool Function() test, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

/// A `dsh web` this test owns: started with an isolated DSH_HOME, stopped by
/// its own PID. The launch link stays in memory.
class Host {
  Host._(this.process, this.port, this.tls);

  final Process process;
  final int port;
  final bool tls;
  final Completer<String> _link = Completer<String>();
  Future<String> get link => _link.future;
  Uri get origin => Uri.parse('${tls ? 'https' : 'http'}://127.0.0.1:$port');

  static Future<Host> start({
    required int port,
    required String home,
    required String workspace,
    ({String cert, String key})? tls,
  }) async {
    final process = await Process.start(
      'dsh',
      [
        'web',
        '--no-open',
        '--host',
        '127.0.0.1',
        '--port',
        '$port',
        if (tls != null) ...['--tls-cert', tls.cert, '--tls-key', tls.key],
      ],
      workingDirectory: workspace,
      environment: {'DSH_HOME': home, 'NODE_NO_WARNINGS': '1'},
    );
    final host = Host._(process, port, tls != null);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final m = RegExp(r'dsh web: (https?://\S+)').firstMatch(line);
          if (m != null && !host._link.isCompleted) {
            host._link.complete(m.group(1));
          }
        });
    unawaited(process.stderr.drain<void>());
    return host;
  }

  Future<void> stop() async {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }
}

Future<({String cert, String key, String fingerprint})> makeCertificate(
  Directory dir,
  String name,
) async {
  final key = '${dir.path}/$name-key.pem';
  final cert = '${dir.path}/$name-cert.pem';
  final made = await Process.run('openssl', [
    'req',
    '-x509',
    '-newkey',
    'ec',
    '-pkeyopt',
    'ec_paramgen_curve:prime256v1',
    '-nodes',
    '-days',
    '2',
    '-keyout',
    key,
    '-out',
    cert,
    '-subj',
    '/CN=$name',
    '-addext',
    'subjectAltName=IP:127.0.0.1',
  ]);
  expect(made.exitCode, 0);
  await Process.run('chmod', ['600', key]);
  final fp = await Process.run('openssl', [
    'x509',
    '-in',
    cert,
    '-noout',
    '-fingerprint',
    '-sha256',
  ]);
  return (
    cert: cert,
    key: key,
    fingerprint: (fp.stdout as String).trim().split('=').last,
  );
}

void main() {
  test('the connection experience against live dsh hosts', () async {
    // The real binding (not the test one, which blocks real sockets).
    WidgetsFlutterBinding.ensureInitialized();
    final base = int.parse(
      Platform.environment['DSH_LIVE_PORT_BASE'] ?? '18941',
    );
    expect(base == 18686 || base == 8686 || base + 1 == 8686, isFalse);
    final scratch = await Directory.systemTemp.createTemp('whalee-live-conn-');
    final plainHome = Directory('${scratch.path}/home-plain')..createSync();
    final tlsHome = Directory('${scratch.path}/home-tls')..createSync();
    final ws = Directory('${scratch.path}/ws')..createSync();
    final certDir = Directory('${scratch.path}/tls')..createSync();
    await Process.run('chmod', ['700', scratch.path]);
    final started = <Host>[];
    Future<Host> launch(
      int port,
      Directory home, {
      ({String cert, String key})? tls,
    }) async {
      final h = await Host.start(
        port: port,
        home: home.path,
        workspace: ws.path,
        tls: tls,
      );
      started.add(h);
      return h;
    }

    final controller = AppController(
      backend: LiveBackend(connectTimeout: const Duration(seconds: 30)),
      locale: DshLocale.en,
    );
    try {
      // ---- plain http, loopback ------------------------------------------
      var plain = await launch(base, plainHome);
      var link = await plain.link;
      await step('plain http: pair on loopback', () async {
        final ok = await controller.pair(link);
        expect(ok, isTrue, reason: '${controller.pairingError?.kind}');
        expect(controller.security, LinkSecurity.plain);
        return controller.hostOrigin;
      }, detail: (o) => 'connected to $o, security plain');

      await step('create a session and open it', () async {
        await controller.createSession();
        expect(controller.openSessionId, isNotNull);
        final sc = controller.openSession!;
        await sc.open();
        return sc.sessionId;
      });
      final owner = controller.openSession!.owner;
      owner.textDraft!.text = 'a half-written message';
      final openId = controller.openSessionId!;

      // ---- host restart: backoff, token expiry, re-pair ---------------------
      final seen = <String>[];
      final sub = controller.backend.statuses.listen((s) {
        final tag = '${s.state.name}#${s.attempt}';
        if (seen.isEmpty || seen.last != tag) seen.add(tag);
      });
      await step(
        'host restart: waiting with backoff, then needs pairing',
        () async {
          await plain.stop();
          await until(
            'waiting',
            () => seen.any((s) => s.startsWith('waiting')),
          );
          expect(controller.reconnecting, isTrue);
          plain = await launch(base, plainHome);
          link = await plain.link;
          await until(
            'needsPairing',
            () => controller.status.state == ConnectionState.needsPairing,
            timeout: const Duration(seconds: 90),
          );
          expect(controller.phase, ConnectionPhase.needsPairing);
          expect(controller.manager, isNotNull, reason: 'sessions stay');
          return seen.join(' > ');
        },
        detail: (s) => s.length > 200 ? s.substring(0, 200) : s,
      );

      await step(
        're-pair with the new link: the same session resumes',
        () async {
          final ok = await controller.pair(link);
          expect(ok, isTrue, reason: '${controller.pairingError?.kind}');
          await until(
            'session open again',
            () =>
                controller.openSession!.session.snapshot.value.openState.name ==
                'open',
          );
          expect(controller.openSessionId, openId);
          expect(owner.textDraft!.text, 'a half-written message');
          return controller.status.state.name;
        },
        detail: (s) => 'state $s, draft kept',
      );
      await sub.cancel();

      await step('refused: plain http to a public address', () async {
        final before = controller.phase;
        final ok = await controller.pair(
          'http://203.0.113.9:8686/?token=abcdefgh',
        );
        expect(ok, isFalse);
        expect(controller.pairingError?.kind, PairingErrorKind.insecure);
        expect(controller.phase, before);
        return null;
      });
      await controller.disconnect();

      // ---- self-signed TLS ----------------------------------------------
      final cert1 = await makeCertificate(certDir, 'whalee-live-1');
      final cert2 = await makeCertificate(certDir, 'whalee-live-2');
      var tls = await launch(
        base + 1,
        tlsHome,
        tls: (cert: cert1.cert, key: cert1.key),
      );
      var tlsLink = await tls.link;
      await step(
        'TLS: first contact shows the fingerprint and sends nothing',
        () async {
          final ok = await controller.pair(tlsLink);
          expect(ok, isFalse);
          final prompt = controller.certificatePrompt;
          expect(prompt, isNotNull);
          expect(prompt!.certificate.sha256, cert1.fingerprint);
          expect(prompt.changed, isFalse);
          expect(controller.phase, ConnectionPhase.disconnected);
          return prompt.certificate.sha256;
        },
        detail: (fp) => 'fingerprint equals openssl: $fp',
      );

      await step('TLS: decline keeps nothing', () async {
        controller.declineCertificate();
        expect(controller.certificatePrompt, isNull);
        expect(controller.backend.trust.pinnedFingerprint(tls.origin), isNull);
        return null;
      });

      await step(
        'TLS: trust, then pairing, session list and a session over wss',
        () async {
          await controller.pair(tlsLink);
          final ok = await controller.trustCertificate();
          expect(ok, isTrue, reason: '${controller.pairingError?.kind}');
          expect(controller.security, LinkSecurity.pinned);
          await controller.createSession();
          expect(controller.openSessionId, isNotNull);
          await controller.openSession!.open();
          return controller.backend.trust.pinnedFingerprint(tls.origin);
        },
        detail: (fp) => 'pinned $fp',
      );

      await step(
        'TLS: a different certificate is refused, nothing is sent',
        () async {
          await tls.stop();
          tls = await launch(
            base + 1,
            tlsHome,
            tls: (cert: cert2.cert, key: cert2.key),
          );
          tlsLink = await tls.link;
          await until(
            'certificateRefused',
            () => controller.status.state == ConnectionState.certificateRefused,
            timeout: const Duration(seconds: 60),
          );
          final refusal = controller.status.refusal!;
          expect(refusal.changed, isTrue);
          expect(refusal.pinned, cert1.fingerprint);
          expect(refusal.presented.sha256, cert2.fingerprint);
          return refusal.presented.sha256;
        },
        detail: (fp) => 'presented $fp, pinned unchanged',
      );

      await step(
        'TLS: review, trust the new certificate, pair again',
        () async {
          controller.reviewRefusedCertificate();
          final prompt = controller.certificatePrompt!;
          expect(prompt.canTrust, isFalse);
          await controller.reviewCertificateChange();
          expect(prompt.canTrust, isTrue);
          // The restarted host has a new launch link: re-pair with it.
          controller.declineCertificate();
          await controller.pair(tlsLink);
          expect(controller.certificatePrompt, isNotNull);
          final ok = await controller.trustCertificate();
          expect(ok, isTrue, reason: '${controller.pairingError?.kind}');
          return controller.backend.trust.pinnedFingerprint(tls.origin);
        },
        detail: (fp) => 'now pinned $fp',
      );
    } finally {
      controller.dispose();
      for (final h in started) {
        await h.stop();
      }
      await scratch.delete(recursive: true);
      final out = Platform.environment['DSH_LIVE_RESULT'];
      if (out != null) {
        File(out).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({'results': results}),
        );
      }
      for (final r in results) {
        // ignore: avoid_print
        print('${r['state']}  ${r['check']} (${r['ms']} ms) ${r['detail']}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
