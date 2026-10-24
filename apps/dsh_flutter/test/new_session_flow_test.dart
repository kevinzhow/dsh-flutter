import 'package:dsh_client/dsh_client.dart' show RemoteException, StreamItem;
import 'package:dsh_feature_conversation/dsh_feature_conversation.dart'
    show ComposerCard;
import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// New session end to end over the whole app: the workspace list, the hero of
/// a blank session, the picker, the directory browser and the first message,
/// with a scripted host behind them.
void main() {
  late FakeBackend backend;
  late AppController controller;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump();
    }
  }

  Map<String, Object?> workspace(
    String id,
    String title, {
    List<String> sessions = const [],
  }) => {
    'workspaceId': id,
    'path': '/work/$title',
    'title': title,
    'sessionIds': sessions,
    'createdAt': '2026-10-01T00:00:00.000Z',
    'updatedAt': '2026-10-01T00:00:00.000Z',
  };

  Future<void> start(
    WidgetTester t, {
    Size size = const Size(400, 800),
    DshLocale locale = DshLocale.en,
    List<Map<String, Object?>> workspaces = const [],
    List<Map<String, Object?>> sessions = const [],
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    backend = FakeBackend();
    backend.host.handlers['commands/list'] = (_) => const <Object?>[];
    backend.host.handlers['workspace/initializeDefault'] = (_) => null;
    controller = makeController(backend, locale: locale);
    addTearDown(() async {
      controller.dispose();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    });
    await t.pumpWidget(WhaleeApp(controller: controller));
    backend.transport.onList = () async => {'items': sessions};
    await t.runAsync(() => controller.pair('http://host:18686/?token=abc'));
    backend.emitWorkspaces(workspaces);
    await settle(t);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  /// The Host registers a created session with its workspace and says so on the
  /// follow stream, as it does in the same call that answers `session/create`.
  void registered(String wsId, String title, List<String> sessions) =>
      backend.workspaceFrames.add(
        StreamItem(1, {
          'type': 'upsert',
          'workspace': workspace(wsId, title, sessions: sessions),
        }),
      );

  Future<void> openBlank(WidgetTester t) async {
    await settle(t);
    backend.transport.open(1, snapshot(const []));
    await settle(t);
  }

  testWidgets(
    'plus opens a blank session in the most recent workspace and shows the hero',
    (t) async {
      await start(
        t,
        workspaces: [
          workspace('wa', 'alpha', sessions: ['s1']),
          workspace('wb', 'beta'),
        ],
        sessions: [listRow('s1', title: 'Task one', cwd: '/work/alpha')],
      );
      backend.transport.onCreate = (_) async {
        registered('wa', 'alpha', ['s1', 'blank1']);
        return {'sessionId': 'blank1'};
      };
      await t.tap(key('sessions-new'));
      await openBlank(t);
      expect(backend.transport.createRequests, [
        {'workspaceId': 'wa'},
      ]);
      expect(key('hero'), findsOneWidget);
      expect(find.text('Into the Unknown'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('Choose workspace'), findsNothing);
      // The chip names the workspace of the session; its composer says what to do.
      expect(
        find.descendant(
          of: key('hero-workspace-chip'),
          matching: find.text('alpha'),
        ),
        findsOneWidget,
      );
      expect(
        t.widget<TextField>(find.byType(TextField).last).decoration!.hintText,
        startsWith('Describe what you want to build'),
      );
    },
  );

  testWidgets(
    'choosing another workspace moves the draft to its blank session',
    (t) async {
      await start(
        t,
        workspaces: [
          workspace('wa', 'alpha', sessions: ['s1']),
          workspace('wb', 'beta', sessions: ['b0']),
        ],
        sessions: [
          listRow('s1', title: 'Task one', cwd: '/work/alpha'),
          listRow('b0', cwd: '/work/beta', blank: true),
        ],
      );
      backend.transport.onCreate = (r) async {
        final id = (r['sessionId'] as String?) ?? 'blank1';
        if (r['workspaceId'] == 'wa') registered('wa', 'alpha', ['s1', id]);
        return {'sessionId': id};
      };
      await t.tap(key('sessions-new'));
      await openBlank(t);
      await t.enterText(find.byType(EditableText).last, 'hello there');
      await settle(t);

      await t.tap(key('hero-workspace-chip'));
      await settle(t);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('beta'), findsOneWidget);
      await t.tap(find.text('beta'));
      await settle(t);
      await t.pump(const Duration(milliseconds: 600));
      // beta already has a blank session: the Host is asked to reuse it.
      expect(backend.transport.createRequests.last, {
        'workspaceId': 'wb',
        'sessionId': 'b0',
      });
      backend.transport.open(1, snapshot(const []));
      await settle(t);
      final field = t.widget<EditableText>(find.byType(EditableText).last);
      expect(field.controller.text, 'hello there');
      expect(controller.openSessionId, 'b0');
    },
  );

  testWidgets(
    'with no workspace the New session screen asks for one; adding a folder runs the whole flow to the first message',
    (t) async {
      await start(t);
      backend.host.handlers['directoryPicker/list'] = (args) => {
        'path': '/home/u',
        'home': '/home/u',
        'crumbs': [
          {'name': '/', 'path': '/', 'hidden': false},
          {'name': 'home', 'path': '/home', 'hidden': false},
          {'name': 'u', 'path': '/home/u', 'hidden': false},
        ],
        'entries': [
          {'name': 'proj', 'path': '/home/u/proj', 'hidden': false},
        ],
        'truncated': false,
      };
      backend.host.handlers['workspace/create'] = (_) {
        backend.emitWorkspaces([workspace('wn', 'proj', sessions: [])]);
        return {'workspace': workspace('wn', 'proj'), 'created': true};
      };
      backend.transport.onCreate = (_) async {
        registered('wn', 'proj', ['first']);
        return {'sessionId': 'first'};
      };

      await t.tap(key('sessions-new'));
      await settle(t);
      // Nothing to default to: the screen asks for a workspace first.
      expect(key('new-session'), findsOneWidget);
      expect(find.text('Choose workspace'), findsOneWidget);
      expect(key('inert-composer'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(backend.transport.createRequests, isEmpty);

      // With no workspace listed the chip IS the add action: the browser opens.
      await t.tap(key('hero-workspace-chip'));
      await settle(t);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Select Workspace Directory'), findsOneWidget);
      await t.tap(key('row-/home/u/proj'));
      await settle(t);
      await t.tap(key('directory-open'));
      await settle(t);
      await t.pump(const Duration(milliseconds: 600));
      expect(backend.host.callsTo('workspace/create').single.args['request'], {
        'path': '/home/u/proj',
      });
      expect(backend.transport.createRequests.single, {'workspaceId': 'wn'});
      backend.transport.open(1, snapshot(const []));
      await settle(t);
      expect(key('hero'), findsOneWidget);
      expect(
        find.descendant(
          of: key('hero-workspace-chip'),
          matching: find.text('proj'),
        ),
        findsOneWidget,
      );

      // The first message goes to the new session.
      await t.enterText(find.byType(EditableText).last, 'build it');
      await settle(t);
      await t.tap(key('composer-send'));
      await settle(t);
      expect(
        ((backend.transport.prompts.single['content']! as List).single
            as Map)['text'],
        'build it',
      );
    },
  );

  testWidgets(
    'a folder the Host refuses opens the error dialog with its message',
    (t) async {
      await start(t);
      backend.host.handlers['directoryPicker/list'] = (args) => {
        'path': '/home/u',
        'home': '/home/u',
        'crumbs': [
          {'name': 'u', 'path': '/home/u', 'hidden': false},
        ],
        'entries': <Object?>[],
        'truncated': false,
      };
      backend.host.handlers['workspace/create'] = (_) =>
          throw RemoteException('workspace/invalid-path', 'Not a directory');
      await t.tap(key('sessions-new'));
      await settle(t);
      await t.tap(key('hero-workspace-chip'));
      await settle(t);
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(key('directory-open'));
      await settle(t);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Couldn’t open folder'), findsOneWidget);
      expect(find.text('Not a directory'), findsOneWidget);
      expect(backend.transport.createRequests, isEmpty);
    },
  );

  testWidgets('a creation the Host refuses is reported on the list', (t) async {
    await start(t, workspaces: [workspace('wa', 'alpha')], sessions: const []);
    backend.transport.onCreate = (_) async =>
        throw RemoteException('session/create-failed', 'disk full');
    await t.tap(key('sessions-new'));
    await settle(t);
    expect(controller.createError, isA<RemoteException>());
    expect(key('create-error'), findsOneWidget);
  });

  testWidgets('a wide window shows the New session screen in the detail pane', (
    t,
  ) async {
    await start(t, size: const Size(1100, 800));
    await t.tap(key('sessions-new'));
    await settle(t);
    expect(key('new-session'), findsOneWidget);
    // The list stays beside it.
    expect(key('sessions-title'), findsOneWidget);
    // Wide: the stack is centered with the headline above the chip.
    final head = t.getTopLeft(key('hero-headline'));
    final chip = t.getTopLeft(key('hero-workspace-chip'));
    expect(head.dy, lessThan(chip.dy));
  });

  testWidgets('the hero speaks Chinese', (t) async {
    await start(
      t,
      locale: DshLocale.zh,
      workspaces: [
        workspace('wa', 'alpha', sessions: ['s1']),
      ],
      sessions: [listRow('s1', cwd: '/work/alpha')],
    );
    backend.transport.onCreate = (_) async {
      registered('wa', 'alpha', ['s1', 'blank1']);
      return {'sessionId': 'blank1'};
    };
    await t.tap(key('sessions-new'));
    await openBlank(t);
    expect(find.text('探索未至之境'), findsOneWidget);
    expect(find.text('预览版'), findsOneWidget);
  });

  testWidgets(
    'the / menu of the hero rises above the card, keyboard up or not',
    (t) async {
      await start(
        t,
        workspaces: [
          workspace('wa', 'alpha', sessions: ['s1']),
        ],
        sessions: [listRow('s1', title: 'Task one', cwd: '/work/alpha')],
      );
      backend.host.handlers['commands/list'] = (_) => [
        for (final n in ['compact', 'goal', 'plan', 'feedback', 'export'])
          {'name': n, 'description': 'The $n command', 'definitionId': '@x/$n'},
      ];
      backend.transport.onCreate = (_) async {
        registered('wa', 'alpha', ['s1', 'blank1']);
        return {'sessionId': 'blank1'};
      };
      await t.tap(key('sessions-new'));
      await openBlank(t);
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await settle(t);
      await t.tap(find.byType(EditableText).last);
      await t.enterText(find.byType(EditableText).last, '/');
      await settle(t);
      await t.pump(const Duration(milliseconds: 300));
      final menu = t.getRect(key('trigger-menu-surface'));
      final card = t.getRect(find.byType(ComposerCard));
      expect(menu.bottom, closeTo(card.top - 4, 1));
      expect(menu.top, greaterThanOrEqualTo(60));
      // The keyboard took 300px: the card rode up with the hero.
      expect(card.bottom, lessThan(500));
      expect(menu.left, 16);
      expect(menu.right, 384);
    },
  );
}
