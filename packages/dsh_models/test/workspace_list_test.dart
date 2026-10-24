import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_workspace.dart' as ws;
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';

ws.WorkspaceView view(
  String id, {
  String? path,
  List<String> sessions = const [],
}) => ws.WorkspaceView(
  workspaceId: id,
  path: path ?? '/work/$id',
  title: id,
  sessionIds: sessions,
  createdAt: '2026-10-01T00:00:00.000Z',
  updatedAt: '2026-10-01T00:00:00.000Z',
);

Object? baseline(
  List<ws.WorkspaceView> items, {
  List<String> archived = const [],
  List<String> pinned = const [],
}) => {
  'type': 'baseline',
  'value': {
    'items': [for (final w in items) w.toJson()],
    'archivedSessionIds': archived,
    'pinnedSessionIds': pinned,
  },
};

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeHost host;
  late StreamController<GenerationFrame> frames;
  late WorkspaceList list;

  setUp(() {
    host = FakeHost();
    frames = StreamController<GenerationFrame>.broadcast(sync: true);
    list = WorkspaceList(
      remote: host.remotes.workspace,
      follow: () => frames.stream,
    );
    list.start();
  });

  tearDown(() async {
    await list.dispose();
    await host.close();
    await frames.close();
  });

  void item(Object? value, [int generation = 1]) =>
      frames.add(StreamItem(generation, value));

  test('starts pending and empty; the baseline makes it ready', () {
    expect(list.value.phase, WorkspacePhase.pending);
    expect(list.value.items, isEmpty);
    item(baseline([view('a'), view('b')], pinned: ['s1']));
    expect(list.value.phase, WorkspacePhase.ready);
    expect([for (final w in list.value.items) w.workspaceId], ['a', 'b']);
    expect(list.value.pinnedSessionIds, ['s1']);
  });

  test('an upsert replaces a row in place or appends a new one', () {
    item(baseline([view('a'), view('b')]));
    item({
      'type': 'upsert',
      'workspace': view('a', sessions: ['s1']).toJson(),
    });
    item({'type': 'upsert', 'workspace': view('c').toJson()});
    expect([for (final w in list.value.items) w.workspaceId], ['a', 'b', 'c']);
    expect(list.value.byId('a')!.sessionIds, ['s1']);
    expect(list.value.ofSession('s1')!.workspaceId, 'a');
    expect(list.value.ofSession('zz'), isNull);
  });

  test('a removed workspace is not resurrected by a late upsert', () {
    item(baseline([view('a'), view('b')]));
    item({'type': 'remove', 'workspaceId': 'a'});
    expect([for (final w in list.value.items) w.workspaceId], ['b']);
    item({'type': 'upsert', 'workspace': view('a').toJson()});
    expect(list.value.byId('a'), isNull);
    // A new generation's baseline is authoritative again.
    item(baseline([view('a')]), 2);
    expect(list.value.byId('a'), isNotNull);
  });

  test('order frames reorder; rows the order omits keep their place after', () {
    item(baseline([view('a'), view('b'), view('c')]));
    item({
      'type': 'order',
      'workspaceIds': ['c', 'a'],
    });
    expect([for (final w in list.value.items) w.workspaceId], ['c', 'a', 'b']);
  });

  test('the archive and pin sets are replaced by their frames', () {
    item(baseline([view('a')]));
    item({
      'type': 'archived',
      'archivedSessionIds': ['x'],
    });
    item({
      'type': 'pinned',
      'pinnedSessionIds': ['y', 'z'],
    });
    expect(list.value.archivedSessionIds, ['x']);
    expect(list.value.pinnedSessionIds, ['y', 'z']);
  });

  test('a replace frame is a full reset like a baseline', () {
    item(baseline([view('a'), view('b')]));
    item({'type': 'remove', 'workspaceId': 'b'});
    item({
      'type': 'replace',
      'value': {
        'items': [view('b').toJson()],
        'archivedSessionIds': <String>[],
        'pinnedSessionIds': <String>[],
      },
    });
    expect([for (final w in list.value.items) w.workspaceId], ['b']);
  });

  test('an unknown frame kind is ignored', () {
    item(baseline([view('a')]));
    item({'type': 'from-the-future', 'x': 1});
    expect(list.value.items, hasLength(1));
  });

  test(
    'create merges the Host answer at once, before the stream echoes it',
    () async {
      item(baseline([view('a')]));
      host.handlers['workspace/create'] = (args) {
        expect(args['request'], {'path': '/work/new'});
        return {
          'workspace': view('new', path: '/work/new').toJson(),
          'created': true,
        };
      };
      final created = await list.create('/work/new');
      expect(created.workspaceId, 'new');
      expect([for (final w in list.value.items) w.workspaceId], ['a', 'new']);
      // The echo is an idempotent upsert.
      item({
        'type': 'upsert',
        'workspace': view('new', path: '/work/new').toJson(),
      });
      expect(list.value.items, hasLength(2));
    },
  );

  test('a directory that already is a workspace resolves to its row', () async {
    item(baseline([view('a', path: '/work/a')]));
    host.handlers['workspace/create'] = (_) => {
      'workspace': view('a', path: '/work/a').toJson(),
      'created': false,
    };
    final created = await list.create('/work/a');
    expect(created.workspaceId, 'a');
    expect(list.value.items, hasLength(1));
  });

  test(
    'a refused path throws the Host failure and leaves the list alone',
    () async {
      item(baseline([view('a')]));
      host.handlers['workspace/create'] = (_) =>
          throw RemoteException('workspace/invalid-path', 'Not a directory');
      await expectLater(
        list.create('/nope'),
        throwsA(
          isA<RemoteException>().having(
            (e) => e.message,
            'message',
            'Not a directory',
          ),
        ),
      );
      expect(list.value.items, hasLength(1));
    },
  );

  test('initializeDefault answers null for an ineligible account', () async {
    host.handlers['workspace/initializeDefault'] = (_) => null;
    expect(await list.initializeDefault(), isNull);
    expect(list.value.items, isEmpty);
  });

  test('initializeDefault merges the default workspace', () async {
    host.handlers['workspace/initializeDefault'] = (_) => {
      'workspace': view('home').toJson(),
      'created': true,
    };
    final made = await list.initializeDefault();
    expect(made!.workspaceId, 'home');
    expect(list.value.byId('home'), isNotNull);
  });

  test('a stream error is kept on the snapshot', () async {
    item(baseline([view('a')]));
    frames.addError(StateError('lost'));
    await settle();
    expect(list.value.error, isA<StateError>());
    expect(list.value.items, hasLength(1));
  });

  test('a later generation replaces the whole state', () {
    item(baseline([view('a')], pinned: ['p']));
    item(baseline([view('b')]), 2);
    expect([for (final w in list.value.items) w.workspaceId], ['b']);
    expect(list.value.pinnedSessionIds, isEmpty);
  });

  test('nothing lands after dispose', () async {
    await list.dispose();
    item(baseline([view('a')]));
    expect(list.value.items, isEmpty);
  });
}
