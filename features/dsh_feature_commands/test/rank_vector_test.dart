import 'dart:convert';
import 'dart:io';

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// The menu's ranking against dsh's own `rankByName` (tool/vectors/gen_input_expected.py).
void main() {
  final fixture = jsonDecode(
    File('../../packages/dsh_conversation/test/fixtures/input_vector.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  final cases = (fixture['cases']! as List)
      .cast<Map<String, Object?>>()
      .where((c) => c['op'] == 'rank')
      .toList();

  test('every ranking of the fixture matches dsh', () {
    expect(cases, isNotEmpty);
    for (final c in cases) {
      final items = (c['items']! as List).cast<Map<String, Object?>>();
      final got = rankByName<Map<String, Object?>>(
        items,
        c['query']! as String,
        name: (i) => i['name']! as String,
        label: (i) => i['label'] as String?,
      );
      expect(
        [for (final i in got) i['name']],
        c['expect'],
        reason: 'query "${c['query']}"',
      );
    }
  });
}
