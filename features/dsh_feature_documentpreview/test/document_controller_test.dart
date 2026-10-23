import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_documentpreview/dsh_feature_documentpreview.dart';
import 'package:dsh_slots/testing.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeWorkspaceFiles files;
  setUp(() {
    files = FakeWorkspaceFiles();
    files.texts['a.dart'] = List.generate(
      12,
      (i) => 'line ${i + 1}',
    ).join('\n');
    files.pageLines = 5;
  });

  test('reads the first page, then the next on demand until eof', () async {
    final c = DocumentController(sessionId: 's', path: 'a.dart', files: files);
    addTearDown(c.dispose);
    await settle();
    expect(c.selected!.id, 'code');
    expect(c.lines, ['line 1', 'line 2', 'line 3', 'line 4', 'line 5']);
    expect(c.eof, isFalse);
    await c.loadNext();
    await c.loadNext();
    expect(c.lines, hasLength(12));
    expect(c.eof, isTrue);
    expect(c.loadedThrough, 12);
    expect(files.calls.where((x) => x.startsWith('read ')), [
      'read a.dart 1',
      'read a.dart 6',
      'read a.dart 11',
    ]);
    // Past eof nothing is read.
    await c.loadNext();
    expect(files.calls.where((x) => x.startsWith('read ')), hasLength(3));
  });

  test('navigate loads pages until the line exists', () async {
    final c = DocumentController(sessionId: 's', path: 'a.dart', files: files);
    addTearDown(c.dispose);
    await settle();
    c.navigate(11, 1);
    await settle();
    await settle();
    expect(c.loadedThrough, greaterThanOrEqualTo(11));
    expect(c.targetLine, 11);
    c.answeredTarget();
    expect(c.targetLine, isNull);
    // The same revision is not answered twice.
    c.navigate(3, 1);
    expect(c.targetLine, isNull);
  });

  test('a failed read keeps its failure and loading stops', () async {
    files.failures['bad.txt'] = RemoteException(
      'workspace-file/too-large',
      'big',
      {'path': 'bad.txt', 'limit': 2097152},
    );
    final c = DocumentController(sessionId: 's', path: 'bad.txt', files: files);
    addTearDown(c.dispose);
    await settle();
    expect((c.failure as RemoteException).code, 'workspace-file/too-large');
    expect(c.loading, isFalse);
    expect(c.hasContent, isFalse);
  });

  test('images read the complete bytes once', () async {
    files.binaries['p.png'] = Uint8List.fromList([1, 2, 3]);
    final c = DocumentController(sessionId: 's', path: 'p.png', files: files);
    addTearDown(c.dispose);
    await settle();
    expect(c.selected!.id, 'image');
    expect(c.bytes, [1, 2, 3]);
    expect(c.hasContent, isTrue);
    expect(files.calls.where((x) => x.startsWith('readBytes')), hasLength(1));
  });

  test('a binary container has no renderer and reads nothing', () async {
    final c = DocumentController(sessionId: 's', path: 'a.pdf', files: files);
    addTearDown(c.dispose);
    await settle();
    expect(c.candidates, isEmpty);
    expect(c.selected, isNull);
    expect(files.calls.where((x) => !x.startsWith('changes')), isEmpty);
  });

  test(
    'switching to a viewer with the same loading keeps the content',
    () async {
      files.texts['README.md'] = '# hi\n\nthere';
      final c = DocumentController(
        sessionId: 's',
        path: 'README.md',
        files: files,
      );
      addTearDown(c.dispose);
      await settle();
      expect(c.selected!.id, 'markdown');
      c.select('code');
      expect(c.selected!.id, 'code');
      expect(files.calls.where((x) => x.startsWith('read ')), hasLength(1));
    },
  );

  test(
    'a change observed on the watch reloads when auto refresh is on',
    () async {
      final c = DocumentController(
        sessionId: 's',
        path: 'a.dart',
        files: files,
      );
      addTearDown(c.dispose);
      await settle();
      expect(c.version, 'v1');
      files.texts['a.dart'] = 'new';
      files.watches['a.dart']!.add(
        const WatchChanged(absolutePath: '/work/project/a.dart', version: 'v2'),
      );
      await settle();
      await settle();
      expect(c.lines, ['new']);
    },
  );

  test('a file observed gone shows its failure; the content stays', () async {
    final c = DocumentController(sessionId: 's', path: 'a.dart', files: files);
    addTearDown(c.dispose);
    await settle();
    files.watches['a.dart']!.add(
      const WatchChanged(absolutePath: '/work/project/a.dart', absent: true),
    );
    await settle();
    expect((c.metaFailure as RemoteException).code, 'workspace-file/not-found');
    expect(c.hasContent, isTrue);
  });

  test('wrap toggles and reload rereads from the first page', () async {
    final c = DocumentController(sessionId: 's', path: 'a.dart', files: files);
    addTearDown(c.dispose);
    await settle();
    await c.loadNext();
    expect(c.wrap, isTrue);
    c.toggleWrap();
    expect(c.wrap, isFalse);
    await c.reload();
    expect(c.lines, hasLength(5));
  });
}
