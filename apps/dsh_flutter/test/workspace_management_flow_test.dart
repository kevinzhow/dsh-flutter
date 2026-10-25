import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<Map<String, Object?>> finished() => [
  rec(1, 'turn/start', data: {'turn': 1}),
  rec(2, 'step/start', data: {'turn': 1, 'step': 1}),
  userMessage(3, 'Synthetic request'),
  rec(
    4,
    'assistant/message',
    data: {
      'turn': 1,
      'step': 1,
      'message': {
        'role': 'assistant',
        'id': 'answer',
        'content': [
          {'type': 'text', 'text': 'Synthetic answer'},
        ],
      },
      'stream': <Object?>[],
    },
    surfaceOp: 'append',
  ),
  rec(5, 'step/end', data: {'turn': 1, 'step': 1}),
  rec(
    6,
    'turn/end',
    data: {
      'turn': 1,
      'reason': {'kind': 'completed'},
    },
  ),
];
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => loadParityFonts(findParityFontsManifest()));
  testWidgets(
    'contributed header actions route rename, pin, guarded archive and undo once',
    (t) async {
      t.view.physicalSize = const Size(1280, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final backend = FakeBackend();
      final app = makeController(backend);
      addTearDown(() async {
        app.dispose();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      });
      backend.transport.onList = () async => {
        'items': [listRow('s1', title: 'Synthetic source')],
      };
      backend.host.handlers['session/rename'] = (_) => {
        'title': 'Normalized fixture',
        'seq': 12,
      };
      backend.host.handlers['workspace/pinSession'] = (_) => {
        'pinnedSessionIds': ['s1'],
      };
      backend.host.handlers['workspace/unarchiveSession'] = (_) => {
        'archivedSessionIds': [],
      };
      backend.host.handlers['workspace/archiveSession'] = (args) {
        final request = args['request'] as Map;
        if (request['stopActivity'] != true) {
          throw RemoteException(
            'workspace/session-active',
            'Active synthetic turn',
            {
              'activity': [
                {'kind': 'turn'},
              ],
            },
          );
        }
        return {
          'archivedSessionIds': ['s1'],
        };
      };
      await t.pumpWidget(WhaleeApp(controller: app));
      await t.runAsync(() => app.pair('http://host:18686/?token=abc'));
      await settle(t);
      backend.emitWorkspaces([]);
      await settle(t);
      await openRow(t, 's1');
      await settle(t);
      backend.transport.open(
        1,
        snapshot(finished(), projections: {'title': 'Synthetic source (2)'}),
      );
      await settle(t);
      Future<void> menu(String action) async {
        await t.tap(find.byKey(const ValueKey('session-overflow')));
        await settle(t);
        await t.tap(find.byKey(ValueKey('dsh-menu-$action')));
        await settle(t);
      }

      await menu('rename');
      await t.enterText(
        find.byKey(const ValueKey('workspace-action-name')),
        '  Draft rename  ',
      );
      await t.pump();
      await t.tap(find.byKey(const ValueKey('workspace-action-confirm')));
      await settle(t);
      expect(backend.host.callsTo('session/rename').single.args, {
        'request': {'sessionId': 's1', 'title': 'Draft rename'},
      });
      expect(
        app.manager!.get('s1').projections.get('title'),
        'Normalized fixture',
      );
      expect(backend.transport.followRequests, hasLength(1));
      await menu('pin');
      expect(backend.host.callsTo('workspace/pinSession'), hasLength(1));
      expect(app.workspaceState.value.pinnedSessionIds, ['s1']);
      await menu('archive');
      expect(backend.host.callsTo('workspace/archiveSession'), hasLength(1));
      expect(app.openSessionId, 's1');
      await t.tap(find.text('Cancel'));
      await settle(t);
      expect(app.openSessionId, 's1');
      await menu('archive');
      await t.tap(find.byKey(const ValueKey('workspace-action-confirm')));
      await settle(t);
      expect(backend.host.callsTo('workspace/archiveSession').last.args, {
        'request': {'sessionId': 's1', 'stopActivity': true},
      });
      expect(app.openSessionId, isNull);
      expect(app.workspaceState.value.archivedSessionIds, ['s1']);
      await t.tap(find.text('Unarchive session'));
      await settle(t);
      expect(app.workspaceState.value.archivedSessionIds, isEmpty);
      expect(
        app.openSessionId,
        isNull,
      ); // undo restores the row, not a surprise navigation
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'sidebar content search calls the Host and opens its existing session',
    (t) async {
      t.view.physicalSize = const Size(1280, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final backend = FakeBackend();
      final app = makeController(backend);
      addTearDown(() async {
        app.dispose();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      });
      backend.transport.onList = () async => {
        'items': [listRow('s1', title: 'Unrelated title')],
      };
      backend.host.handlers['session/search'] = (_) => {
        'items': [
          {'sessionId': 's1', 'snippet': 'Synthetic indexed content'},
        ],
        'hasMore': false,
      };
      await t.pumpWidget(WhaleeApp(controller: app));
      await t.runAsync(() => app.pair('http://host:18686/?token=abc'));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('browser-search')));
      await settle(t);
      await t.enterText(
        find.byKey(const ValueKey('browser-search-input')),
        'indexed',
      );
      await settle(t);
      expect(backend.host.callsTo('session/search').single.args, {
        'request': {'query': 'indexed'},
      });
      expect(find.text('Synthetic indexed content'), findsOneWidget);
      await t.tap(find.text('Unrelated title'));
      await settle(t);
      expect(app.openSessionId, 's1');
      expect(backend.transport.followRequests, hasLength(1));
      expect(find.byKey(const ValueKey('browser-search-input')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'footer fork uses completed event boundary and opens the normalized child',
    (t) async {
      t.view.physicalSize = const Size(1280, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final backend = FakeBackend();
      final AppController app = makeController(backend);
      addTearDown(() async {
        app.dispose();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      });
      backend.transport.onList = () async => {
        'items': [listRow('s1', title: 'Synthetic source (2)')],
      };
      backend.host.handlers['session/fork'] = (_) => {'sessionId': 'child'};
      backend.host.handlers['session/rename'] = (_) => {
        'title': 'Synthetic source (3)',
        'seq': 20,
      };
      await t.pumpWidget(WhaleeApp(controller: app));
      await t.runAsync(() => app.pair('http://host:18686/?token=abc'));
      await settle(t);
      await openRow(t, 's1');
      await settle(t);
      backend.transport.open(
        1,
        snapshot(finished(), projections: {'title': 'Synthetic source (2)'}),
      );
      await settle(t);
      final branch = find.byKey(const ValueKey('message-branch'));
      expect(branch, findsOneWidget);
      await t.tap(branch);
      await settle(t);
      expect(backend.host.callsTo('session/fork').single.args, {
        'request': {'sessionId': 's1', 'atSeq': 6, 'allowMigration': true},
      });
      expect(backend.host.callsTo('session/rename').single.args, {
        'request': {'sessionId': 'child', 'title': 'Synthetic source (3)'},
      });
      expect(app.openSessionId, 'child');
      expect(app.manager!.summaryOf('child')!.parentSessionId, 's1');
      expect(
        app.manager!.get('child').projections.get('title'),
        'Synthetic source (3)',
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
}
