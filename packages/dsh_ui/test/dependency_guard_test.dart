import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source guard: theme and ui code stay below the client layers and never
/// branch on a theme name. Greps the files; runs from the package directory
/// (`flutter test`), with a fallback walk up to the repo for other cwds.
Directory packageLib(String package) {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory('${dir.path}/packages/$package/lib');
    if (candidate.existsSync()) return candidate;
    final sibling = Directory('${dir.path}/../$package/lib');
    if (sibling.existsSync()) return sibling;
    dir = dir.parent;
  }
  throw StateError(
    'cannot find packages/$package/lib from ${Directory.current.path}',
  );
}

List<File> dartFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  const forbidden = [
    'package:dsh_client',
    'package:dsh_models',
    'package:dsh_conversation',
    'package:dsh_slots',
  ];
  final themeFiles = dartFiles(packageLib('dsh_theme'));
  final uiFiles = dartFiles(packageLib('dsh_ui'));

  test('the guard sees real files', () {
    expect(themeFiles.length, greaterThan(5));
    expect(uiFiles, isNotEmpty);
  });

  for (final entry in {'dsh_theme': themeFiles, 'dsh_ui': uiFiles}.entries) {
    test(
      '${entry.key}/lib imports nothing from client, models, conversation or slots',
      () {
        for (final file in entry.value) {
          final text = file.readAsStringSync();
          for (final token in forbidden) {
            expect(
              text.contains(token),
              isFalse,
              reason: '${file.path} mentions $token',
            );
          }
        }
      },
    );
  }

  test('dsh_ui/lib never compares against a theme name', () {
    // A quoted theme or pack name, or a packId / pack id comparison, would mean
    // a component branches on which theme is active instead of reading tokens.
    final names = RegExp(r'''['"](official|light|dark|system)['"]''');
    final idCompare = RegExp(
      r'(packId|\.id|themeId)\s*(==|!=)|(==|!=)\s*(packId|themeId)|switch\s*\(\s*[\w.]*(packId|themeId)',
    );
    for (final file in uiFiles) {
      final text = file.readAsStringSync();
      expect(
        names.hasMatch(text),
        isFalse,
        reason: '${file.path} contains a quoted theme name',
      );
      expect(
        idCompare.hasMatch(text),
        isFalse,
        reason: '${file.path} compares a theme id',
      );
      expect(
        text.contains('officialPack'),
        isFalse,
        reason: '${file.path} references the official pack',
      );
    }
  });

  test(
    'dsh_ui/lib reads the theme only through the DshThemeData extension',
    () {
      for (final file in uiFiles) {
        final text = file.readAsStringSync();
        if (text.contains('Theme.of(')) {
          expect(
            text.contains('extension<DshThemeData>()'),
            isTrue,
            reason: file.path,
          );
          expect(
            RegExp(r'Theme\.of\([^)]*\)\.(?!extension)').hasMatch(text),
            isFalse,
            reason: '${file.path} reads Material theme data directly',
          );
        }
      }
    },
  );
}
