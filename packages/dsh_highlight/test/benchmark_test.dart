import 'dart:io';

import 'package:dsh_highlight/dsh_highlight.dart';
import 'package:dsh_highlight/dsh_highlight_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Micro benchmark with a generous bound: a 5000-line TypeScript file must
/// tokenize in seconds, not minutes. (Measured on a desktop in JIT mode; the
/// bound leaves room for a phone and a loaded CI machine.)
void main() {
  test('5000 lines of TypeScript', () async {
    final dir = Directory('test/fixtures/samples/typescript');
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final code = StringBuffer();
    var lines = 0;
    while (lines < 5000) {
      for (final f in files) {
        final text = f.readAsStringSync();
        code.write(text);
        lines += '\n'.allMatches(text).length;
      }
    }
    final engine = HighlightEngine(FileGrammarSource('assets/grammars'));
    await engine.load('typescript');
    final sw = Stopwatch()..start();
    final result = engine.highlightLines(code.toString(), 'typescript')!;
    sw.stop();
    // ignore: avoid_print
    print(
      'benchmark: ${result.length} lines of typescript in '
      '${sw.elapsedMilliseconds} ms',
    );
    expect(result.length, greaterThanOrEqualTo(5000));
    expect(engine.timedOutLines, 0);
    expect(sw.elapsed, lessThan(const Duration(seconds: 30)));
  });
}
