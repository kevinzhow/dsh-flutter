import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

import 'support/fake_transport.dart';

List<num> seqs(Session s) => s.eventSource.window.entries
    .where((e) => !e.transient)
    .map((e) => e.seq)
    .toList();

void main() {
  late FakeTransport t;
  late Session session;

  setUp(() {
    t = FakeTransport();
    session = Session('sess', t);
  });

  tearDown(() => session.dispose());

  Future<void> openWith(
    List<Map<String, Object?>> records, {
    bool hasMore = false,
  }) async {
    final opening = session.open();
    await pump();
    t.open(1, snapshot(records, hasMore: hasMore));
    await opening;
  }

  test(
    'follow request asks for the assistant stream and the history window',
    () async {
      await openWith([rec(1, 'turn/start')]);
      expect(t.followRequests.single, {
        'address': {'kind': 'session', 'sessionId': 'sess'},
        'assistantStream': true,
        'maxMessages': 500,
        'turnWindow': {'minMessages': 50, 'minTurns': 2},
      });
      expect(session.snapshot.value.openState, OpenState.open);
    },
  );

  test(
    'the opening snapshot replaces the window and seeds projections',
    () async {
      final opening = session.open();
      await pump();
      expect(session.snapshot.value.openState, OpenState.loading);
      t.open(
        1,
        snapshot(
          [rec(1, 'turn/start'), rec(2, 'turn/end')],
          hasMore: true,
          projections: {'title': 'T'},
        ),
      );
      await opening;
      expect(seqs(session), [1, 2]);
      expect(session.snapshot.value.hasMore, isTrue);
      expect(session.projections.get('title'), 'T');
      expect(session.eventSource.window.change, WindowChangeKind.replace);
    },
  );

  test(
    'contiguous events append, duplicates and replays are dropped',
    () async {
      await openWith([rec(1, 'turn/start')]);
      t.item(1, rec(2, 'step/start'));
      t.item(1, rec(2, 'step/start'));
      t.item(1, rec(1, 'turn/start'));
      t.item(1, rec(3, 'step/end'));
      await pump();
      expect(seqs(session), [1, 2, 3]);
    },
  );

  test('a gap is repaired with one page read through the new entry', () async {
    await openWith([rec(1, 'turn/start')]);
    t.onPage = (req) async => {
      'records': [
        rec(1, 'turn/start'),
        rec(2, 'step/start'),
        rec(3, 'step/end'),
        rec(4, 'turn/end'),
      ],
      'hasMore': false,
    };
    t.item(1, rec(4, 'turn/end'));
    await pump();
    expect(seqs(session), [1, 2, 3, 4]);
    expect(t.pageRequests.single['throughSeq'], 4);
    expect(t.pageRequests.single['address'], {
      'kind': 'session',
      'sessionId': 'sess',
    });
    expect(session.eventSource.window.change, WindowChangeKind.replace);
  });

  test('entries queued behind a repair merge into the replacement', () async {
    await openWith([rec(1, 'turn/start')]);
    t.onPage = (req) async {
      await pump(50);
      return {
        'records': [
          rec(1, 'turn/start'),
          rec(2, 'step/start'),
          rec(3, 'step/end'),
        ],
        'hasMore': false,
      };
    };
    t.item(1, rec(3, 'step/end'));
    await pump();
    t.item(1, rec(4, 'turn/end'));
    await pump(120);
    expect(seqs(session), [1, 2, 3, 4]);
  });

  test('a new generation snapshot replaces the window; a stale cursor is a violation', () async {
    await openWith([rec(1, 'turn/start'), rec(2, 'step/start')]);
    t.currentFollow.add(StreamEnded(1, CarrierLost()));
    t.currentFollow.add(const StreamOpened(2));
    t.item(
      2,
      snapshot([
        rec(1, 'turn/start'),
        rec(2, 'step/start'),
        rec(3, 'step/end'),
      ]),
    );
    await pump();
    expect(seqs(session), [1, 2, 3]);
    t.currentFollow.add(const StreamOpened(3));
    t.item(3, snapshot([rec(1, 'turn/start')]));
    await pump();
    expect(session.snapshot.value.openState, OpenState.error);
    expect(
      (session.snapshot.value.openError as RemoteException).code,
      'gateway/internal',
    );
  });

  test('loadOlder prepends one older page and keeps contiguity', () async {
    await openWith([rec(5, 'turn/start'), rec(6, 'step/start')], hasMore: true);
    t.onPage = (req) async => {
      'records': [rec(3, 'turn/start'), rec(4, 'turn/end')],
      'hasMore': false,
    };
    await session.loadOlder();
    expect(seqs(session), [3, 4, 5, 6]);
    expect(session.snapshot.value.hasMore, isFalse);
    expect(t.pageRequests.single['beforeSeq'], 5);
    expect(t.pageRequests.single['throughSeq'], 6);
  });

  test('a discontinuous history page is rejected', () async {
    await openWith([rec(5, 'turn/start')], hasMore: true);
    t.onPage = (req) async => {
      'records': [rec(2, 'turn/start'), rec(3, 'turn/end')],
      'hasMore': false,
    };
    await expectLater(session.loadOlder(), throwsA(isA<ProtocolViolation>()));
    expect(seqs(session), [5]);
  });

  test('a host error on follow puts the session in the error state', () async {
    final opening = session.open();
    await pump();
    t.currentFollow.add(StreamOpened(1));
    t.currentFollow.add(
      StreamEnded(1, RemoteException('session/not-found', 'x')),
    );
    await opening;
    expect(session.snapshot.value.openState, OpenState.error);
  });

  group('assistant stream', () {
    Map<String, Object?> start(int rev) => aframe({
      'type': 'start',
      'attemptId': 'a1',
      'revision': rev,
      'turn': 1,
      'step': 1,
      'startedAfterSeq': 2,
    });
    Map<String, Object?> chunk(int rev, int index, Map<String, Object?> c) =>
        aframe({
          'type': 'chunk',
          'attemptId': 'a1',
          'revision': rev,
          'index': index,
          'time': 5000 + index,
          'chunk': c,
        });
    Map<String, Object?> endFrame(int rev, int index) => aframe({
      'type': 'end',
      'attemptId': 'a1',
      'revision': rev,
      'index': index,
      'outcome': {
        'kind': 'committed',
        'eventType': 'assistant/message',
        'seq': 3,
      },
    });

    List<String> kinds() => session.eventSource.window.entries
        .map(
          (e) => e.transient ? 't:${(e.data as Map)['chunk']['type']}' : e.type,
        )
        .toList();

    test('live chunks stream as transient rows, then the durable settlement replaces them', () async {
      await openWith([rec(1, 'turn/start'), rec(2, 'step/start')]);
      t.item(1, start(1));
      t.item(1, chunk(2, 0, {'type': 'text-delta', 'index': 0, 'text': 'hi'}));
      t.item(1, chunk(3, 1, {'type': 'block-end', 'index': 0}));
      await pump();
      expect(kinds(), [
        'turn/start',
        'step/start',
        't:text-delta',
        't:block-end',
      ]);
      final live = session.eventSource.window.entries
          .where((e) => e.transient)
          .toList();
      expect(live.first.seq, greaterThan(2));
      expect(live.first.seq, lessThan(3));
      // the durable settlement is staged while its attempt is live...
      t.item(
        1,
        rec(
          3,
          'assistant/message',
          surfaceOp: 'append',
          data: {'turn': 1, 'step': 1},
        ),
      );
      await pump();
      expect(kinds().contains('assistant/message'), isFalse);
      // ...and released by the end frame; transient rows stay until Step end.
      t.item(1, endFrame(4, 2));
      await pump();
      expect(kinds().last, 'assistant/message');
      expect(kinds().where((k) => k.startsWith('t:')), isNotEmpty);
      t.item(1, rec(4, 'step/end', data: {'turn': 1, 'step': 1}));
      await pump();
      expect(kinds(), [
        'turn/start',
        'step/start',
        'assistant/message',
        'step/end',
      ]);
    });

    test('an index gap rebaselines: follow is reopened once', () async {
      await openWith([rec(1, 'turn/start'), rec(2, 'step/start')]);
      t.item(1, start(1));
      t.item(1, chunk(2, 0, {'type': 'text-delta', 'index': 0, 'text': 'a'}));
      t.item(1, chunk(3, 5, {'type': 'text-delta', 'index': 0, 'text': 'b'}));
      await pump(60);
      expect(t.follows.length, 2, reason: 'restart reopened the follow stream');
      t.open(
        1,
        snapshot([rec(1, 'turn/start'), rec(2, 'step/start')], revision: 3),
      );
      await pump();
      expect(session.snapshot.value.openState, OpenState.open);
    });

    test(
      'a revision skip is a carrier failure: restart, window retained',
      () async {
        await openWith([rec(1, 'turn/start'), rec(2, 'step/start')]);
        t.item(1, start(1));
        t.item(1, chunk(5, 0, {'type': 'text-delta', 'index': 0, 'text': 'a'}));
        await pump(60);
        expect(t.follows.length, 2);
        expect(seqs(session), [1, 2]);
      },
    );

    test('a reconnect snapshot with an active attempt rebuilds the transient prefix', () async {
      final opening = session.open();
      await pump();
      t.open(
        1,
        snapshot(
          [rec(1, 'turn/start'), rec(2, 'step/start')],
          revision: 7,
          activeAttempt: {
            'attemptId': 'a1',
            'startedAfterSeq': 2,
            'turn': 1,
            'step': 1,
            'nextIndex': 2,
            'stream': [
              {
                'type': 'text-chunks',
                'time0': 100,
                'index': 0,
                'dt': [5],
                'texts': ['he', 'llo'],
              },
            ],
          },
        ),
      );
      await opening;
      final texts = session.eventSource.window.entries
          .where((e) => e.transient)
          .map((e) => (e.data as Map)['chunk']['text'])
          .toList();
      expect(texts, ['he', 'llo']);
    });

    test('expandAssistantStream unpacks runs and raw chunks', () {
      final chunks = expandAssistantStream([
        {
          'type': 'reasoning-chunks',
          'time0': 10,
          'index': 0,
          'dt': [1, 2],
          'texts': ['a', 'b', 'c'],
        },
        {
          'type': 'tool-call-chunks',
          'time0': 20,
          'index': 1,
          'dt': [],
          'id': 'c1',
          'name': 'sh',
          'args': ['{}'],
        },
        {
          'type': 'chunk',
          'time': 30,
          'chunk': {'type': 'usage'},
        },
      ]);
      expect(chunks.map((c) => c.time), [10, 11, 13, 20, 30]);
      expect(chunks[3].chunk['name'], 'sh');
      expect(chunks.last.chunk['type'], 'usage');
    });
  });

  test('prompt sends the queue request and echoes locally until the durable user message', () async {
    await openWith([]);
    await session.prompt('hello');
    final sent = t.prompts.single;
    expect(sent['mode'], 'queue');
    expect(sent['sessionId'], 'sess');
    expect((sent['content']! as List).single, {
      'type': 'text',
      'text': 'hello',
    });
    expect(session.snapshot.value.pendingSubmissions.single.text, 'hello');
    t.item(
      1,
      rec(
        0,
        'user/message',
        data: {
          'source': {'kind': 'user', 'rpcId': sent['requestId']},
        },
      ),
    );
    await pump();
    expect(session.snapshot.value.pendingSubmissions, isEmpty);
  });

  test('cancel calls session/cancel', () async {
    await session.cancel();
    expect(t.cancels, ['sess']);
  });
}
