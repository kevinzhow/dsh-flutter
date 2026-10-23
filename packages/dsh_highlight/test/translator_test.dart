import 'dart:convert';
import 'dart:io';

import 'package:dsh_highlight/src/compiled_pattern.dart';
import 'package:dsh_highlight/src/onig_translator.dart';
import 'package:flutter_test/flutter_test.dart';

List<List<int>?> _ranges(OnigMatch m) => [
  for (var i = 0; i <= m.groupCount; i++)
    m.start(i) < 0 ? null : [m.start(i), m.end(i)],
];

void main() {
  group('differential cases (shiki JS engine as oracle)', () {
    final cases = (jsonDecode(
      File('test/fixtures/translator_cases.json').readAsStringSync(),
    ) as List<dynamic>).cast<Map<String, dynamic>>();
    for (final c in cases) {
      final pattern = c['pattern'] as String;
      final subject = c['subject'] as String;
      final start = c['start'] as int;
      final expect_ = c['expect'];
      test('${jsonEncode(pattern)} on ${jsonEncode(subject)}@$start', () {
        final compiled = CompiledPattern.tryCompile(
          pattern,
          positionGroups: {for (var i = 1; i < 40; i++) i},
        );
        if (expect_ == 'unsupported') {
          expect(compiled, isNull, reason: 'shiki rejects this pattern');
          return;
        }
        expect(
          compiled,
          isNotNull,
          reason: 'translator rejected a pattern shiki accepts',
        );
        final m = compiled!.search(subject, start);
        if (expect_ == null) {
          expect(m, isNull);
          return;
        }
        expect(m, isNotNull);
        final want = (expect_ as List<dynamic>)
            .map((e) => e == null ? null : (e as List<dynamic>).cast<int>())
            .toList();
        expect(_ranges(m!), want);
      });
    }
  });

  group('translator output', () {
    test('plain captures keep numbering across hidden groups', () {
      final t = translateOnigPattern(r'(a)(?>b+)(c)');
      expect(t.groupMap, [0, 1, 3]);
      expect(t.markerMap, [0, -1, 0]);
    });
    test('unsupported features throw TranslationException', () {
      for (final p in [r'(?(1)a|b)', r'\y', r'[\d-z]', '(abc', 'a)']) {
        expect(
          () => translateOnigPattern(p),
          throwsA(isA<TranslationException>()),
          reason: p,
        );
      }
    });
    test('tryCompile degrades instead of throwing and reports why', () {
      String? why;
      expect(
        CompiledPattern.tryCompile(r'(?(1)a|b)', onError: (r) => why = r),
        isNull,
      );
      expect(why, contains('conditional'));
    });
    test('leading \\G anchors the search', () {
      final t = translateOnigPattern(r'\Gx');
      expect(t.anchoredAtSearchStart, isTrue);
      expect(t.clipSearch, isFalse);
    });
    test('\\G elsewhere clips the search', () {
      final t = translateOnigPattern(r'(?:a|)\Gb');
      expect(t.clipSearch, isTrue);
    });
  });
}
