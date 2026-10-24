import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_workspace.dart' as ws;
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

import 'support/fake_transport.dart';

ws.WorkspaceView view(
  String id, {
  List<String> sessions = const [],
  String? created,
}) => ws.WorkspaceView(
  workspaceId: id,
  path: '/work/$id',
  title: id,
  sessionIds: sessions,
  createdAt: created ?? '2026-10-01T00:00:00.000Z',
  updatedAt: '2026-10-01T00:00:00.000Z',
);

Map<String, Object?> row(
  String id,
  String cwd, {
  num updatedAt = 1,
  bool blank = false,
}) => {
  'sessionId': id,
  'updatedAt': updatedAt,
  'agentAvailable': false,
  'running': false,
  'blank': blank,
  'cwd': cwd,
};

SessionSummary summary(String id, num updatedAt) => SessionSummary(
  sessionId: id,
  updatedAt: updatedAt,
  running: false,
  blank: false,
  agentAvailable: false,
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('recentWorkspace', () {
    test(
      'the latest session activity wins, then the creation time, then order',
      () {
        final items = [
          view('a', sessions: ['s1'], created: '2026-10-01T00:00:00.000Z'),
          view('b', sessions: ['s2'], created: '2026-10-01T00:00:00.000Z'),
          view('c', created: '2026-10-09T00:00:00.000Z'),
        ];
        expect(
          WorkspaceNavigation.recentWorkspace(items, {
            's1': summary('s1', 5),
            's2': summary('s2', 9),
          }),
          // c has no listed session: its creation (2026-10-09, in ms) is later.
          'c',
        );
        expect(
          WorkspaceNavigation.recentWorkspace(items.take(2).toList(), {
            's1': summary('s1', 5),
            's2': summary('s2', 9),
          }),
          'b',
        );
        expect(
          WorkspaceNavigation.recentWorkspace(items.take(2).toList(), {
            's1': summary('s1', 7),
            's2': summary('s2', 7),
          }),
          'a',
        );
        expect(WorkspaceNavigation.recentWorkspace(const [], const {}), isNull);
      },
    );
  });

  group('navigation', () {
    late FakeHost host;
    late FakeTransport transport;
    late SessionManager sessions;
    late StreamController<GenerationFrame> frames;
    late WorkspaceList workspaces;
    late WorkspaceNavigation nav;
    String? current;
    late List<String> shown;
    late List<String> events;
    late List<Object> failures;

    void baseline(
      List<ws.WorkspaceView> items, {
      List<String> archived = const [],
    }) => frames.add(
      StreamItem(1, {
        'type': 'baseline',
        'value': {
          'items': [for (final w in items) w.toJson()],
          'archivedSessionIds': archived,
          'pinnedSessionIds': <String>[],
        },
      }),
    );

    Future<void> list(List<Map<String, Object?>> rows) async {
      transport.onList = () async => {'items': rows};
      await sessions.refreshList();
    }

    setUp(() {
      host = FakeHost();
      transport = FakeTransport();
      sessions = SessionManager(transport);
      frames = StreamController<GenerationFrame>.broadcast(sync: true);
      workspaces = WorkspaceList(
        remote: host.remotes.workspace,
        follow: () => frames.stream,
      )..start();
      current = null;
      shown = [];
      events = [];
      failures = [];
      nav = WorkspaceNavigation(
        workspaces: workspaces,
        sessions: sessions,
        current: () => current,
        show: (id) async => shown.add(id),
        clear: () => events.add('clear'),
        onFailure: failures.add,
      );
    });

    tearDown(() async {
      await workspaces.dispose();
      await sessions.dispose();
      await frames.close();
      await host.close();
    });

    test(
      'plus with an explicit workspace creates a fresh session in it',
      () async {
        baseline([view('a'), view('b')]);
        await list([]);
        transport.onCreate = (_) async => {'sessionId': 'fresh'};
        await nav.startSession('b');
        expect(transport.createRequests, [
          {'workspaceId': 'b'},
        ]);
        expect(shown, ['fresh']);
      },
    );

    test('plus without one follows the session in view', () async {
      baseline([
        view('a', sessions: ['s1']),
        view('b'),
      ]);
      await list([row('s1', '/work/a', updatedAt: 1)]);
      current = 's1';
      await nav.startSession();
      expect(transport.createRequests.single['workspaceId'], 'a');
    });

    test('plus with nothing in view takes the most recent workspace', () async {
      baseline([
        view('a', sessions: ['s1']),
        view('b', sessions: ['s2']),
      ]);
      await list([
        row('s1', '/work/a', updatedAt: 3),
        row('s2', '/work/b', updatedAt: 8),
      ]);
      await nav.startSession();
      expect(transport.createRequests.single['workspaceId'], 'b');
    });

    test(
      'plus while the lists are still pending waits for no one: it clears',
      () async {
        // Workspace phase pending: no baseline yet.
        await nav.startSession();
        expect(events, ['clear']);
        expect(transport.createRequests, isEmpty);
      },
    );

    test(
      'plus with no workspace at all clears the view to the chooser',
      () async {
        baseline(const []);
        await list([]);
        await nav.startSession();
        expect(events, ['clear']);
        expect(shown, isEmpty);
      },
    );

    test('picking from the hero reuses the first reusable blank of the workspace', () async {
      baseline(
        [
          view('a', sessions: ['old', 'blank1', 'blank2']),
        ],
        archived: ['blank1'],
      );
      await list([
        row('old', '/work/a'),
        row('blank1', '/work/a', blank: true),
        row('blank2', '/work/a', blank: true),
      ]);
      transport.onCreate = (r) async => {'sessionId': r['sessionId'] ?? 'x'};
      final carried = <String>[];
      await nav.openWorkspace('a', beforeOpen: carried.add);
      // The archived blank is passed over; the Host is asked for the next one.
      expect(transport.createRequests.single, {
        'workspaceId': 'a',
        'sessionId': 'blank2',
      });
      expect(carried, ['blank2']);
      expect(shown, ['blank2']);
    });

    test(
      'a workspace with no blank gets a new session, nothing named',
      () async {
        baseline([
          view('a', sessions: ['old']),
        ]);
        await list([row('old', '/work/a')]);
        transport.onCreate = (_) async => {'sessionId': 'made'};
        await nav.openWorkspace('a');
        expect(transport.createRequests.single, {'workspaceId': 'a'});
        expect(shown, ['made']);
      },
    );

    test(
      'the Host may decline the named blank and answer another session',
      () async {
        baseline([
          view('a', sessions: ['b1']),
        ]);
        await list([row('b1', '/work/a', blank: true)]);
        transport.onCreate = (_) async => {'sessionId': 'other'};
        await nav.openWorkspace('a');
        expect(shown, ['other']);
      },
    );

    test('two picks of one workspace in flight share one creation', () async {
      baseline([view('a')]);
      await list([]);
      final gate = Completer<Map<String, Object?>>();
      transport.onCreate = (_) => gate.future;
      final first = nav.openWorkspace('a');
      final second = nav.connectWorkspace('a');
      expect(transport.createRequests, hasLength(1));
      gate.complete({'sessionId': 'one'});
      await first;
      expect(await second, 'one');
    });

    test('a newer pick supersedes a pending one', () async {
      baseline([view('a'), view('b')]);
      await list([]);
      final gates = <String, Completer<Map<String, Object?>>>{};
      transport.onCreate = (r) =>
          (gates[r['workspaceId']! as String] = Completer()).future;
      final first = nav.openWorkspace('a');
      final second = nav.openWorkspace('b');
      gates['b']!.complete({'sessionId': 'sb'});
      await second;
      gates['a']!.complete({'sessionId': 'sa'});
      await first;
      expect(shown, ['sb']);
    });

    test('a failed creation reports once and throws', () async {
      baseline([view('a')]);
      await list([]);
      transport.onCreate = (_) async => throw RemoteException('x/y', 'denied');
      await expectLater(nav.startSession('a'), throwsA(isA<RemoteException>()));
      expect(failures, hasLength(1));
      expect(shown, isEmpty);
    });

    test('an unknown workspace is a failure, not a request', () async {
      baseline([view('a')]);
      await list([]);
      await expectLater(nav.openWorkspace('gone'), throwsStateError);
      expect(transport.createRequests, isEmpty);
    });
  });
}
