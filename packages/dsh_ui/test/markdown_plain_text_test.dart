import 'dart:convert';
import 'dart:io';

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final data = jsonDecode(
    File('test/fixtures/markdown_summaries.json').readAsStringSync(),
  ) as Map;
  for (final (index, row) in (data['cases'] as List).indexed) {
    test('actual TS Markdown summary $index', () {
      for (final mode in ['all', 'first-line', 'first-paragraph']) {
        expect(
          dshMarkdownPlainText(row['text'] as String, mode: mode),
          row['expected'][mode],
          reason: '$mode: ${row['text']}',
        );
      }
    });
  }
}
