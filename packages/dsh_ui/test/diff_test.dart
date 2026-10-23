import 'dart:convert';
import 'dart:io';

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Dart diff must produce dsh's rows: the fixture is the output of dsh's
/// own `structuredPatch` (jsdiff, context 3, maxEditLength 256) over
/// generated edits, written by tool/vectors/ts/diff_cases.mjs.
void main() {
  final fixture = json.decode(
    File('test/fixtures/diff_cases.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  test('the oracle fixture is real', () {
    expect(fixture['schema'], 'dsh-diff-cases/1');
    expect(cases.length, greaterThan(40));
  });

  for (var i = 0; i < cases.length; i++) {
    test('case $i rows and totals equal jsdiff', () {
      final c = cases[i];
      final hunk = DshDiffHunk(
        path: 'f',
        oldText: c['old'] as String?,
        newText: c['new'] as String,
      );
      final rows = buildDiffRows([hunk]).skip(1).toList(); // path header
      final want = (c['rows'] as List).cast<List<dynamic>>();
      expect(
        [
          for (final r in rows) [r.kind.name, r.text],
        ],
        want,
        reason: 'old=${jsonEncode(c['old'])} new=${jsonEncode(c['new'])}',
      );
      final totals = diffTotals([hunk]);
      expect(totals.added, c['added']);
      expect(totals.removed, c['removed']);
    });
  }

  test('a second hunk of the same file is separated by a gap row', () {
    final rows = buildDiffRows(const [
      DshDiffHunk(path: 'a.dart', oldText: 'x\n', newText: 'y\n'),
      DshDiffHunk(path: 'a.dart', oldText: 'p\n', newText: 'q\n'),
      DshDiffHunk(path: 'b.dart', oldText: null, newText: 'n\n'),
    ]);
    expect(
      [for (final r in rows) r.kind],
      [
        DshDiffRowKind.path,
        DshDiffRowKind.del,
        DshDiffRowKind.add,
        DshDiffRowKind.gap,
        DshDiffRowKind.del,
        DshDiffRowKind.add,
        DshDiffRowKind.path,
        DshDiffRowKind.add,
      ],
    );
  });

  test('copy text prefixes rows like dsh', () {
    final rows = buildDiffRows(const [
      DshDiffHunk(path: 'a', oldText: 'x\nk\n', newText: 'y\nk\n'),
    ]);
    expect(diffCopyText(rows), 'a\n- x\n+ y\n  k');
  });

  test('the code language comes from the file extension', () {
    expect(dshLanguageForPath('src/app.ts'), 'typescript');
    expect(dshLanguageForPath(r'C:\dir\Main.PS1'), 'powershell');
    expect(dshLanguageForPath('.env'), 'dotenv');
    expect(dshLanguageForPath('.gitignore'), isNull);
    expect(dshLanguageForPath('Makefile'), isNull);
    expect(dshSupportsHighlighting('dart'), isTrue);
    expect(dshSupportsHighlighting('klingon'), isFalse);
    expect(dshSupportsHighlighting(null), isFalse);
  });
}
