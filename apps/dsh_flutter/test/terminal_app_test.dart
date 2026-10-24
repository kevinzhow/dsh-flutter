import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_models/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late FakeBackend backend;
  late AppController controller;

  Future<void> openSession(
    WidgetTester t, {
    Size size = const Size(560, 800),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    backend = FakeBackend();
    controller = makeController(backend);
    addTearDown(() async {
      controller.dispose();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    });
    await t.pumpWidget(WhaleeApp(controller: controller));
    backend.transport.onList = () async => {
      'items': [listRow('s1', title: 'Task one')],
    };
    await t.runAsync(() => controller.pair('http://host:18686/?token=abc'));
    await settle(t);
    await openRow(t, 's1');
    await settle(t);
    backend.transport.open(1, snapshot([userMessage(1, 'Earlier question')]));
    await settle(t);
  }

  testWidgets('the sidebar opens a terminal from the guide and closes it', (
    t,
  ) async {
    await openSession(t);
    await t.tap(find.byKey(const ValueKey('sidebar-open')));
    await t.pumpAndSettle();
    // The surface seeds its guide on first opening: the cards are there.
    expect(find.text('New terminal'), findsOneWidget);
    expect(find.text('Workspace files'), findsOneWidget);
    await t.tap(find.text('New terminal'));
    await settle(t);
    final fake = backend.terminals;
    final create = fake.host.callsTo('terminal/create').single.args;
    expect(create['agentId'], 's1');
    fake.attach.start(
      1,
      terminalSnapshot(
        screen: 'hello from the host',
        info: terminalInfo(
          id: (create['request']! as Map<String, Object?>)['id']! as String,
        ),
      ),
    );
    await settle(t);
    expect(find.byKey(const ValueKey('terminal-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('terminal-key-bar')), findsOneWidget);
    // Closing the tab ends the Host terminal in the background.
    final close = find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> && k.value.startsWith('dock-close-');
    });
    expect(close, findsOneWidget);
    await t.tap(close);
    await settle(t);
    expect(fake.host.callsTo('terminal/close'), hasLength(1));
    expect(find.byKey(const ValueKey('terminal-screen')), findsNothing);
  });

  testWidgets('a timed question counts down in the composer', (t) async {
    await openSession(t, size: const Size(1200, 800));
    backend.transport.events.add(
      const WaterfallEvent(
        generation: 1,
        event: 'user-questions/request',
        eventId: 'e1',
        agentId: 's1',
        request: {
          'questions': [
            {
              'id': 'q1',
              'question': 'Which colour?',
              'options': [
                {'label': 'Red'},
                {'label': 'Blue'},
              ],
            },
          ],
          'wait': {'callId': 'c1', 'timed': true},
        },
      ),
    );
    await settle(t);
    // The client claims the wait first; the Host answers with the remaining time.
    expect(backend.claims.single.$1, 'c1');
    backend.claims.single.$2.add(const Duration(seconds: 20));
    await settle(t);
    expect(find.text('Which colour?'), findsOneWidget);
    expect(find.text('Continuing in 20s'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('question-take-time')));
    await settle(t);
    expect(find.text('Waiting until you answer'), findsOneWidget);
  });
}
