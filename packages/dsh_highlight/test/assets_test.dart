import 'dart:convert';
import 'dart:io';

import 'package:dsh_highlight/dsh_highlight.dart';
import 'package:dsh_highlight/dsh_highlight_flutter.dart';
import 'package:dsh_highlight/dsh_highlight_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AssetGrammarSource reads the bundled grammars', () async {
    final source = await AssetGrammarSource.create();
    expect(
      source.available,
      containsAll(['typescript', 'shellscript', 'json']),
    );
    final e = HighlightEngine(source);
    await e.load('json');
    final lines = e.highlightLines('{"a": [1, true]}', 'json')!;
    expect(lines.single.map((s) => s.text).join(), '{"a": [1, true]}');
    expect(
      lines.single.any((s) => s.token == HighlightToken.keyword),
      isTrue,
      reason: 'property names use the keyword class in the css-variables theme',
    );
  });

  group('the shipped grammar set', () {
    final dir = Directory('assets/grammars');
    final index = jsonDecode(
      File('assets/grammars/index.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final ids = (index['grammars'] as Map<String, dynamic>).keys.toList()
      ..sort();

    test('index.json lists exactly the grammar files', () {
      final files =
          dir
              .listSync()
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last)
              .where((n) => n.endsWith('.json') && n != 'index.json')
              .map((n) => n.substring(0, n.length - 5))
              .toList()
            ..sort();
      expect(files, ids);
      expect(FileGrammarSource('assets/grammars').available, ids.toSet());
    });

    test('all grammar assets together stay within the 4 MB budget', () {
      var total = 0;
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.endsWith('.json')) total += f.lengthSync();
      }
      expect(total, lessThanOrEqualTo(4 * 1024 * 1024));
    });

    test('every embedded dependency is shipped', () {
      final grammars = index['grammars'] as Map<String, dynamic>;
      for (final e in grammars.entries) {
        for (final dep
            in (e.value as Map<String, dynamic>)['embeddedLangs']
                as List<dynamic>) {
          expect(
            grammars.containsKey(dep),
            isTrue,
            reason: '${e.key} embeds $dep',
          );
        }
      }
    });

    test('PROVENANCE.md names every grammar and its license', () {
      final text = File('assets/grammars/PROVENANCE.md').readAsStringSync();
      for (final id in ids) {
        expect(text, contains('`$id`'), reason: id);
      }
    });

    test('every grammar loads and every regex translates', () async {
      final e = HighlightEngine(FileGrammarSource('assets/grammars'));
      final stats = <String, PatternStats>{};
      for (final id in ids) {
        await e.load(id);
        expect(e.isLoaded(id), isTrue, reason: id);
        stats[id] = e.patternStats(id)!;
      }
      var unique = 0;
      var degraded = 0;
      for (final e in stats.entries) {
        unique += e.value.unique;
        degraded += e.value.degraded;
        expect(e.value.degraded, 0, reason: '${e.key}: ${e.value.reasons}');
      }
      // ignore: avoid_print
      print(
        'translator coverage: $unique distinct regexes in ${ids.length} '
        'grammars, $degraded degraded',
      );
    });
  });
}
