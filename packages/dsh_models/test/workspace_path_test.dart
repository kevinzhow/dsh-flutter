import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

void main() {
  workspaceTitleTests();
  test('addresses inside the workspace become relative', () {
    expect(
      fileAddressFor('s1', '/w/proj', '/w/proj/src/a b.dart'),
      'dsh-resource://file/session/s1/src/a%20b.dart',
    );
    expect(
      fileAddressFor('s1', '/w/proj/', 'src/a.dart'),
      'dsh-resource://file/session/s1/src/a.dart',
    );
    expect(
      fileAddressFor('s1', '/w/proj', r'.\src\a.dart'),
      'dsh-resource://file/session/s1/src/a.dart',
    );
  });

  test(
    'outside the workspace or with an unknown root the path stays absolute',
    () {
      expect(
        fileAddressFor('s1', '/w/proj', '/etc/hosts'),
        'dsh-resource://file/session/s1//etc/hosts',
      );
      expect(
        fileAddressFor('s1', null, '/etc/hosts'),
        'dsh-resource://file/session/s1//etc/hosts',
      );
    },
  );

  test('parse reads the parts back, decoded, ignoring query and fragment', () {
    final a = parseSessionFileAddress(
      'dsh-resource://file/session/s%201/dir/a%23b.md?x=1#frag',
    )!;
    expect(a.sessionId, 's 1');
    expect(a.path, 'dir/a#b.md');
    expect(
      parseSessionFileAddress(fileAddressFor('s1', '/w', '/etc/hosts'))!.path,
      '/etc/hosts',
    );
  });

  test('anything else does not parse', () {
    expect(
      parseSessionFileAddress('dsh-resource://file/absolute/etc/x'),
      isNull,
    );
    expect(parseSessionFileAddress('http://x/y'), isNull);
    expect(parseSessionFileAddress('dsh-resource://file/session/s1'), isNull);
    expect(parseSessionFileAddress('dsh-resource://file/session//a'), isNull);
    expect(
      parseSessionFileAddress('dsh-resource://file/session/s1/%E0%A4%A'),
      isNull,
    );
  });

  test('pathPartsOf splits the last segment', () {
    expect(pathPartsOf('/a/b/c.txt'), (directory: '/a/b/', name: 'c.txt'));
    expect(pathPartsOf('c.txt'), (directory: '', name: 'c.txt'));
    expect(pathPartsOf('/a/b/'), (directory: '/a/', name: 'b'));
    expect(pathPartsOf(r'C:\x\y.txt'), (directory: r'C:\x\', name: 'y.txt'));
  });
}

void workspaceTitleTests() {
  test('only the automatic first-use title reads as the localized default', () {
    expect(
      workspaceDisplayTitle('default-workspace', 'Default workspace'),
      'Default workspace',
    );
    expect(workspaceDisplayTitle('default-workspace', '默认工作区'), '默认工作区');
    expect(workspaceDisplayTitle('proj', 'Default workspace'), 'proj');
    expect(workspaceDisplayTitle('', 'Default workspace'), '');
  });

  test(
    'the chip label is the last path segment, or the raw cwd for a root',
    () {
      expect(workspaceTitleOf('/work/proj/'), 'proj');
      expect(workspaceTitleOf(r'C:\work\proj'), 'proj');
      expect(workspaceTitleOf('/'), '');
    },
  );
}
