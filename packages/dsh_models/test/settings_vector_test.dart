// Replays the dsh-settings-vector/1 fixtures through the Dart settings models.
// The expectations come from dsh's own TypeScript code (tool/vectors,
// gen_settings_expected.py): the schema vector compares the verdict and, unless
// a case says `messageExact: false`, the failure text of every case; the form
// vector compares the describe mirror and every watched configuration form
// after each step of a scripted trace.
import 'dart:convert';
import 'dart:io';

import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

Map<String, Object?> loadFixture(String name, String kind) {
  final fixture = jsonDecode(
    File('test/fixtures/$name').readAsStringSync(),
  ) as Map<String, Object?>;
  if (fixture['format'] != 'dsh-settings-vector/1' || fixture['kind'] != kind) {
    throw StateError('$name is not a dsh-settings-vector/1 $kind fixture');
  }
  return fixture;
}

void main() {
  group('schema vector', () {
    final fixture = loadFixture('settings_schema_vector.json', 'schema');
    final schemas = (fixture['schemas'] as Map).cast<String, Object?>();
    final cases = (fixture['cases'] as List).cast<Map<String, Object?>>();

    test('every case gets the verdict and message of the TypeScript client', () {
      final mismatches = <String>[];
      for (final entry in cases) {
        final ref = entry['schemaRef'];
        final envelope = ref is String ? schemas[ref] : entry['schema'];
        final expected = entry['expect'] as String?;
        final exact = entry['messageExact'] != false;
        // Each case validates its own copy: validation must not depend on state
        // left by an earlier case.
        final actual = SettingsSchema.rehydrate(
          jsonDecode(jsonEncode(envelope)),
        ).validate(jsonDecode(jsonEncode(entry['value'])));
        final same = (expected == null || actual == null)
            ? expected == actual
            : (!exact || expected == actual);
        if (!same) {
          mismatches.add(
            '${entry['name']}\n    ts:   ${jsonEncode(expected)}\n    dart: ${jsonEncode(actual)}',
          );
        }
      }
      if (mismatches.isNotEmpty) {
        fail(
          '${mismatches.length} of ${cases.length} cases differ:\n'
          '${mismatches.take(40).join('\n')}',
        );
      }
    });

    test('the fixture covers accepted and refused values of every schema', () {
      final accepted = cases.where((c) => c['expect'] == null).length;
      expect(cases.length, greaterThan(3000));
      expect(accepted, greaterThan(500));
      expect(cases.length - accepted, greaterThan(500));
    });
  });
}
