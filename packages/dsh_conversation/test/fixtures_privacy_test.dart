import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The committed vectors are public. The recorded trace must carry structure
/// only; the synthetic one is hand-written generic text. Neither may contain
/// tokens, cookies, hosts, addresses or home paths.
void main() {
  final deny = [
    RegExp(r'/home/'),
    RegExp(r'/mnt/'),
    RegExp(r'[?&]token='),
    RegExp('cookie', caseSensitive: false),
    RegExp(r'sk-[A-Za-z0-9]{8}'),
    RegExp(r'https?://'),
    RegExp(r'[A-Za-z0-9._-]+@[A-Za-z0-9-]+\.[a-z]{2,}'),
    RegExp(r'127\.0\.0\.1'),
    RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
  ];

  for (final name in [
    'conversation_edge_vector.json',
    'plan_todo_vector.json',
    'attachment_vector.json',
    'tool_turn_vector.json',
    'input_vector.json',
  ]) {
    test('$name carries nothing private', () {
      final text = File('test/fixtures/$name').readAsStringSync();
      for (final pattern in deny) {
        expect(
          pattern.hasMatch(text),
          isFalse,
          reason: '$pattern must not appear in $name',
        );
      }
    });
  }

  test(
    'the recorded trace is structure only: strings are s<len>, ids or enums',
    () {
      final fixture = jsonDecode(
        File('test/fixtures/tool_turn_vector.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final word = RegExp(r'^(s\d+|[a-z]+-\d+|[A-Za-z0-9/._:-]{1,40})$');
      final leaf = RegExp(r'^s\d+$');
      void walk(Object? v, String key) {
        if (v is Map) {
          v.forEach((k, x) => walk(x, '$k'));
        } else if (v is List) {
          for (final x in v) {
            walk(x, key);
          }
        } else if (v is String) {
          if (key == 'arguments' && v.startsWith('{')) {
            // a tool call's argument keys survive, every value is scrubbed
            final args = jsonDecode(v) as Map<String, Object?>;
            for (final value in args.values) {
              if (value is String) {
                expect(
                  leaf.hasMatch(value),
                  isTrue,
                  reason: 'argument value $value',
                );
              }
            }
            return;
          }
          expect(word.hasMatch(v), isTrue, reason: 'free text under "$key"');
        }
      }

      walk(fixture['steps'], 'steps');
    },
  );
}
