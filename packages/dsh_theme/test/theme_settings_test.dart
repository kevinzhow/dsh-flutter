import 'dart:ui' show Brightness;

import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('font size ranges (dsh theme-settings.ts)', () {
    test('defaults and ranges', () {
      final s = ThemeSettings();
      expect((s.fontSize, s.codeFontSize, s.terminalFontSize), (14, 11, 13));
      expect(s.preference, ThemePreference.system);
      expect(
        (fontSizeSpecs[FontRole.text]!.min, fontSizeSpecs[FontRole.text]!.max),
        (10, 22),
      );
      expect(
        (fontSizeSpecs[FontRole.code]!.min, fontSizeSpecs[FontRole.code]!.max),
        (10, 16),
      );
      expect(
        (
          fontSizeSpecs[FontRole.terminal]!.min,
          fontSizeSpecs[FontRole.terminal]!.max,
        ),
        (10, 20),
      );
    });

    test('values clamp into the role range', () {
      final low = ThemeSettings(
        fontSize: 3,
        codeFontSize: 3,
        terminalFontSize: 3,
      );
      expect(
        (low.fontSize, low.codeFontSize, low.terminalFontSize),
        (10, 10, 10),
      );
      final high = ThemeSettings(
        fontSize: 99,
        codeFontSize: 99,
        terminalFontSize: 99,
      );
      expect(
        (high.fontSize, high.codeFontSize, high.terminalFontSize),
        (22, 16, 20),
      );
      expect(
        ThemeSettings(
          fontSize: 17,
          codeFontSize: 16,
          terminalFontSize: 20,
        ).fontSizes,
        const FontSizes(text: 17, code: 16, terminal: 20),
      );
    });

    test('isValidFontSize is the strict form', () {
      expect(ThemeSettings.isValidFontSize(FontRole.code, 16), isTrue);
      expect(ThemeSettings.isValidFontSize(FontRole.code, 17), isFalse);
      expect(ThemeSettings.isValidFontSize(FontRole.text, 12.5), isFalse);
      expect(ThemeSettings.isValidFontSize(FontRole.terminal, 9), isFalse);
    });

    test('fromJson clamps ranges but rejects wrong types naming the field', () {
      final s = ThemeSettings.fromJson({'fontSize': 40, 'codeFontSize': 2.4});
      expect((s.fontSize, s.codeFontSize, s.terminalFontSize), (22, 10, 13));
      expect(
        () => ThemeSettings.fromJson({'terminalFontSize': 'big'}),
        throwsA(
          isA<ThemeException>().having(
            (e) => e.where,
            'where',
            'terminalFontSize',
          ),
        ),
      );
      expect(
        () => ThemeSettings.fromJson({'preference': 'sepia'}),
        throwsA(
          isA<ThemeException>().having((e) => e.where, 'where', 'preference'),
        ),
      );
      expect(
        () => ThemeSettings.fromJson({'textFontFamily': 5}),
        throwsA(
          isA<ThemeException>().having(
            (e) => e.where,
            'where',
            'textFontFamily',
          ),
        ),
      );
    });

    test('JSON round trip uses dsh field names', () {
      final s = ThemeSettings(
        preference: ThemePreference.dark,
        fontSize: 16,
        textFontFamily: 'Inter, serif',
      );
      expect(s.toJson(), {
        'preference': 'dark',
        'fontSize': 16,
        'codeFontSize': 11,
        'terminalFontSize': 13,
        'textFontFamily': '"Inter", serif',
        'codeFontFamily': '',
        'terminalFontFamily': '',
      });
      expect(ThemeSettings.fromJson(s.toJson()), s);
    });
  });

  group('font family normalization', () {
    test('quotes names, keeps generics bare', () {
      expect(
        normalizeFontFamily('Fira Code, monospace'),
        '"Fira Code", monospace',
      );
      expect(
        normalizeFontFamily('-apple-system, BlinkMacSystemFont, Inter'),
        '-apple-system, BlinkMacSystemFont, "Inter"',
      );
    });

    test(
      'drops quotes, backslashes, angle brackets and control characters',
      () {
        expect(
          normalizeFontFamily(
            '"Evil\\Font", \'Other\', <b>Tag</b>, Line\u0001Feed\u007f',
          ),
          '"EvilFont", "Other", "bTag/b", "LineFeed"',
        );
      },
    );

    test(
      'empty and blank entries disappear; empty restores the built-in stack',
      () {
        expect(normalizeFontFamily(' , ,  '), '');
        expect(normalizeFontFamily('A,,B'), '"A", "B"');
        expect(normalizeFontFamily(''), '');
      },
    );

    test('whitespace collapses and normalizing is idempotent', () {
      final once = normalizeFontFamily('  JetBrains    Mono ,  sans-serif ');
      expect(once, '"JetBrains Mono", sans-serif');
      expect(normalizeFontFamily(once), once);
    });

    test('names and css round trip', () {
      final list = normalizeFontFamily('A B, serif');
      expect(fontFamilyNames(list), ['A B', 'serif']);
      expect(fontStackCss(fontFamilyNames(list)), list);
    });
  });

  group('preference and snapshot', () {
    test('system follows the platform brightness', () {
      expect(
        resolveBrightness(ThemePreference.system, Brightness.dark),
        Brightness.dark,
      );
      expect(
        resolveBrightness(ThemePreference.system, Brightness.light),
        Brightness.light,
      );
      expect(
        resolveBrightness(ThemePreference.light, Brightness.dark),
        Brightness.light,
      );
      expect(
        resolveBrightness(ThemePreference.dark, Brightness.light),
        Brightness.dark,
      );
    });

    test('snapshot shape follows dsh ThemeSnapshot', () {
      final snap = ThemeSettings(
        fontSize: 15,
        codeFontFamily: 'Menlo',
      ).snapshot(Brightness.dark, revision: 3);
      expect(snap.colorScheme, Brightness.dark);
      expect(snap.toJson(), {
        'preference': 'system',
        'fontSizes': {'text': 15, 'code': 11, 'terminal': 13},
        'fontFamilies': {'text': '', 'code': '"Menlo"', 'terminal': ''},
        'active': {'id': 'dark', 'colorScheme': 'dark'},
        'revision': 3,
      });
    });
  });
}
