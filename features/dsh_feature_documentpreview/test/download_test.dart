import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_documentpreview/dsh_feature_documentpreview.dart';
import 'package:dsh_slots/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeWorkspaceFiles files;
  late FakeHostFileActions actions;
  setUp(() {
    files = FakeWorkspaceFiles();
    actions = FakeHostFileActions();
    files.binaries['doc.pdf'] = Uint8List.fromList(
      List.generate(2500, (i) => i % 256),
    );
  });

  FileDownload download({int window = 1000}) => FileDownload(
    sessionId: 's',
    path: 'doc.pdf',
    name: 'doc.pdf',
    files: files,
    actions: actions,
    windowBytes: window,
  );

  test('reads in windows, writes the exact bytes, then opens', () async {
    final d = download();
    addTearDown(d.dispose);
    expect(await d.open(), isTrue);
    expect(files.calls.where((c) => c.startsWith('readBytes')), [
      'readBytes doc.pdf 0',
      'readBytes doc.pdf 1000',
      'readBytes doc.pdf 2000',
    ]);
    expect(actions.content['doc.pdf']!.takeBytes(), files.binaries['doc.pdf']);
    expect(actions.opened, ['doc.pdf']);
    expect(d.done, isTrue);
    expect(d.total, 2500);
    expect(d.fraction, 1);
  });

  test('a second action does not download again', () async {
    final d = download();
    addTearDown(d.dispose);
    await d.open();
    await d.save();
    expect(files.calls.where((c) => c.startsWith('readBytes')), hasLength(3));
    expect(actions.saved, ['doc.pdf']);
  });

  test('a failure keeps its error and a retry starts over', () async {
    files.failures['doc.pdf'] = RemoteException(
      'workspace-file/not-found',
      'gone',
    );
    final d = download();
    addTearDown(d.dispose);
    expect(await d.open(), isFalse);
    expect(d.error, isA<RemoteException>());
    expect(d.busy, isFalse);
    files.failures.clear();
    expect(await d.open(), isTrue);
    expect(d.error, isNull);
  });
}
