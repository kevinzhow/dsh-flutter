import 'dart:async';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';

void main() {
  late FakeHost host;
  late DshConnection conn;
  late DshWorkspaceFiles files;

  setUp(() async {
    host = await FakeHost.start();
    conn = DshConnection(origin: host.origin);
    files = DshWorkspaceFiles(conn);
    conn.start(host.token);
    await conn.untilConnected();
  });

  tearDown(() async {
    await conn.stop();
    await host.stop();
  });

  test('sends the host parameter names and parses a stat', () async {
    host.unary['workspaceFiles/stat'] = (args) {
      expect(args, {'workspaceFileScopeId': 's1', 'path': 'a.txt'});
      return {'absolutePath': '/w/a.txt', 'version': 'v1', 'bytes': 29};
    };
    final stat = await files.stat('s1', 'a.txt');
    expect(stat.absolutePath, '/w/a.txt');
    expect(stat.version, 'v1');
    expect(stat.bytes, 29);
  });

  test('read sends the range and parses a page', () async {
    host.unary['workspaceFiles/read'] = (args) {
      expect(args, {
        'workspaceFileScopeId': 's1',
        'path': 'a.txt',
        'range': {'offset': 3, 'limit': 100},
      });
      return {
        'absolutePath': '/w/a.txt',
        'version': 'v1',
        'offset': 3,
        'text': 'c\nd',
        'lines': 2,
        'eof': true,
      };
    };
    final page = await files.read('s1', 'a.txt', offset: 3, limit: 100);
    expect(page.text, 'c\nd');
    expect(page.lines, 2);
    expect(page.eof, isTrue);
    expect(page.bytes, isNull);
  });

  test('read without a window sends an empty range object', () async {
    host.unary['workspaceFiles/read'] = (args) {
      expect(args['range'], <String, Object?>{});
      return {
        'absolutePath': '/w/a',
        'version': 'v',
        'offset': 1,
        'text': '',
        'lines': 0,
        'eof': true,
      };
    };
    await files.read('s1', 'a');
  });

  test('readBytes returns the byte window and sends options', () async {
    host.unary['workspaceFiles/readBytes'] = (args) {
      expect(args['options'], {
        'range': {'offset': 10, 'length': 4},
        'baseFile': 'docs/a.md',
      });
      return FakeBinaryResult(
        {
          'absolutePath': '/w/p.png',
          'version': 'v',
          'bytes': 14,
          'offset': 10,
          'data': null,
          'eof': true,
        },
        [
          (path: ['data'], bytes: [1, 2, 3, 4]),
        ],
      );
    };
    final bytes = await files.readBytes(
      's1',
      'p.png',
      range: const ByteRange(offset: 10, length: 4),
      baseFile: 'docs/a.md',
    );
    expect(bytes.data, isA<Uint8List>());
    expect(bytes.data, [1, 2, 3, 4]);
    expect(bytes.eof, isTrue);
    expect(bytes.offset, 10);
  });

  test('the complete-file read sends empty options', () async {
    host.unary['workspaceFiles/readBytes'] = (args) {
      expect(args['options'], <String, Object?>{});
      return FakeBinaryResult(
        {
          'absolutePath': '/w/p',
          'version': 'v',
          'offset': 0,
          'data': null,
          'eof': true,
        },
        [
          (path: ['data'], bytes: const <int>[]),
        ],
      );
    };
    expect((await files.readBytes('s1', 'p')).data, isEmpty);
  });

  test('list parses entries and types', () async {
    host.unary['workspaceFiles/list'] = (args) => {
      'path': '',
      'entries': [
        {'name': 'a.txt', 'type': 'file', 'size': 29},
        {'name': 'sub', 'type': 'directory'},
        {'name': 'sock', 'type': 'other'},
      ],
      'truncated': true,
    };
    final listing = await files.list('s1', '.');
    expect(listing.truncated, isTrue);
    expect(listing.entries.map((e) => e.name), ['a.txt', 'sub', 'sock']);
    expect(listing.entries.map((e) => e.type), [
      WorkspaceEntryType.file,
      WorkspaceEntryType.directory,
      WorkspaceEntryType.other,
    ]);
    expect(listing.entries.first.size, 29);
    expect(listing.entries[1].size, isNull);
  });

  test('host failures keep their code and details', () async {
    host.unary['workspaceFiles/read'] = (args) =>
        throw FakeRemoteError('workspace-file/not-found', 'no entry');
    await expectLater(
      files.read('s1', 'nope'),
      throwsA(
        isA<RemoteException>().having(
          (e) => e.code,
          'code',
          'workspace-file/not-found',
        ),
      ),
    );
  });

  test('a malformed answer is refused', () async {
    host.unary['workspaceFiles/stat'] = (args) => {'absolutePath': 3};
    await expectLater(
      files.stat('s1', 'a'),
      throwsA(
        isA<RemoteException>().having(
          (e) => e.code,
          'code',
          'transport/bad-envelope',
        ),
      ),
    );
  });

  test('changes maps frames to ready / change / reopen events', () async {
    final opened = Completer<FakeStream>();
    host.streams['workspaceFiles/changes'] = opened.complete;
    final events = <WorkspaceWatchEvent>[];
    final sub = files.changes('s1', '/w').listen(events.add);
    final stream = await opened.future;
    expect(stream.payload, {
      'args': {'workspaceFileScopeId': 's1', 'path': '/w'},
    });
    stream.item({'kind': 'ready'});
    stream.item({
      'kind': 'change',
      'change': {'absolutePath': '/w', 'version': 'v2'},
    });
    stream.item({
      'kind': 'change',
      'change': {'absolutePath': '/w/x', 'absent': true},
    });
    stream.item({'kind': 'unknown'});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(events[0], isA<WatchReopened>());
    expect(events[1], isA<WatchReady>());
    expect(events[2], isA<WatchChanged>().having((e) => e.version, 'v', 'v2'));
    expect(
      events[3],
      isA<WatchChanged>().having((e) => e.absent, 'absent', true),
    );
    expect(events, hasLength(4));
    await sub.cancel();
  });

  test('a watch the host cannot start surfaces its error code', () async {
    final opened = Completer<FakeStream>();
    host.streams['workspaceFiles/changes'] = opened.complete;
    final errors = <Object>[];
    final sub = files.changes('s1', '/w').listen((_) {}, onError: errors.add);
    (await opened.future).error('workspace-file/watch-unsupported', 'no');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      errors.single,
      isA<RemoteException>().having(
        (e) => e.code,
        'code',
        'workspace-file/watch-unsupported',
      ),
    );
    await sub.cancel();
  });
}
