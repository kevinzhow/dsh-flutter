import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

import 'support/fake_transport.dart';

Map<String, Object?> row(
  String id, {
  num updatedAt = 1,
  bool running = false,
  bool blank = false,
  Map<String, Object?>? projections,
}) => {
  'sessionId': id,
  'updatedAt': updatedAt,
  'agentAvailable': false,
  'running': running,
  'blank': blank,
  'cwd': '/ws',
  if (projections != null) 'projections': projections,
};

List<String> ids(SessionManager m) =>
    m.list.value.items.map((e) => e.sessionId).toList();

void main() {
  late FakeTransport t;
  late SessionManager m;

  setUp(() {
    t = FakeTransport();
    m = SessionManager(t);
  });
  tearDown(() => m.dispose());

  test(
    'refreshList loads the baseline in host order and lands list blocks',
    () async {
      t.onList = () async => {
        'items': [
          row(
            'a',
            projections: {
              'kind': 'cached',
              'asOfSeq': 4,
              'values': {'title': 'Alpha'},
            },
          ),
          row(
            'b',
            projections: {
              'kind': 'sequenced',
              'asOfSeq': 9,
              'values': {'title': 'Beta'},
            },
          ),
        ],
      };
      await m.refreshList();
      expect(ids(m), ['a', 'b']);
      expect(m.list.value.phase, ListPhase.ready);
      expect(m.list.value.items.map((e) => e.title), ['Alpha', 'Beta']);
    },
  );

  test(
    'live events during an in-flight pull are replayed over the baseline',
    () async {
      final gate = Completer<Map<String, Object?>>();
      t.onList = () => gate.future;
      final pull = m.refreshList();
      m.handleSessionAdded(SessionSummary.fromWire(row('new', updatedAt: 50)));
      m.handleSessionStatus('a', true);
      m.handleSessionRemoved('gone');
      gate.complete({
        'items': [row('a'), row('gone'), row('b')],
      });
      await pull;
      expect(ids(m), [
        'new',
        'a',
        'b',
      ], reason: 'removal wins, the added row survives the pull');
      expect(
        m.list.value.items
            .firstWhere((e) => e.sessionId == 'a')
            .summary
            .running,
        isTrue,
      );
    },
  );

  test('a later pull keeps the established order and inserts newcomers by neighbours', () async {
    t.onList = () async => {
      'items': [row('a'), row('b'), row('c')],
    };
    await m.refreshList();
    // the host now lists a newcomer first and reorders; the client keeps its order
    t.onList = () async => {
      'items': [row('n'), row('c'), row('b'), row('a')],
    };
    await m.refreshList();
    expect(ids(m), ['a', 'b', 'n', 'c']);
  });

  test('mergeOrderedBaseline keeps current relative order', () {
    expect(
      mergeOrderedBaseline<String>(
        ['x', 'y', 'z'],
        ['z', 'n', 'y', 'q'],
        (s) => s,
      ),
      ['n', 'y', 'z', 'q'],
    );
  });

  test('activity only moves updatedAt forward; blank only lowers', () {
    final a = SessionSummary.fromWire(row('a', updatedAt: 10, blank: true));
    var l = applyMutation([a], const ActivityMutation('a', 5));
    expect(l.single.updatedAt, 10);
    l = applyMutation(l, const ActivityMutation('a', 20));
    expect(l.single.updatedAt, 20);
    l = applyMutation(
      l,
      UpsertMutation(SessionSummary.fromWire(row('a', blank: false))),
    );
    expect(l.single.blank, isFalse);
    l = applyMutation(
      l,
      UpsertMutation(SessionSummary.fromWire(row('a', blank: true))),
    );
    expect(
      l.single.blank,
      isFalse,
      reason: 'a stale blank=true never re-hides',
    );
  });

  test(
    'forwarded api-session events and control frames drive the manager',
    () async {
      m.start();
      t.events.add(EmitEvent('api-session/added', [row('s1', blank: true)]));
      await pump();
      expect(ids(m), ['s1']);
      t.events.add(EmitEvent('api-session/status', ['s1', true]));
      t.events.add(EmitEvent('api-session/activity', ['s1', 99]));
      await pump();
      final s = m.list.value.items.single.summary;
      expect([s.running, s.blank, s.updatedAt], [true, false, 99]);
      expect(m.get('s1').snapshot.value.running, isTrue);

      t.controlController.add(
        StreamItem(1, {
          'type': 'baseline',
          'value': {
            'projections': {
              's1': {
                'asOfSeq': 5,
                'values': {'title': 'Hello'},
              },
            },
          },
        }),
      );
      await pump();
      expect(m.list.value.items.single.title, 'Hello');
      t.controlController.add(
        StreamItem(1, {
          'type': 'projection',
          'sessionId': 's1',
          'key': 'title',
          'value': 'Newer',
          'seq': 7,
        }),
      );
      t.controlController.add(
        StreamItem(1, {
          'type': 'projection',
          'sessionId': 's1',
          'key': 'title',
          'value': 'Stale',
          'seq': 6,
        }),
      );
      await pump();
      expect(
        m.list.value.items.single.title,
        'Newer',
        reason: 'higher seq wins',
      );

      t.events.add(EmitEvent('api-session/error', ['s1', 'boom']));
      t.events.add(EmitEvent('api-session/removed', ['s1']));
      await pump();
      expect(m.get('s1').snapshot.value.lastAgentError, 'boom');
      expect(m.get('s1').snapshot.value.removed, isTrue);
      expect(ids(m), isEmpty);
    },
  );

  test('a new generation refetches the baseline', () async {
    var pulls = 0;
    t.onList = () async {
      pulls++;
      return {
        'items': [row('a')],
      };
    };
    m.start();
    t.gens.add(null);
    await pump();
    expect(pulls, 0);
    t.gens.add(_FakeGeneration.instance);
    await pump();
    expect(pulls, 1);
  });

  test('create places a row and returns the resident session', () async {
    final s = await m.create(cwd: '/ws');
    expect(s.sessionId, 'new-session');
    expect(ids(m), ['new-session']);
    expect(identical(m.get('new-session'), s), isTrue);
  });

  test('ClientSessions reference-counts bindings and opens once', () async {
    final sessions = ClientSessions(m);
    final a = sessions.bind('s1');
    final b = sessions.bind('s1');
    await pump();
    expect(sessions.referenceCount('s1'), 2);
    expect(t.follows.length, 1, reason: 'one follow for two bindings');
    a.release();
    a.release();
    expect(sessions.referenceCount('s1'), 1);
    b.release();
    expect(sessions.referenceCount('s1'), 0);
  });
}

/// Generations are only published, never inspected, by the manager.
class _FakeGeneration implements ConnectionGeneration {
  static final instance = _FakeGeneration();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
