import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_feature_documentpreview/src/html_document.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
void main() {
  test(
    'static document is inert before loading and remains an opaque sandbox',
    () {
      final basic = createBasicHtmlDocument(
        bytes(
          '<html><head><base href="https://example.com"><meta http-equiv="refresh" content="0;url=https://example.com"></head><body onload="bad()"><script>bad()</script><iframe src="file:///secret"></iframe><a href="https://example.com">link</a><style>p{color:red}</style><p>Kept</p></body></html>',
        ),
      );
      expect(basic, contains("script-src 'none'"));
      expect(basic, contains("connect-src 'none'"));
      expect(basic, contains('Kept'));
      expect(basic, contains('<style>'));
      expect(basic, isNot(contains('<script')));
      expect(basic, isNot(contains('<iframe')));
      expect(basic, isNot(contains('onload=')));
      expect(basic, isNot(contains('<base')));
      final frame = sandboxedHtmlDocument(basic, interactive: false);
      expect(frame, contains('sandbox=""'));
      expect(frame, isNot(contains('allow-same-origin')));
      expect(frame, contains('&lt;'));
    },
  );
  test('interactive pack reads finite classic resources, no modules or URL traversal', () async {
    final reads = <String>[];
    final packed = await packHtmlDocument(
      bytes(
        '<script src="local.js?rev=1"></script><script src="local.js?rev=1"></script><script type="module" src="module.js"></script><script src="https://remote.example/other.js"></script><link rel="stylesheet" href="theme.css#x">',
      ),
      (reference) async {
        reads.add(reference);
        return bytes(
          reference.endsWith('#x')
              ? 'body{}'
              : 'document.body.dataset.ready="yes";',
        );
      },
    );
    expect(reads, ['local.js?rev=1', 'theme.css#x']);
    expect(htmlRelativeFile('local%20script.js?rev=1#x'), 'local script.js');
    expect(() => htmlRelativeFile('%2Fsecret.js'), throwsFormatException);
    expect(() => htmlRelativeFile('file%3Asecret.js'), throwsFormatException);
    expect(() => htmlRelativeFile('a%5Cb.js'), throwsFormatException);
    final frame = sandboxedHtmlDocument(
      createInteractiveHtmlDocument(packed),
      interactive: true,
    );
    expect(frame, contains('sandbox="allow-scripts"'));
    expect(frame, isNot(contains('allow-same-origin')));
    final based = await packHtmlDocument(
      bytes(
        '<base href="https://example.com/"><script src="skip.js"></script>',
      ),
      (_) async => throw StateError('must not read'),
    );
    expect(based.assets, isEmpty);
  });
  test('asset and decode failures do not silently produce a partial interactive document', () async {
    await expectLater(
      packHtmlDocument(
        bytes('<script src="missing.js"></script>'),
        (_) async => throw StateError('denied'),
      ),
      throwsStateError,
    );
    expect(
      () => createBasicHtmlDocument(Uint8List.fromList([0xff])),
      throwsFormatException,
    );
    var reads = 0;
    await expectLater(
      packHtmlDocument(
        bytes(List.generate(65, (i) => '<script src="$i.js"></script>').join()),
        (_) async {
          reads++;
          return bytes('');
        },
      ),
      throwsFormatException,
    );
    expect(reads, 64);
  });
}
