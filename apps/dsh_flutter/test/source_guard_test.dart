import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source guards for the rules every screen follows: colours and type come from
/// the theme contract, and every word a person reads comes from the catalog.
void main() {
  final roots = [
    'lib',
    '../../features/dsh_feature_approval/lib',
    '../../features/dsh_feature_chat/lib',
    '../../features/dsh_feature_conversation/lib',
    '../../features/dsh_feature_session/lib',
    '../../features/dsh_feature_tool/lib',
    '../../features/dsh_feature_user_questions/lib',
    '../../packages/dsh_ui/lib',
  ];
  final files = [
    for (final r in roots)
      ...Directory(r)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
  ];

  String strip(String source) => source
      .replaceAll(RegExp(r'//.*'), '')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

  test('the guard sees the feature sources', () {
    expect(files.length, greaterThan(30));
  });

  test('no hard-coded colours: every colour is a theme token', () {
    final bad = RegExp(
      r'Color\(\s*0x|Colors\.|Color\.fromRGBO|Color\.fromARGB',
    );
    for (final f in files) {
      expect(
        bad.hasMatch(strip(f.readAsStringSync())),
        isFalse,
        reason: '${f.path} hard-codes a colour',
      );
    }
  });

  test('no hard-coded font sizes or families: text styles come from the ladder', () {
    final bad = RegExp(
      r'fontSize\s*:|fontFamily\s*:|TextStyle\(\s*\n?\s*(fontSize|fontFamily)',
    );
    for (final f in files) {
      expect(
        bad.hasMatch(strip(f.readAsStringSync())),
        isFalse,
        reason: '${f.path} hard-codes a font size or family',
      );
    }
  });

  test(
    'no literal user-facing strings: Text, hints and labels read the catalog',
    () {
      final literalText = RegExp(r'''Text\(\s*['"][^'"$]*[A-Za-z]''');
      final literalLabel = RegExp(
        r'''(hintText|semanticLabel|label|tooltip|title)\s*:\s*['"][^'"$]*[A-Za-z]''',
      );
      for (final f in files) {
        final text = strip(f.readAsStringSync());
        expect(
          literalText.hasMatch(text),
          isFalse,
          reason: '${f.path} passes a string literal to Text',
        );
        expect(
          literalLabel.hasMatch(text),
          isFalse,
          reason: '${f.path} has a literal label or hint',
        );
      }
    },
  );
}
