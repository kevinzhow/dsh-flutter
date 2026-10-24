import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_flutter/src/connection_store.dart';
import 'package:dsh_flutter/src/launch_link.dart';
import 'package:dsh_flutter/src/local_prefs.dart';
import 'package:dsh_flutter/src/screens/qr_scanner_screen.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_conversation/dsh_conversation.dart' show FlushScheduler;
import 'package:dsh_models/testing.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

// A made-up launch token of the real shape.
const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO_-';
const newToken = 'ZYXWVUTSRQPONMLKJIHGFEDCBAzyxwvutsrq_-98765';
final plainLink = 'http://10.0.0.5:8686/?token=$token';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump();
  }
}

class FakeScanner implements LaunchScanner {
  FakeScanner(this.result);
  String? result;
  int scans = 0;
  @override
  bool get available => true;
  @override
  Future<String?> scan() async {
    scans++;
    return result;
  }
}

void main() {
  late FakeBackend backend;
  late AppController controller;
  late MemoryConnectionStore store;
  late MemoryLocalPrefs prefs;

  Future<void> start(
    WidgetTester t, {
    DshLocale locale = DshLocale.en,
    LaunchScanner scanner = const NoScanner(),
    HostResolver? resolver,
    Size size = const Size(1200, 800),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    backend = FakeBackend();
    store = MemoryConnectionStore();
    prefs = MemoryLocalPrefs();
    controller = AppController(
      backend: backend,
      store: store,
      locale: locale,
      scanner: scanner,
      resolver: resolver,
      prefs: prefs,
      frameScheduler: FlushScheduler.immediate(),
    );
    addTearDown(() async {
      controller.dispose();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    });
    await t.pumpWidget(WhaleeApp(controller: controller));
  }

  Future<void> connect(WidgetTester t, {String link = ''}) async {
    backend.transport.onList = () async => {
      'items': [listRow('s1', title: 'Task one')],
    };
    await t.runAsync(
      () => controller.pair(
        link.isEmpty ? 'http://127.0.0.1:8686/?token=$token' : link,
      ),
    );
    await settle(t);
  }

  Future<void> openSession(WidgetTester t) async {
    await openRow(t, 's1');
    await settle(t);
    backend.transport.open(
      1,
      snapshot([userMessage(1, 'Earlier')], projections: {'title': 'Task one'}),
    );
    await settle(t);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  group('reconnect states', () {
    testWidgets('healthy: nothing about the connection is shown', (t) async {
      await start(t);
      await connect(t);
      expect(key('connection-indicator-row'), findsNothing);
    });

    testWidgets(
      'an attempt in flight shows dsh\'s Reconnecting with its retry number',
      (t) async {
        await start(t);
        await connect(t);
        backend.emit(ConnectionState.connecting, attempt: 2);
        await settle(t);
        expect(find.text('Reconnecting'), findsOneWidget);
        expect(find.text('Retry 2'), findsOneWidget);
        expect(controller.reconnecting, isTrue);
      },
    );

    testWidgets(
      'between attempts: Disconnected and a countdown; tap retries now',
      (t) async {
        await start(t);
        await connect(t);
        backend.emit(
          ConnectionState.waiting,
          attempt: 1,
          retryAt: DateTime.now().add(const Duration(milliseconds: 3500)),
        );
        await settle(t);
        expect(find.text('Disconnected'), findsOneWidget);
        expect(find.text('Retry 1, in 4s'), findsOneWidget);
        await t.tap(find.text('Disconnected'));
        expect(backend.reconnects, 1);
      },
    );

    testWidgets('coming back shows Connected for two seconds, then nothing', (
      t,
    ) async {
      await start(t);
      await connect(t);
      backend.emit(ConnectionState.waiting, attempt: 1);
      await settle(t);
      backend.emit(ConnectionState.connected);
      await settle(t);
      expect(find.text('Connected'), findsOneWidget);
      await t.pump(
        AppController.recoveredFor + const Duration(milliseconds: 50),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Connected'), findsNothing);
      expect(controller.reconnecting, isFalse);
    });

    testWidgets('three failed retries: the host is reported unreachable', (
      t,
    ) async {
      await start(t);
      await connect(t);
      backend.emit(ConnectionState.waiting, attempt: 2);
      await settle(t);
      expect(key('connection-unreachable'), findsNothing);
      backend.emit(ConnectionState.waiting, attempt: 3);
      await settle(t);
      expect(key('connection-unreachable'), findsOneWidget);
      expect(find.text('Can\'t reach the host'), findsOneWidget);
      expect(find.textContaining('http://127.0.0.1:8686'), findsWidgets);
      await t.tap(key('connection-retry-now'));
      expect(backend.reconnects, 1);
    });

    testWidgets(
      'the app coming to the front retries a connection that is down',
      (t) async {
        await start(t);
        await connect(t);
        controller.setForeground(true);
        expect(backend.reconnects, 0, reason: 'connected: nothing to retry');
        backend.emit(ConnectionState.waiting, attempt: 1);
        await settle(t);
        controller.setForeground(true);
        expect(backend.reconnects, 1);
      },
    );

    testWidgets('the session screen shows the same indicator', (t) async {
      await start(t);
      await connect(t);
      await openSession(t);
      backend.emit(ConnectionState.waiting, attempt: 1);
      await settle(t);
      expect(find.text('Disconnected'), findsOneWidget);
    });

    testWidgets(
      'Chinese: dsh\'s own words for the indicator, ours for the rest',
      (t) async {
        await start(t, locale: DshLocale.zh);
        await connect(t);
        backend.emit(ConnectionState.waiting, attempt: 3);
        await settle(t);
        expect(find.text('连接异常，刷新重试'), findsOneWidget);
        expect(find.text('连不上主机'), findsOneWidget);
        expect(find.text('立即重试'), findsOneWidget);
        backend.emit(ConnectionState.connecting, attempt: 4);
        await settle(t);
        expect(find.text('重新连接中'), findsOneWidget);
        expect(find.text('第 4 次重试'), findsOneWidget);
      },
    );
  });

  group('host restarted: the launch token is no longer valid', () {
    testWidgets('the sessions stay, a card says why, Pair again re-pairs', (
      t,
    ) async {
      await start(t);
      await connect(t);
      backend.emit(ConnectionState.needsPairing);
      await settle(t);
      expect(key('browser-title'), findsOneWidget, reason: 'sessions stay');
      expect(find.text('The host restarted'), findsOneWidget);
      expect(key('pairing-connect'), findsNothing);
      await t.tap(key('connection-repair'));
      await t.pumpAndSettle();
      expect(key('pairing-url'), findsOneWidget);
      await t.enterText(
        key('pairing-url'),
        'http://127.0.0.1:8686/?token=$newToken',
      );
      await t.tap(key('pairing-connect'));
      await settle(t);
      await t.pumpAndSettle();
      expect(backend.connects.last.$2, newToken);
      expect(key('pairing-url'), findsNothing, reason: 'the page closed');
      expect(key('browser-title'), findsOneWidget);
      expect(controller.phase, ConnectionPhase.connected);
    });

    testWidgets('an unsent message survives the restart and the re-pair', (
      t,
    ) async {
      await start(t);
      await connect(t);
      await openSession(t);
      await t.enterText(find.byType(EditableText).last, 'half a thought');
      await t.pump();
      backend.emit(ConnectionState.needsPairing);
      await settle(t);
      await t.tap(key('connection-repair'));
      await t.pumpAndSettle();
      await t.enterText(
        key('pairing-url'),
        'http://127.0.0.1:8686/?token=$newToken',
      );
      await t.tap(key('pairing-connect'));
      await settle(t);
      await t.pumpAndSettle();
      expect(find.text('half a thought'), findsOneWidget);
    });

    testWidgets('a draft also survives leaving the session and coming back', (
      t,
    ) async {
      await start(t);
      await connect(t);
      await openSession(t);
      await t.enterText(find.byType(EditableText).last, 'kept text');
      await t.pump();
      // Another page (the Plugins panel) takes the centre; the session comes back.
      await t.tap(find.text('Plugins'));
      await settle(t);
      expect(find.text('kept text'), findsNothing);
      await openRow(t, 's1');
      await settle(t);
      expect(find.text('kept text'), findsOneWidget);
    });

    testWidgets('a re-pair that fails says why and stays', (t) async {
      await start(t);
      await connect(t);
      backend.emit(ConnectionState.needsPairing);
      await settle(t);
      await t.tap(key('connection-repair'));
      await t.pumpAndSettle();
      backend.failWith = const ConnectException(ConnectFailure.rejected);
      await t.enterText(
        key('pairing-url'),
        'http://127.0.0.1:8686/?token=$newToken',
      );
      await t.tap(key('pairing-connect'));
      await settle(t);
      await t.pump();
      expect(find.textContaining('refused the token'), findsOneWidget);
      expect(key('browser-title'), findsNothing, reason: 'the page is on top');
    });

    testWidgets('without sessions, the pairing screen explains', (t) async {
      await start(t);
      backend.failWith = const ConnectException(ConnectFailure.rejected);
      await t.runAsync(() => controller.pair(plainLink));
      await settle(t);
      expect(find.textContaining('refused the token'), findsOneWidget);
    });
  });

  group('the host cannot be reached at start-up', () {
    testWidgets('a saved host offers Try again and Forget', (t) async {
      await start(t);
      await store.save(SavedHost('http://10.0.0.5:8686', token));
      backend.failWith = const ConnectException(
        ConnectFailure.unreachable,
        'timed out',
      );
      await t.runAsync(controller.restore);
      await settle(t);
      expect(key('saved-host'), findsOneWidget);
      expect(
        find.textContaining('Can\'t reach http://10.0.0.5:8686'),
        findsOneWidget,
      );
      backend.failWith = null;
      backend.transport.onList = () async => {'items': <Object?>[]};
      await t.tap(key('saved-host-retry'));
      await settle(t);
      expect(key('browser-title'), findsOneWidget);
      expect(backend.connects, hasLength(2));
    });

    testWidgets('Forget removes the saved host', (t) async {
      await start(t);
      await store.save(SavedHost('http://10.0.0.5:8686', token));
      backend.failWith = const ConnectException(ConnectFailure.unreachable);
      await t.runAsync(controller.restore);
      await settle(t);
      await t.tap(key('saved-host-forget'));
      await settle(t);
      expect(key('saved-host'), findsNothing);
      expect(await store.load(), isNull);
    });
  });

  group('plain http', () {
    testWidgets('typing an http address shows the not-encrypted notice', (
      t,
    ) async {
      await start(t);
      expect(key('pairing-http-notice'), findsNothing);
      await t.enterText(key('pairing-url'), 'http://10.0.0.5:8686');
      await t.pump();
      expect(find.textContaining('not encrypted'), findsOneWidget);
      await t.enterText(key('pairing-url'), 'https://dsh.example');
      await t.pump();
      expect(key('pairing-http-notice'), findsNothing);
    });

    testWidgets('connected over http the chip says Not encrypted', (t) async {
      await start(t);
      await connect(t, link: plainLink);
      await t.tap(key('settings-trigger'));
      await settle(t);
      expect(key('security-plain'), findsOneWidget);
      expect(find.text('Not encrypted'), findsOneWidget);
    });

    testWidgets('a public address is refused for http, nothing is sent', (
      t,
    ) async {
      await start(t);
      await t.runAsync(
        () => controller.pair('http://203.0.113.9:8686/?token=$token'),
      );
      await settle(t);
      expect(backend.connects, isEmpty);
      expect(controller.pairingError?.kind, PairingErrorKind.insecure);
      expect(find.textContaining('203.0.113.9'), findsOneWidget);
    });

    testWidgets('loopback and private addresses are accepted', (t) async {
      await start(t);
      for (final host in [
        '127.0.0.1',
        '10.1.2.3',
        '192.168.5.5',
        '100.100.1.1',
        'localhost',
      ]) {
        backend.connects.clear();
        await t.runAsync(
          () => controller.pair('http://$host:8686/?token=$token'),
        );
        expect(backend.connects, hasLength(1), reason: host);
      }
    });

    testWidgets('a name is judged by what it resolves to', (t) async {
      var answer = [InternetAddress('203.0.113.9')];
      await start(t, resolver: (host) async => answer);
      await t.runAsync(
        () => controller.pair('http://dsh.example.org:8686/?token=$token'),
      );
      expect(backend.connects, isEmpty);
      expect(controller.pairingError?.kind, PairingErrorKind.insecure);
      answer = [InternetAddress('192.168.1.7')];
      await t.runAsync(
        () => controller.pair('http://dsh.example.org:8686/?token=$token'),
      );
      expect(backend.connects, hasLength(1));
    });

    testWidgets('a name that does not resolve is unreachable, not insecure', (
      t,
    ) async {
      await start(
        t,
        resolver: (host) async =>
            throw const SocketException('Failed host lookup'),
      );
      await t.runAsync(
        () => controller.pair('http://nowhere.example.org:8686/?token=$token'),
      );
      expect(controller.pairingError?.kind, PairingErrorKind.unreachable);
      expect(backend.connects, isEmpty);
    });
  });

  group('certificates', () {
    final httpsLink = 'https://dsh.example:8443/?token=$token';
    final cert = fakeCertificate(sha256: '11:22:33:44');

    testWidgets(
      'first contact: fingerprint shown, nothing sent, Cancel keeps nothing',
      (t) async {
        await start(t);
        backend.trust.next = ProbeUntrusted(cert);
        await t.runAsync(() => controller.pair(httpsLink));
        await settle(t);
        expect(key('certificate-card'), findsOneWidget);
        expect(find.text('Trust this certificate?'), findsOneWidget);
        expect(find.text('11:22:33:44'), findsOneWidget);
        expect(find.textContaining('host.example'), findsWidgets);
        expect(backend.connects, isEmpty, reason: 'the token has not left');
        await t.tap(key('certificate-cancel'));
        await t.pump();
        expect(key('certificate-card'), findsNothing);
        expect(
          backend.trust.pinnedFingerprint(
            Uri.parse('https://dsh.example:8443'),
          ),
          isNull,
        );
        expect(backend.connects, isEmpty);
      },
    );

    testWidgets('Trust and connect pins the fingerprint, then connects', (
      t,
    ) async {
      await start(t);
      backend.trust.next = ProbeUntrusted(cert);
      backend.transport.onList = () async => {'items': <Object?>[]};
      await t.runAsync(() => controller.pair(httpsLink));
      await settle(t);
      await t.tap(key('certificate-trust'));
      await settle(t);
      expect(
        backend.trust.pinnedFingerprint(Uri.parse('https://dsh.example:8443')),
        '11:22:33:44',
      );
      expect(backend.connects.single.$1, Uri.parse('https://dsh.example:8443'));
      expect(backend.connects.single.$2, token);
      expect(key('browser-title'), findsOneWidget);
      await t.tap(key('settings-trigger'));
      await settle(t);
      expect(key('security-pinned'), findsOneWidget);
      expect(find.text('Encrypted, trusted certificate'), findsOneWidget);
    });

    testWidgets('a pinned host connects without asking again', (t) async {
      await start(t);
      await backend.trust.pin(Uri.parse('https://dsh.example:8443'), cert);
      backend.trust.next = ProbePinned(cert);
      backend.transport.onList = () async => {'items': <Object?>[]};
      await t.runAsync(() => controller.pair(httpsLink));
      await settle(t);
      expect(key('certificate-card'), findsNothing);
      expect(backend.connects, hasLength(1));
    });

    testWidgets('a certificate the system trusts needs no confirmation', (
      t,
    ) async {
      await start(t);
      backend.trust.next = const ProbeSystemTrusted();
      backend.transport.onList = () async => {'items': <Object?>[]};
      await t.runAsync(() => controller.pair(httpsLink));
      await settle(t);
      expect(backend.connects, hasLength(1));
      await t.tap(key('settings-trigger'));
      await settle(t);
      expect(key('security-encrypted'), findsOneWidget);
    });

    testWidgets(
      'a changed certificate is a warning; trust is not offered until reviewed',
      (t) async {
        await start(t);
        final origin = Uri.parse('https://dsh.example:8443');
        await backend.trust.pin(origin, cert);
        final other = fakeCertificate(sha256: '99:88:77:66');
        backend.trust.next = ProbeUntrusted(other);
        await t.runAsync(() => controller.pair(httpsLink));
        await settle(t);
        expect(find.text('The host\'s certificate changed'), findsOneWidget);
        expect(find.text('11:22:33:44'), findsOneWidget);
        expect(find.text('99:88:77:66'), findsOneWidget);
        expect(key('certificate-trust'), findsNothing);
        expect(backend.connects, isEmpty);
        expect(await t.runAsync(controller.trustCertificate), isFalse);
        expect(
          backend.connects,
          isEmpty,
          reason: 'not without the review step',
        );
        await t.tap(key('certificate-review'));
        await settle(t);
        expect(
          backend.trust.pinnedFingerprint(origin),
          isNull,
          reason: 'old pin dropped',
        );
        expect(key('certificate-trust'), findsOneWidget);
        backend.transport.onList = () async => {'items': <Object?>[]};
        await t.tap(key('certificate-trust'));
        await settle(t);
        expect(backend.trust.pinnedFingerprint(origin), '99:88:77:66');
        expect(backend.connects, hasLength(1));
      },
    );

    testWidgets('a host that answers no TLS at all is unreachable', (t) async {
      await start(t);
      backend.trust.next = const ProbeUnreachable(SocketException('refused'));
      await t.runAsync(() => controller.pair(httpsLink));
      await settle(t);
      expect(controller.pairingError?.kind, PairingErrorKind.unreachable);
      expect(backend.connects, isEmpty);
    });

    testWidgets('the certificate is swapped during a live connection', (
      t,
    ) async {
      await start(t);
      final origin = Uri.parse('https://dsh.example:8443');
      await backend.trust.pin(origin, cert);
      backend.trust.next = ProbePinned(cert);
      backend.transport.onList = () async => {'items': <Object?>[]};
      await t.runAsync(() => controller.pair(httpsLink));
      await settle(t);
      backend.emit(
        ConnectionState.certificateRefused,
        refusal: CertificateRefusal(
          authority: 'dsh.example:8443',
          presented: fakeCertificate(sha256: '99:88:77:66'),
          pinned: '11:22:33:44',
        ),
      );
      await settle(t);
      expect(key('browser-title'), findsOneWidget);
      expect(find.text('The connection was refused'), findsOneWidget);
      await t.tap(key('connection-certificate-review'));
      await t.pumpAndSettle();
      expect(find.text('The host\'s certificate changed'), findsOneWidget);
      expect(key('certificate-trust'), findsNothing);
      await t.tap(key('certificate-review'));
      await settle(t);
      backend.trust.next = ProbePinned(fakeCertificate(sha256: '99:88:77:66'));
      await t.tap(key('certificate-trust'));
      await settle(t);
      await t.pumpAndSettle();
      expect(
        backend.connects.last.$2,
        token,
        reason: 'the live token continues',
      );
      expect(backend.trust.pinnedFingerprint(origin), '99:88:77:66');
    });

    testWidgets('Settings: forget the certificate and leave the host', (
      t,
    ) async {
      await start(t);
      final origin = Uri.parse('https://dsh.example:8443');
      await backend.trust.pin(origin, cert);
      backend.trust.next = ProbePinned(cert);
      backend.transport.onList = () async => {'items': <Object?>[]};
      await t.runAsync(() => controller.pair(httpsLink));
      await settle(t);
      await openSettingsUi(t);
      await t.pumpAndSettle();
      await t.tap(key('settings-nav-general'));
      await t.pumpAndSettle();
      expect(find.textContaining('11:22:33:44'), findsOneWidget);
      await t.ensureVisible(key('settings-forget-certificate'));
      await t.tap(key('settings-forget-certificate'));
      await settle(t);
      await t.pumpAndSettle();
      expect(backend.trust.pinnedFingerprint(origin), isNull);
      expect(key('pairing-connect'), findsOneWidget);
    });

    testWidgets('Chinese copy of the decision', (t) async {
      await start(t, locale: DshLocale.zh);
      backend.trust.next = ProbeUntrusted(cert);
      await t.runAsync(() => controller.pair(httpsLink));
      await settle(t);
      expect(find.text('信任此证书？'), findsOneWidget);
      expect(find.text('信任并连接'), findsOneWidget);
    });
  });

  group('QR scanning', () {
    testWidgets('a scanned launch link connects', (t) async {
      final scanner = FakeScanner(plainLink);
      await start(t, scanner: scanner);
      backend.transport.onList = () async => {'items': <Object?>[]};
      await t.tap(key('pairing-scan'));
      await settle(t);
      expect(scanner.scans, 1);
      expect(backend.connects.single.$2, token);
      expect(find.textContaining(token), findsNothing);
    });

    testWidgets('backing out of the camera changes nothing', (t) async {
      await start(t, scanner: FakeScanner(null));
      await t.tap(key('pairing-scan'));
      await settle(t);
      expect(backend.connects, isEmpty);
      expect(key('pairing-connect'), findsOneWidget);
    });
  });

  group('scanner screen', () {
    late _FakeCamera camera;
    var opened = 0;
    String? result;

    Future<void> show(WidgetTester t, {DshLocale locale = DshLocale.en}) async {
      camera = _FakeCamera();
      opened = 0;
      result = null;
      final theme = resolveTheme(
        officialPack,
        ThemeSettings(),
        Brightness.light,
      );
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [theme]),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => QrScannerScreen(
                      camera: camera,
                      i18n: DshI18n(locale),
                      openSystemSettings: () => opened++,
                      noticeFor: const Duration(seconds: 1),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('a launch link ends the scan and is returned', (t) async {
      await show(t);
      expect(key('scan-hint'), findsOneWidget);
      camera.emit(plainLink);
      await t.pumpAndSettle();
      expect(result, plainLink);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets(
      'another QR code is told so, never shown, and scanning goes on',
      (t) async {
        await show(t);
        camera.emit('WIFI:T:WPA;S:cafe;P:secret-password;;');
        await t.pump();
        expect(key('scan-not-link'), findsOneWidget);
        expect(find.textContaining('secret-password'), findsNothing);
        expect(result, isNull);
        expect(find.byType(QrScannerScreen), findsOneWidget);
        await t.pump(const Duration(seconds: 2));
        expect(key('scan-hint'), findsOneWidget);
        camera.emit('http://10.0.0.5:8686/');
        await t.pump();
        expect(
          key('scan-not-link'),
          findsOneWidget,
          reason: 'a link without a token is no link',
        );
        await t.pump(const Duration(seconds: 2));
        camera.emit(plainLink);
        await t.pumpAndSettle();
        expect(result, plainLink);
      },
    );

    testWidgets('a refused camera permission offers the system settings', (
      t,
    ) async {
      await show(t);
      camera.fail(CameraProblem.denied);
      await t.pump();
      expect(find.textContaining('Camera access is off'), findsOneWidget);
      await t.tap(key('scan-open-settings'));
      expect(opened, 1);
    });

    testWidgets('a camera that cannot start points to pasting', (t) async {
      await show(t);
      camera.fail(CameraProblem.unavailable);
      await t.pump();
      expect(find.textContaining('could not start'), findsOneWidget);
      expect(key('scan-open-settings'), findsNothing);
    });

    testWidgets('the close button returns nothing', (t) async {
      await show(t);
      await t.tap(key('scan-close'));
      await t.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('Chinese copy', (t) async {
      await show(t, locale: DshLocale.zh);
      expect(find.text('扫描二维码'), findsOneWidget);
      camera.emit('hello');
      await t.pump();
      expect(find.textContaining('不是 dsh 启动链接'), findsOneWidget);
    });
  });
}

class _FakeCamera implements QrCamera {
  void Function(String)? _onCode;
  _CameraState? _state;

  void emit(String raw) => _onCode!(raw);
  void fail(CameraProblem problem) => _state!.set(problem);

  @override
  Widget preview(
    BuildContext context, {
    required void Function(String raw) onCode,
    required Widget Function(CameraProblem problem) problem,
  }) {
    _onCode = onCode;
    return _FakePreview(owner: this, problem: problem);
  }
}

class _FakePreview extends StatefulWidget {
  const _FakePreview({required this.owner, required this.problem});
  final _FakeCamera owner;
  final Widget Function(CameraProblem problem) problem;
  @override
  State<_FakePreview> createState() => _CameraState();
}

class _CameraState extends State<_FakePreview> {
  CameraProblem? _problem;

  @override
  void initState() {
    super.initState();
    widget.owner._state = this;
  }

  void set(CameraProblem p) => setState(() => _problem = p);

  @override
  Widget build(BuildContext context) =>
      _problem == null ? const SizedBox.expand() : widget.problem(_problem!);
}
