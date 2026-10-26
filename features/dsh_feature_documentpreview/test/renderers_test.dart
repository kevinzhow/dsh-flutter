import 'package:dsh_feature_documentpreview/dsh_feature_documentpreview.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> ids(String path) => [
  for (final r in rendererCandidates(path)) r.id,
];

void main() {
  test('markdown offers the rendered view, the source and plain text', () {
    expect(ids('docs/README.md'), ['markdown', 'code', 'text']);
  });

  test('source files highlight, with the plain text as the alternative', () {
    expect(ids('lib/a.dart'), ['code', 'text']);
    expect(ids('a.TS'), ['code', 'text']);
  });

  test(
    'images have no plain alternative (bitmaps) but svg keeps its source',
    () {
      expect(ids('p.PNG'), ['image']);
      expect(ids('x/y.jpeg'), ['image']);
      expect(ids('logo.svg'), ['image', 'code', 'text']);
    },
  );

  test('unknown text files fall back to plain text', () {
    expect(ids('NOTES'), ['text']);
    expect(ids('notes.weird'), ['text']);
    // `.env` is a source suffix in dsh's language table.
    expect(ids('.env'), ['code', 'text']);
  });

  test('binary containers have no viewer at all', () {
    for (final p in ['c.zip', 'd.mp4', 'e.xlsx', 'f.heic']) {
      expect(rendererCandidates(p), isEmpty, reason: p);
      expect(unviewableBinaryPath(p), isTrue, reason: p);
    }
  });

  test('the longest matching suffix wins', () {
    expect(documentFileName(r'C:\x\File.TAR.GZ'), 'file.tar.gz');
    expect(unviewableBinaryPath('x.tar.gz'), isTrue);
  });
}
