/// The controller and the header split button.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart' show OpenInAppClient;
import 'package:dsh_feature_open_in_app/dsh_feature_open_in_app.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client implements OpenInAppClient {
  List<String> installed = ['vscode', 'terminal', 'mystery'];
  final List<({String app, String path})> opened = [];
  Object? failure;
  Completer<void>? gate;
  int reads = 0;

  @override
  Future<List<String>> apps() async {
    reads++;
    return installed;
  }

  @override
  Future<void> open(String app, String path) async {
    await gate?.future;
    if (failure != null) throw failure!;
    opened.add((app: app, path: path));
  }

  @override
  Future<Uint8List?> icon(String app) async => null;
}

class _Services implements OpenInAppServices {
  _Services(this.controller, this.shortcuts);

  @override
  final OpenInAppController controller;

  @override
  final ShortcutService? shortcuts;

  @override
  DshI18n get i18n => const DshI18n(DshLocale.en);

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  String? directory = '/work/project';

  @override
  String? currentDirectory() => directory;
}

void main() {
  late _Client client;
  late String? stored;
  late OpenInAppController controller;

  OpenInAppController make() => OpenInAppController(
    client: client,
    readChoice: () => stored,
    writeChoice: (id) => stored = id,
  );

  setUp(() {
    client = _Client();
    stored = null;
    controller = make();
  });

  group('controller', () {
    test('offers nothing until the host is local, then reads once', () async {
      expect(controller.apps, isNull);
      expect(client.reads, 0);
      controller.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(client.reads, 1);
      expect(controller.apps, ['vscode', 'terminal', 'mystery']);
      expect(controller.nameable, ['vscode', 'terminal']);
      controller.setEnabled(true);
      expect(client.reads, 1);
      controller.setEnabled(false);
      expect(controller.apps, isNull);
    });

    test('the choice falls back to the first installed application', () async {
      controller.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentApp(), 'vscode');
      controller.choose('terminal');
      expect(stored, 'terminal');
      expect(controller.currentApp(), 'terminal');
      stored = 'gone';
      expect(controller.currentApp(), 'vscode');
    });

    test('launches one at a time and reports a failure', () async {
      controller.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      client.gate = Completer<void>();
      final first = controller.launch('vscode', '/a');
      expect(controller.busy, isTrue);
      await controller.launch('terminal', '/b');
      client.gate!.complete();
      await first;
      expect(client.opened, [(app: 'vscode', path: '/a')]);
      expect(controller.busy, isFalse);
      client.failure = StateError('no');
      await expectLater(controller.launch('vscode', '/a'), throwsStateError);
      expect(controller.failed, isTrue);
      expect(controller.busy, isFalse);
    });

    test('a read that lands after the host changed is dropped', () async {
      controller.setEnabled(true);
      controller.setEnabled(false);
      await Future<void>.delayed(Duration.zero);
      expect(controller.apps, isNull);
    });
  });

  group('header', () {
    late SlotRegistry slots;
    late _Services services;
    late SessionOwner owner;
    String? cwd = '/work/project';

    Future<void> pump(WidgetTester t, {bool enabled = true}) async {
      t.view.physicalSize = const Size(1280, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      services = _Services(controller, null);
      registerOpenInAppFeature(slots, services: services);
      controller.setEnabled(enabled);
      final base = testSessionOwner('s1');
      owner = SessionOwner(
        session: base.session,
        conversation: base.conversation,
        actions: FakeActions(),
        cwdReader: () => cwd,
      );
      final themed = dshTestApp(const SizedBox()) as MaterialApp;
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: services.navigatorKey,
          theme: themed.theme,
          home: Scaffold(
            body: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: slots.renderList(
                DshSlots.conversationSessionHeaderUtilities
                    .typed<SessionOwner, Widget>(),
                owner,
              ),
            ),
          ),
        ),
      );
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pumpAndSettle();
    }

    testWidgets('a local host shows the split button with a menu', (t) async {
      cwd = '/work/project';
      await pump(t);
      expect(find.byKey(const ValueKey('open-in-app')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-in-app-more')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('open-in-app-more')));
      await t.pumpAndSettle();
      expect(find.text('VS Code (default)'), findsOneWidget);
      expect(find.text('Terminal'), findsOneWidget);
      await t.tap(find.text('Terminal'));
      await t.pumpAndSettle();
      expect(client.opened, [(app: 'terminal', path: '/work/project')]);
      expect(stored, 'terminal', reason: 'a menu pick is remembered');
    });

    testWidgets('the main half opens the preferred application', (t) async {
      cwd = '/work/project';
      await pump(t);
      await t.tap(find.byKey(const ValueKey('open-in-app-main')));
      await t.pumpAndSettle();
      expect(client.opened, [(app: 'vscode', path: '/work/project')]);
      expect(stored, isNull, reason: 'the default click remembers nothing');
    });

    testWidgets('a failed launch announces itself', (t) async {
      cwd = '/work/project';
      client.failure = StateError('no');
      await pump(t);
      await t.tap(find.byKey(const ValueKey('open-in-app-main')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Could not open. Try again.'), findsOneWidget);
      expect(t.widget<DshToast>(find.byType(DshToast)).tone, isNull);
      expect(
        t
            .widget<DshIcon>(
              find.descendant(
                of: find.byType(DshShadowBox),
                matching: find.byType(DshIcon),
              ),
            )
            .icon,
        DshIcons.warning,
      );
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.text('Could not open. Try again.'), findsNothing);
    });

    testWidgets('nothing without a local host or a directory', (t) async {
      cwd = '/work/project';
      await pump(t, enabled: false);
      expect(find.byKey(const ValueKey('open-in-app')), findsNothing);
      cwd = null;
      await pump(t);
      expect(find.byKey(const ValueKey('open-in-app')), findsNothing);
    });

    testWidgets('a single installed application has no menu half', (t) async {
      cwd = '/work/project';
      client.installed = ['vscode'];
      await pump(t);
      expect(find.byKey(const ValueKey('open-in-app-main')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-in-app-more')), findsNothing);
    });
  });
}
