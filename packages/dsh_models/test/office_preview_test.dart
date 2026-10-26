import 'dart:async';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

class Files implements WorkspaceFilesRemote {
  String version = 'v1';
  bool denied = false;
  int authorized = 0;
  @override
  Future<WorkspaceFileBytes> readBytes(
    String sessionId,
    String path, {
    ByteRange? range,
    String? baseFile,
  }) async {
    authorized++;
    if (denied) throw RemoteException('workspace-file/denied', 'denied');
    expect(range?.length, 1);
    return WorkspaceFileBytes(
      absolutePath: '/$path',
      version: version,
      offset: 0,
      data: Uint8List(1),
      eof: false,
    );
  }

  @override
  Future<WorkspaceFileStat> stat(String sessionId, String path) async =>
      WorkspaceFileStat(absolutePath: '/$path', version: version);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> rendered(
  String path,
  String version, {
  String generation = 'g1',
}) => {
  'absolutePath': '/$path',
  'version': version,
  'offset': 0,
  'data': Uint8List.fromList([37, 80, 68, 70]),
  'eof': true,
  'generation': generation,
  'missingFonts': <String>[],
};
Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  late FakeHost host;
  late Files files;
  late OfficePreviewService service;
  setUp(() {
    host = FakeHost();
    files = Files();
    host.handlers['officeToPdf/generation'] = (_) => 'g1';
    host.handlers['officeToPdf/render'] = (args) =>
        rendered(args['path'] as String, files.version);
    service = OfficePreviewService(
      remotes: host.remotes,
      files: files,
      maxEntries: 1,
    );
  });
  tearDown(() async {
    await service.dispose();
    await host.close();
  });
  test('cached reuse always reauthorizes original Session; source versions and LRU bound results', () async {
    await service.read('original', 'a.docx');
    await service.read('original', 'a.docx');
    expect(files.authorized, 2);
    expect(host.callsTo('officeToPdf/render'), hasLength(1));
    files.denied = true;
    await expectLater(
      service.read('original', 'a.docx'),
      throwsA(isA<RemoteException>()),
    );
    files.denied = false;
    files.version = 'v2';
    await service.read('original', 'a.docx');
    await service.read('other', 'a.docx');
    expect(host.callsTo('officeToPdf/render'), hasLength(3));
    expect(service.cachedEntries, 1);
    expect(service.cachedBytes, 4);
    expect(
      host.callsTo('officeToPdf/render').last.args['workspaceFileScopeId'],
      'other',
    );
  });
  test('concurrent readers share conversion; one cancellation cannot stop the remaining reader', () async {
    final conversion = Completer<Object?>();
    host.handlers['officeToPdf/render'] = (_) => conversion.future;
    final cancelled = RemoteCancellation();
    final a = service.read('s', 'a.docx', cancellation: cancelled);
    final b = service.read('s', 'a.docx');
    await tick();
    final rejected = expectLater(a, throwsA(isA<RemoteException>()));
    cancelled.cancel();
    await rejected;
    expect(host.callsTo('officeToPdf/render'), hasLength(1));
    conversion.complete(rendered('a.docx', 'v1'));
    final result = await b;
    expect(result.data, [37, 80, 68, 70]);
    expect(service.cachedEntries, 1);
  });
  test('renderer generation change cancels old conversion and retries authorization, not stale cache', () async {
    final old = Completer<Object?>();
    var reads = 0;
    host.handlers['officeToPdf/render'] = (args) =>
        ++reads == 1 ? old.future : rendered('a.docx', 'v1', generation: 'g2');
    final first = service.read('s', 'a.docx');
    await tick();
    host.handlers['officeToPdf/generation'] = (_) => 'g2';
    final second = service.read('s', 'a.docx');
    final values = await Future.wait([first, second]);
    expect(values.map((r) => r.generation), ['g2', 'g2']);
    expect(reads, 2);
    old.complete(rendered('a.docx', 'v1'));
    await tick();
    expect((await service.read('s', 'a.docx')).generation, 'g2');
  });
}
