import 'dart:convert';
import 'dart:ui' show Brightness, Color;

import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme text does not inherit ambient Material tracking', () {
    const ambient = TextStyle(letterSpacing: 0.25, wordSpacing: 3);
    for (final mode in Brightness.values) {
      final theme = resolveTheme(officialPack, ThemeSettings(), mode);
      for (final style in [
        theme.textStyle('--dsw-font-s-14'),
        theme.textStyle('--dsw-font-markdown-code-block-small'),
        theme.fixedTextStyle(size: 10, line: 14),
        theme.fixedCodeStyle(size: 11, line: 16),
        theme.terminalTextStyle,
      ]) {
        final merged = ambient.merge(style);
        expect(merged.letterSpacing, 0);
        expect(merged.wordSpacing, 0);
      }
    }
  });

  group('font stacks', () {
    test('built-in stacks when the user lists are empty', () {
      final t = resolveTheme(officialPack, ThemeSettings(), Brightness.light);
      expect(t.fontStacks[FontRole.text]!.first, '-apple-system');
      expect(t.fontStacks[FontRole.code]!.first, 'SF Mono');
      expect(t.fontStacks[FontRole.terminal], [
        'ui-monospace',
        'SFMono-Regular',
        'Menlo',
        'Consolas',
        'monospace',
      ]);
      expect(t.brandFontStack.first, 'Montserrat');
    });

    test('the user list goes in front of the built-in stack', () {
      final t = resolveTheme(
        officialPack,
        ThemeSettings(
          textFontFamily: 'Inter, Noto Sans',
          codeFontFamily: 'Berkeley Mono',
          terminalFontFamily: 'Iosevka',
        ),
        Brightness.light,
      );
      expect(t.fontStacks[FontRole.text]!.take(3), [
        'Inter',
        'Noto Sans',
        '-apple-system',
      ]);
      expect(t.fontStacks[FontRole.code]!.take(2), [
        'Berkeley Mono',
        'SF Mono',
      ]);
      expect(t.fontStacks[FontRole.terminal]!.take(2), [
        'Iosevka',
        'ui-monospace',
      ]);
      final style = t.textStyle('--dsw-font-s-14');
      expect(style.fontFamily, 'Inter');
      expect(style.fontFamilyFallback!.take(2), ['Noto Sans', '-apple-system']);
    });

    test('hostile input is sanitised before it reaches the stack', () {
      final t = resolveTheme(
        officialPack,
        ThemeSettings(textFontFamily: '"Ev\\il"; <script>, '),
        Brightness.light,
      );
      final first = t.fontStacks[FontRole.text]!.first;
      expect(first, 'Evil; script');
      expect(first, isNot(anyOf(contains('"'), contains('<'), contains('\\'))));
    });

    test('clearing the list restores the built-in stack', () {
      final withUser = ThemeSettings(textFontFamily: 'Inter');
      final cleared = withUser.copyWith(textFontFamily: '');
      final t = resolveTheme(officialPack, cleared, Brightness.light);
      expect(t.fontStacks[FontRole.text]!.first, '-apple-system');
    });
  });

  group('system mode', () {
    test('follows the platform brightness', () {
      final settings = ThemeSettings();
      final light = resolveTheme(officialPack, settings, Brightness.light);
      final dark = resolveTheme(officialPack, settings, Brightness.dark);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.bgBase, isNot(dark.bgBase));
    });

    test('an explicit preference ignores the platform', () {
      final t = resolveTheme(
        officialPack,
        ThemeSettings(preference: ThemePreference.dark),
        Brightness.light,
      );
      expect(t.brightness, Brightness.dark);
    });
  });

  group('user pack through the same path', () {
    final source = jsonEncode({
      'format': 'dsh-theme/1',
      'id': 'sunset',
      'name': 'Sunset',
      'version': '1',
      'author': 'someone',
      'extends': 'official',
      'fonts': {
        'text': ['Georgia', 'serif'],
      },
      'common': {
        'numbers': {'--dsw-radius-md': 6},
      },
      'modes': {
        'light': {
          'colors': {
            '--dsw-alias-button-primary-fill': '#c2410c',
            '--dsw-alias-border-l1': 'rgb(194 65 12 / 25%)',
          },
        },
        'dark': {
          'colors': {'--dsw-alias-button-primary-fill': '#fb923c'},
        },
      },
    });

    test('loads from a JSON string and overrides official values', () {
      final pack = ThemePack.parse(source, origin: 'sunset.json');
      final light = resolveTheme(
        pack,
        ThemeSettings(preference: ThemePreference.light),
        Brightness.light,
      );
      final dark = resolveTheme(
        pack,
        ThemeSettings(preference: ThemePreference.dark),
        Brightness.light,
      );
      expect(light.packId, 'sunset');
      expect(
        light.color('--dsw-alias-button-primary-fill'),
        const Color(0xffc2410c),
      );
      expect(
        dark.color('--dsw-alias-button-primary-fill'),
        const Color(0xfffb923c),
      );
      expect(light.color('--dsw-alias-border-l1').a, closeTo(0.25, 1e-9));
      expect(light.radiusMd, 6);
      expect(light.radiusSm, 8, reason: 'inherited from official');
      expect(light.fontStacks[FontRole.text], ['Georgia', 'serif']);
      expect(light.bgBase, const Color(0xffffffff), reason: 'inherited');
    });

    test('errors from a user pack name their file and key', () {
      final broken = source.replaceFirst('#c2410c', 'orange');
      expect(
        () => ThemePack.parse(broken, origin: 'sunset.json'),
        throwsA(
          isA<ThemeException>().having(
            (e) => e.toString(),
            'text',
            startsWith(
              'sunset.json.modes.light.colors.--dsw-alias-button-primary-fill',
            ),
          ),
        ),
      );
    });
  });

  group('DshThemeData', () {
    test('unknown token lookups name the token', () {
      final t = resolveTheme(officialPack, ThemeSettings(), Brightness.light);
      expect(
        () => t.color('--dsw-nope'),
        throwsA(
          isA<ThemeException>().having((e) => e.where, 'where', '--dsw-nope'),
        ),
      );
      expect(
        () => t.number('--dsw-alias-bg-base'),
        throwsA(isA<ThemeException>()),
      );
    });

    test('lerp interpolates colours and numbers, copyWith replaces', () {
      final light = resolveTheme(
        officialPack,
        ThemeSettings(preference: ThemePreference.light),
        Brightness.light,
      );
      final dark = resolveTheme(
        officialPack,
        ThemeSettings(preference: ThemePreference.dark),
        Brightness.light,
      );
      final mid = light.lerp(dark, 0.5);
      expect(mid.bgBase, Color.lerp(light.bgBase, dark.bgBase, 0.5));
      expect(light.lerp(dark, 0), light);
      expect(light.lerp(null, 0.5), same(light));
      final copy = light.copyWith(
        numbers: {...light.numbers, '--dsw-radius-md': 99},
      );
      expect(copy.radiusMd, 99);
      expect(copy.bgBase, light.bgBase);
    });

    test('terminal style uses the terminal size and stack', () {
      final t = resolveTheme(
        officialPack,
        ThemeSettings(terminalFontSize: 16, terminalFontFamily: 'Iosevka'),
        Brightness.light,
      );
      final TextStyle s = t.terminalTextStyle;
      expect(s.fontSize, 16);
      expect(s.fontFamily, 'Iosevka');
    });
  });
}
