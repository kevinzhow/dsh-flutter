import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_approval/dsh_feature_approval.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/local_prefs.dart';
import 'package:dsh_flutter/src/notice_coordinator.dart';
import 'package:dsh_flutter/src/platform/notifications.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

WaterfallEvent approval(
  String id, {
  String session = 's1',
  String tool = 'bash',
}) => WaterfallEvent(
  generation: 1,
  event: 'approval/request',
  eventId: id,
  agentId: session,
  request: {'toolName': tool, 'callId': 'c-$id'},
);

WaterfallEvent question(String id, String text, {String session = 's1'}) =>
    WaterfallEvent(
      generation: 1,
      event: 'user-questions/request',
      eventId: id,
      agentId: session,
      request: {
        'questions': [
          {
            'id': 'q',
            'question': text,
            'options': [
              {'label': 'A'},
            ],
          },
        ],
      },
    );

Future<void> pump() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('coordinator', () {
    late StreamController<HostEvent> events;
    late ApprovalTracker approvals;
    late QuestionTracker questions;
    late FakeNotifications service;
    late NoticeCoordinator coordinator;
    late List<String> opened;
    var running = 0;

    Future<void> setUpCoordinator({
      NoticePermission permission = NoticePermission.granted,
      bool enabled = true,
    }) async {
      events = StreamController<HostEvent>.broadcast(sync: true);
      approvals = ApprovalTracker(
        events: events.stream,
        answer: (_, _) async {},
      );
      questions = QuestionTracker(
        events: events.stream,
        answer: (_, _) async {},
      );
      service = FakeNotifications(grant: permission);
      opened = [];
      running = 0;
      coordinator = NoticeCoordinator(
        service: service,
        approvals: approvals,
        questions: questions,
        i18n: () => const DshI18n(DshLocale.en),
        sessionTitle: (id) => id == 's1' ? 'Refactor' : 'Untitled session',
        runningSessions: () => running,
        onOpen: opened.add,
        enabled: enabled,
      );
      await coordinator.init();
      coordinator.setConnected(true);
    }

    tearDown(() async {
      await coordinator.dispose();
      await approvals.dispose();
      await questions.dispose();
      await events.close();
    });

    test('the platform side starts with the tap callback and learns the permission', () async {
      await setUpCoordinator(permission: NoticePermission.denied);
      expect(service.initCalls, 1);
      expect(coordinator.permission, NoticePermission.denied);
      service.onOpen!('s9');
      expect(opened, ['s9']);
    });

    test(
      'an approval in the background becomes a notification for its session',
      () async {
        await setUpCoordinator();
        coordinator.setForeground(false);
        events.add(approval('e1', tool: 'bash'));
        await pump();
        final n = service.shown.single;
        expect(n.sessionId, 's1');
        expect(n.title, 'Approval needed');
        expect(n.body, 'Refactor: bash');
      },
    );

    test(
      'a question carries its first question, cut at 120 characters',
      () async {
        await setUpCoordinator();
        coordinator.setForeground(false);
        events.add(question('q1', 'Which branch should I rebase onto?'));
        final long = 'x' * 200;
        events.add(question('q2', long, session: 's2'));
        await pump();
        expect(service.shown.first.title, 'Your agent has a question');
        expect(
          service.shown.first.body,
          'Refactor: Which branch should I rebase onto?',
        );
        expect(
          service.shown.last.body.length,
          'Untitled session: '.length + 120,
        );
        expect(service.shown.last.body, endsWith('…'));
        expect(service.shown.last.sessionId, 's2');
      },
    );

    test('in the foreground nothing is shown, and it is not announced later either', () async {
      await setUpCoordinator();
      events.add(approval('e1'));
      await pump();
      expect(service.shown, isEmpty);
      coordinator.setForeground(false);
      await pump();
      expect(service.shown, isEmpty);
      // A new one after leaving is announced.
      events.add(approval('e2'));
      await pump();
      expect(service.shown, hasLength(1));
    });

    test('the same pending request is announced once', () async {
      await setUpCoordinator();
      coordinator.setForeground(false);
      events.add(approval('e1'));
      events.add(question('q1', 'Hmm?'));
      await pump();
      coordinator.sessionsChanged();
      await pump();
      expect(service.shown, hasLength(2));
      expect(service.shown.map((n) => n.id).toSet(), hasLength(2));
    });

    test(
      'answering or withdrawing a request withdraws its notification',
      () async {
        await setUpCoordinator();
        coordinator.setForeground(false);
        events.add(approval('e1'));
        events.add(approval('e2', session: 's2'));
        await pump();
        final first = service.shown.first.id;
        events.add(const CancelEvent('e1'));
        await pump();
        expect(service.cancelled, [first]);
        // Another connection answered e2: the host cancels it, too.
        events.add(const CancelEvent('e2'));
        await pump();
        expect(service.cancelled, hasLength(2));
      },
    );

    test('returning to the app withdraws every notification', () async {
      await setUpCoordinator();
      coordinator.setForeground(false);
      events.add(approval('e1'));
      await pump();
      coordinator.setForeground(true);
      await pump();
      expect(service.cancelAlls, 1);
    });

    test('turned off, or refused by the system, nothing is shown', () async {
      await setUpCoordinator(enabled: false);
      coordinator.setForeground(false);
      events.add(approval('e1'));
      await pump();
      expect(service.shown, isEmpty);
      coordinator.setEnabled(true);
      events.add(approval('e2'));
      await pump();
      expect(service.shown, hasLength(1));
      await coordinator.dispose();
      await setUpCoordinator(permission: NoticePermission.denied);
      coordinator.setForeground(false);
      events.add(approval('e3'));
      await pump();
      expect(service.shown, isEmpty);
    });

    test('turning it off withdraws what is on screen', () async {
      await setUpCoordinator();
      coordinator.setForeground(false);
      events.add(approval('e1'));
      await pump();
      coordinator.setEnabled(false);
      await pump();
      expect(service.cancelAlls, 1);
    });

    test(
      'the system is asked once, only when the user wants notifications',
      () async {
        await setUpCoordinator(permission: NoticePermission.notDetermined);
        service.answer = NoticePermission.denied;
        await coordinator.requestIfNeeded();
        await coordinator.requestIfNeeded();
        expect(service.requests, 1);
        expect(coordinator.permission, NoticePermission.denied);
        await coordinator.dispose();
        await setUpCoordinator(
          permission: NoticePermission.notDetermined,
          enabled: false,
        );
        await coordinator.requestIfNeeded();
        expect(service.requests, 0);
        coordinator.setEnabled(true);
        await pump();
        expect(service.requests, 1);
      },
    );

    test(
      'keep-alive: only in the background, connected, with sessions running',
      () async {
        await setUpCoordinator();
        running = 2;
        coordinator.sessionsChanged();
        expect(service.keepAlive, isNull, reason: 'in the foreground');
        coordinator.setForeground(false);
        await pump();
        expect(service.keepAlive?.body, contains('2 sessions are running'));
        running = 1;
        coordinator.sessionsChanged();
        await pump();
        expect(service.keepAlive?.body, contains('1 session is running'));
        running = 0;
        coordinator.sessionsChanged();
        await pump();
        expect(service.keepAlive, isNull);
        expect(service.keepAliveLog, ['start', 'start', 'stop']);
      },
    );

    test('keep-alive ends when the app returns, the user opts out, or the host is gone', () async {
      await setUpCoordinator();
      running = 1;
      coordinator.setForeground(false);
      await pump();
      expect(coordinator.keepingAlive, isTrue);
      coordinator.setForeground(true);
      expect(coordinator.keepingAlive, isFalse);
      coordinator.setForeground(false);
      expect(coordinator.keepingAlive, isTrue);
      coordinator.setEnabled(false);
      expect(coordinator.keepingAlive, isFalse);
      coordinator.setEnabled(true);
      expect(coordinator.keepingAlive, isTrue);
      coordinator.setConnected(false);
      expect(coordinator.keepingAlive, isFalse);
    });

    test('no keep-alive without the permission', () async {
      await setUpCoordinator(permission: NoticePermission.denied);
      running = 3;
      coordinator.setForeground(false);
      await pump();
      expect(service.keepAlive, isNull);
    });

    test('dispose stops the service', () async {
      await setUpCoordinator();
      running = 1;
      coordinator.setForeground(false);
      await pump();
      await coordinator.dispose();
      expect(service.keepAlive, isNull);
    });
  });

  group('in the app', () {
    late FakeBackend backend;
    late AppController controller;
    late FakeNotifications notices;

    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 5; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await t.pump();
      }
    }

    Future<void> start(
      WidgetTester t, {
      NoticePermission permission = NoticePermission.granted,
      MemoryLocalPrefs? prefs,
    }) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      backend = FakeBackend();
      notices = FakeNotifications(grant: permission);
      controller = makeController(
        backend,
        prefs: prefs,
        notifications: notices,
      );
      addTearDown(() async {
        controller.dispose();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      });
      await t.pumpWidget(WhaleeApp(controller: controller));
      backend.transport.onList = () async => {
        'items': [listRow('s1', title: 'Task one', running: true)],
      };
      await t.runAsync(() => controller.pair('http://host:1/?token=abc'));
      await settle(t);
    }

    testWidgets(
      'a backgrounded app notifies, and the tap opens that session at its approval',
      (t) async {
        await start(t);
        controller.setForeground(false);
        backend.transport.events.add(approval('ev-1', tool: 'bash'));
        await settle(t);
        expect(notices.shown.single.sessionId, 's1');
        expect(notices.shown.single.body, 'Task one: bash');
        // The connection is kept open while a session runs.
        expect(notices.keepAlive, isNotNull);

        // The user taps the notification: the app comes forward on that session.
        notices.onOpen!('s1');
        controller.setForeground(true);
        await settle(t);
        backend.transport.open(1, snapshot([userMessage(1, 'hi')]));
        await settle(t);
        expect(controller.openSessionId, 's1');
        expect(find.byKey(const ValueKey('approval-panel')), findsOneWidget);
        expect(notices.cancelAlls, greaterThanOrEqualTo(1));
        expect(notices.keepAlive, isNull);
      },
    );

    testWidgets(
      'the OS prompt is shown once after connecting, when the user wants notifications',
      (t) async {
        await start(t, permission: NoticePermission.notDetermined);
        expect(notices.requests, 1);
      },
    );

    testWidgets(
      'with notifications off there is no prompt and no notification',
      (t) async {
        await start(
          t,
          permission: NoticePermission.notDetermined,
          prefs: MemoryLocalPrefs(notificationsEnabled: false),
        );
        expect(notices.requests, 0);
        controller.setForeground(false);
        backend.transport.events.add(approval('ev-1'));
        await settle(t);
        expect(notices.shown, isEmpty);
      },
    );

    testWidgets('the settings switch turns notifications off and persists it', (
      t,
    ) async {
      final prefs = MemoryLocalPrefs();
      await start(t, prefs: prefs);
      await t.tap(find.byKey(const ValueKey('sessions-settings')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('settings-nav-general')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('notifications-switch')));
      await t.tap(find.byKey(const ValueKey('notifications-switch')));
      await t.pumpAndSettle();
      expect(prefs.notificationsEnabled, isFalse);
      controller.setForeground(false);
      backend.transport.events.add(approval('ev-1'));
      await settle(t);
      expect(notices.shown, isEmpty);
    });

    testWidgets(
      'a refused permission is explained with a way to the system settings',
      (t) async {
        await start(t, permission: NoticePermission.denied);
        await t.tap(find.byKey(const ValueKey('sessions-settings')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('settings-nav-general')));
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const ValueKey('notifications-fix')));
        expect(
          find.text(
            'Notifications are blocked for Whalee in the system settings',
          ),
          findsOneWidget,
        );
        await t.tap(find.byKey(const ValueKey('notifications-fix')));
        await t.pump();
        expect(notices.settingsOpens, 1);
      },
    );

    testWidgets('a platform without notifications shows no row', (t) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      backend = FakeBackend();
      notices = FakeNotifications()..supported = false;
      controller = makeController(backend, notifications: notices);
      addTearDown(() async {
        controller.dispose();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      });
      await t.pumpWidget(WhaleeApp(controller: controller));
      backend.transport.onList = () async => {'items': []};
      await t.runAsync(() => controller.pair('http://host:1/?token=abc'));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('sessions-settings')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('settings-nav-general')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('notifications-row')), findsNothing);
    });
  });
}
