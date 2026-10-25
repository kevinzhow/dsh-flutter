import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_models/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump();
  }
}

Map<String, Object?> queued(String id, String text, String rpcId) => {
  'id': id,
  'source': {'kind': 'user', 'rpcId': rpcId},
  'content': [
    {'type': 'text', 'text': text},
  ],
};
void main() {
  testWidgets(
    'busy sends and queue mutations route through app; no queue echo in chat',
    (t) async {
      t.view.physicalSize = const Size(1200, 900);
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
        'items': [listRow('s1', title: 'Synthetic queue')],
      };
      await t.pumpWidget(WhaleeApp(controller: app));
      await t.runAsync(() => app.pair('http://host:18686/?token=abc'));
      await settle(t);
      await openRow(t, 's1');
      await settle(t);
      backend.transport.open(1, snapshot([userMessage(1, 'Earlier')]));
      await settle(t);
      final session = app.openSession!.session;
      session.handleRunning(true);
      await t.enterText(
        find.byKey(const ValueKey('composer-field')),
        'Queue this next',
      );
      await t.pump();
      await t.tap(find.byKey(const ValueKey('composer-send')));
      await settle(t);
      final request = backend.transport.prompts.single;
      final rpcId = request['requestId'] as String;
      expect(request['mode'], 'queue');
      expect(find.byKey(ValueKey('queue-row-$rpcId')), findsOneWidget);
      expect(
        t
            .widgetList<UserBubble>(find.byType(UserBubble))
            .where((b) => b.text == 'Queue this next'),
        isEmpty,
      );
      session.projections.apply('inbox', {
        'next-turn': [queued('durable-q', 'Queue this next', rpcId)],
        'next-step': [],
      }, 2);
      await settle(t);
      expect(session.snapshot.value.pendingSubmissions, isEmpty);
      await t.tap(find.byKey(const ValueKey('queue-edit-durable-q')));
      await t.pump();
      await t.enterText(
        find.byKey(const ValueKey('queue-editor-durable-q')),
        'Edited queue',
      );
      await t.tap(find.byKey(const ValueKey('queue-save-durable-q')));
      await settle(t);
      expect(backend.transport.queueUpdates.last, {
        'sessionId': 's1',
        'itemId': 'durable-q',
        'action': {
          'kind': 'edit',
          'content': [
            {'type': 'text', 'text': 'Edited queue'},
          ],
        },
      });
      await t.tap(find.byKey(const ValueKey('queue-steer-durable-q')));
      await settle(t);
      expect(
        (backend.transport.queueUpdates.last['action'] as Map)['kind'],
        'steer',
      );
      session.projections.apply('inbox', {
        'next-turn': [],
        'next-step': [queued('durable-q', 'Edited queue', rpcId)],
      }, 3);
      await settle(t);
      expect(find.byKey(const ValueKey('queue-panel')), findsNothing);
      expect(
        t
            .widgetList<UserBubble>(find.byType(UserBubble))
            .where((b) => b.text == 'Edited queue' && b.steering),
        hasLength(1),
      );
      app.conversationPreferences.setBusyEnter('steer');
      await t.enterText(
        find.byKey(const ValueKey('composer-field')),
        'Direct steer',
      );
      await t.pump();
      await t.tap(find.byKey(const ValueKey('composer-send')));
      await settle(t);
      expect(backend.transport.prompts.last['mode'], 'steer');
      expect(
        t
            .widgetList<UserBubble>(find.byType(UserBubble))
            .where((b) => b.text == 'Direct steer' && b.steering),
        hasLength(1),
      );
      expect(t.takeException(), isNull);
    },
  );
}
