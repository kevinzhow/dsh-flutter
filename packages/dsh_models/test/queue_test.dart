import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

Map<String, Object?> row(String id, String requestId) => {
  'id': id,
  'source': {'kind': 'user', 'rpcId': requestId},
  'content': [
    {'type': 'text', 'text': 'queued text'},
  ],
};
void main() {
  late FakeTransport transport;
  late Session session;
  setUp(() {
    transport = FakeTransport();
    session = Session('s', transport);
  });
  tearDown(() => session.dispose());

  test('placement captured at send; inbox admission retires queued echo, not steering', () async {
    session.handleRunning(true);
    await session.prompt('next');
    await session.prompt('interrupt', mode: 'steer');
    final pending = session.snapshot.value.pendingSubmissions;
    expect(pending.map((p) => p.placement), [
      SubmissionPlacement.queued,
      SubmissionPlacement.steering,
    ]);
    session.handleRunning(false);
    session.projections.apply('inbox', {
      'next-turn': [row('a', pending[0].requestId)],
      'next-step': [row('b', pending[1].requestId)],
    }, 10);
    expect(session.snapshot.value.pendingSubmissions.map((p) => p.text), [
      'interrupt',
    ]);
    expect(
      session.snapshot.value.pendingSubmissions.single.placement,
      SubmissionPlacement.steering,
    );
    expect(transport.prompts.map((p) => p['mode']), ['queue', 'steer']);
  });

  test(
    'idle submission remains transcript despite transient next-turn admission',
    () async {
      await session.prompt('idle');
      final pending = session.snapshot.value.pendingSubmissions.single;
      session.projections.apply('inbox', {
        'next-turn': [row('a', pending.requestId)],
      }, 10);
      expect(
        session.snapshot.value.pendingSubmissions.single.placement,
        SubmissionPlacement.transcript,
      );
    },
  );

  test('durable insertion retires queued echo even if inserted and claimed between projections', () async {
    final opening = session.open();
    await pump();
    transport.open(1, snapshot([rec(0, 'turn/start')]));
    await opening;
    session.handleRunning(true);
    await session.prompt('queue');
    final id = session.snapshot.value.pendingSubmissions.single.requestId;
    transport.item(
      1,
      rec(
        1,
        'agent/inbox/spliced',
        data: {
          'target': 'next-turn',
          'start': 0,
          'removedCount': 0,
          'inserted': [row('q', id)],
        },
      ),
    );
    transport.item(
      1,
      rec(
        2,
        'agent/inbox/spliced',
        data: {
          'target': 'next-turn',
          'start': 0,
          'removedCount': 1,
          'inserted': [],
          'outcome': 'canceled',
        },
      ),
    );
    await pump();
    expect(session.snapshot.value.pendingSubmissions, isEmpty);
  });

  test('queue mutations preserve occurrence and host authority, benign steer races only', () async {
    await session.updateQueue('q1', {
      'kind': 'edit',
      'content': [
        {'type': 'text', 'text': 'new'},
      ],
    });
    expect(transport.queueUpdates.single, {
      'sessionId': 's',
      'itemId': 'q1',
      'action': {
        'kind': 'edit',
        'content': [
          {'type': 'text', 'text': 'new'},
        ],
      },
    });
    for (final code in [
      'session/steer-unavailable',
      'session/queue-item-not-found',
    ]) {
      transport.onUpdateQueue = (_) async =>
          throw RemoteException(code, 'race');
      await session.updateQueue('q1', {'kind': 'steer'});
      await expectLater(
        session.updateQueue('q1', {'kind': 'remove'}),
        throwsA(isA<RemoteException>()),
      );
    }
    transport.onUpdateQueue = (_) async =>
        throw RemoteException('session/forbidden', 'no');
    await expectLater(
      session.updateQueue('q1', {'kind': 'steer'}),
      throwsA(isA<RemoteException>()),
    );
  });

  test('rejecting a prompt removes only its own echo', () async {
    session.handleRunning(true);
    await session.prompt('accepted');
    transport.onPrompt = (_) => throw StateError('refused');
    await expectLater(session.prompt('refused'), throwsStateError);
    expect(session.snapshot.value.pendingSubmissions.map((p) => p.text), [
      'accepted',
    ]);
  });

  test('mixed attachment content cannot be edited, malformed wire rows are skipped', () {
    final mixed = InboxItem.tryParse({
      'id': 'q',
      'source': {'kind': 'user'},
      'content': [
        {'type': 'text', 'text': 'x'},
        {'type': 'file', 'attachment': {}},
      ],
    })!;
    expect(mixed.editable, false);
    expect(mixed.text, 'x');
    expect(
      inboxItems({
        'next-turn': [
          null,
          {},
          {
            'id': 'bad',
            'content': [
              {'type': 'text', 'text': 3},
            ],
            'source': {},
          },
        ],
      }, 'next-turn'),
      isEmpty,
    );
  });
}
