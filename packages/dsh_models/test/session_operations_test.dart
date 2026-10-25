import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

void main() {
  late FakeHost host;
  late FakeTransport transport;
  late SessionManager manager;
  setUp(() {
    host = FakeHost();
    transport = FakeTransport();
    manager = SessionManager(transport, operations: host.remotes.session);
    manager.handleSessionAdded(
      const SessionSummary(
        sessionId: 'source',
        updatedAt: 10,
        running: false,
        blank: false,
        agentAvailable: true,
        cwd: '/synthetic',
      ),
    );
    manager.get('source').projections.apply('title', 'Fixture (2)', 2);
  });
  tearDown(() async {
    await manager.dispose();
    await host.close();
  });
  test(
    'rename accepts Host title without following and respects newer projection',
    () async {
      final response = Completer<Object?>();
      host.handlers['session/rename'] = (_) => response.future;
      final rename = manager.rename('source', 'New');
      manager.get('source').projections.apply('title', 'Newer', 15);
      response.complete({'title': 'Normalized', 'seq': 12});
      await rename;
      expect(manager.list.value.items.single.title, 'Newer');
      expect(transport.followRequests, isEmpty);
    },
  );
  test(
    'fork publishes before rename and keeps child if its naming fails',
    () async {
      host.handlers['session/fork'] = (_) => {'sessionId': 'child'};
      host.handlers['session/rename'] = (_) {
        expect(
          manager.list.value.items.any((r) => r.sessionId == 'child'),
          true,
        );
        throw RemoteException(
          'session/rename-failed',
          'Synthetic rename refused',
        );
      };
      await expectLater(
        manager.fork('source', atSeq: 7),
        throwsA(isA<RemoteException>()),
      );
      final child = manager.list.value.items.firstWhere(
        (r) => r.sessionId == 'child',
      );
      expect(child.summary.parentSessionId, 'source');
      expect(child.summary.cwd, '/synthetic');
      expect(host.callsTo('session/fork').single.args, {
        'request': {'sessionId': 'source', 'atSeq': 7, 'allowMigration': false},
      });
      expect(host.callsTo('session/rename').single.args, {
        'request': {'sessionId': 'child', 'title': 'Fixture (3)'},
      });
      expect(transport.followRequests, isEmpty);
    },
  );
  test(
    'attachment refusal preserves published fork without trying again',
    () async {
      host.handlers['session/fork'] = (_) => throw RemoteException(
        'session/workspace-attach-failed',
        'Synthetic attach refused',
        {'sessionId': 'published'},
      );
      await expectLater(
        manager.fork('source'),
        throwsA(isA<RemoteException>()),
      );
      expect(manager.list.value.items.first.summary.parentSessionId, 'source');
      expect(manager.list.value.items.first.sessionId, 'published');
      expect(host.callsTo('session/fork'), hasLength(1));
      expect(host.callsTo('session/rename'), isEmpty);
    },
  );
  test('fork title count preserves parentheses and arbitrary precision', () {
    expect(increasedForkTitle('Fixture'), 'Fixture (1)');
    expect(increasedForkTitle('Fixture（9）'), 'Fixture（10）');
    expect(
      increasedForkTitle('Fixture (999999999999999999999)'),
      'Fixture (1000000000000000000000)',
    );
  });
}
