import 'dart:convert';
import 'dart:ui' show Brightness, Color;

import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/painting.dart' show Alignment;
import 'package:flutter_test/flutter_test.dart';

String pack({
  String id = 'mine',
  String? extendsId = 'official',
  Map<String, Object?>? common,
  Map<String, Object?>? light,
  Map<String, Object?>? dark,
  Map<String, Object?> extra = const {},
}) => jsonEncode({
  'format': 'dsh-theme/1',
  'id': id,
  'name': 'Mine',
  'version': '1',
  'extends': ?extendsId,
  'common': ?common,
  if (light != null || dark != null) 'modes': {'light': ?light, 'dark': ?dark},
  ...extra,
});

void expectThemeError(void Function() body, {String? where, String? contains}) {
  try {
    body();
  } on ThemeException catch (e) {
    if (where != null) expect(e.where, where);
    if (contains != null) expect(e.toString(), contains2(contains));
    return;
  }
  fail('expected ThemeException');
}

Matcher contains2(String s) => contains(s);

void main() {
  group('parse and validate', () {
    test('minimal user pack parses', () {
      final p = ThemePack.parse(pack());
      expect(p.id, 'mine');
      expect(p.extendsId, 'official');
      expect(p.light.length, 0);
    });

    test('invalid JSON names the origin', () {
      expectThemeError(
        () => ThemePack.parse('{nope', origin: 'my.json'),
        where: 'my.json',
        contains: 'not valid JSON',
      );
    });

    test('wrong format is rejected at format', () {
      expectThemeError(
        () => ThemePack.parse(
          jsonEncode({
            'format': 'raft-theme/1',
            'id': 'x',
            'name': 'x',
            'version': '1',
          }),
        ),
        where: 'theme.format',
      );
    });

    test('unknown top-level key names the key', () {
      expectThemeError(
        () => ThemePack.parse(pack(extra: {'colours': {}})),
        where: 'theme.colours',
      );
    });

    test('unknown token names the full path', () {
      final json = pack(
        light: {
          'colors': {'--dsw-alias-not-a-token': '#fff'},
        },
      );
      expectThemeError(
        () => ThemePack.parse(json),
        where: 'theme.modes.light.colors.--dsw-alias-not-a-token',
        contains: 'unknown token',
      );
    });

    test('token in the wrong table names both kinds', () {
      final json = pack(
        common: {
          'numbers': {'--dsw-alias-bg-base': 3},
        },
      );
      expectThemeError(
        () => ThemePack.parse(json),
        where: 'theme.common.numbers.--dsw-alias-bg-base',
        contains: 'is a color, not a number',
      );
    });

    test('unknown table and unknown mode', () {
      expectThemeError(
        () => ThemePack.parse(pack(common: {'paints': {}})),
        where: 'theme.common.paints',
      );
      expect(
        () => ThemePack.parse(
          jsonEncode({
            'format': 'dsh-theme/1',
            'id': 'x',
            'name': 'x',
            'version': '1',
            'modes': {'sepia': {}},
          }),
        ),
        throwsA(
          isA<ThemeException>().having(
            (e) => e.where,
            'where',
            'theme.modes.sepia',
          ),
        ),
      );
    });

    test('bad colour value names the key', () {
      final json = pack(
        light: {
          'colors': {'--dsw-alias-bg-base': 'chartreuse'},
        },
      );
      expectThemeError(
        () => ThemePack.parse(json),
        where: 'theme.modes.light.colors.--dsw-alias-bg-base',
      );
    });

    test('bad number, type style and font stack', () {
      expectThemeError(
        () => ThemePack.parse(
          pack(
            common: {
              'numbers': {'--dsw-radius-md': 'wide'},
            },
          ),
        ),
        where: 'theme.common.numbers.--dsw-radius-md',
      );
      expectThemeError(
        () => ThemePack.parse(
          pack(
            common: {
              'typography': {
                '--dsw-font-s-14': {
                  'family': 'serif',
                  'size': 14,
                  'line': 22,
                  'weight': 400,
                  'style': 'normal',
                },
              },
            },
          ),
        ),
        where: 'theme.common.typography.--dsw-font-s-14.family',
      );
      expectThemeError(
        () => ThemePack.parse(
          pack(
            extra: {
              'fonts': {'text': []},
            },
          ),
        ),
        where: 'theme.fonts.text',
      );
      expectThemeError(
        () => ThemePack.parse(
          pack(
            extra: {
              'fonts': {
                'comic': ['x'],
              },
            },
          ),
        ),
        where: 'theme.fonts.comic',
      );
    });

    test('a theme cannot extend itself', () {
      expectThemeError(
        () => ThemePack.parse(pack(id: 'a', extendsId: 'a')),
        where: 'theme.extends',
      );
    });
  });

  group('colours', () {
    test('hex, rgb, alpha in three syntaxes', () {
      expect(ColorValue.parse('#fff', where: 'k'), const Color(0xffffffff));
      expect(ColorValue.parse('#0f1115', where: 'k'), const Color(0xff0f1115));
      final a = ColorValue.parse('rgb(0 0 0 / 4%)', where: 'k');
      expect(a.a, closeTo(0.04, 1e-9));
      expect(
        ColorValue.parse('rgba(0, 0, 0, 0.04)', where: 'k').a,
        closeTo(0.04, 1e-9),
      );
      expect(
        ColorValue.parse('rgb(34 197 94 / 0.08)', where: 'k').a,
        closeTo(0.08, 1e-9),
      );
      expect(
        ColorValue.parse('#11223380', where: 'k').a,
        closeTo(128 / 255, 1e-9),
      );
      expect(ColorValue.parse('transparent', where: 'k').a, 0);
    });

    test('format round-trips and keeps fractional alpha', () {
      for (final text in [
        '#0f1115',
        'rgb(0 0 0 / 4%)',
        'rgb(34 197 94 / 12%)',
        'rgb(255 255 255 / 70%)',
      ]) {
        expect(ColorValue.format(ColorValue.parse(text, where: 'k')), text);
      }
    });

    test('garbage names the key', () {
      expect(
        () => ColorValue.parse('#12', where: 'a.b'),
        throwsA(isA<ThemeException>().having((e) => e.where, 'where', 'a.b')),
      );
      expect(
        () => ColorValue.parse(5, where: 'a.b'),
        throwsA(isA<ThemeException>()),
      );
      expect(
        () => ColorValue.parse('rgb(1 2)', where: 'a.b'),
        throwsA(isA<ThemeException>()),
      );
    });
  });

  group('shadows and gradients', () {
    test('shadow list with alpha colours', () {
      final layers = ShadowValue.parseList(
        '0px 4px 12px 0px rgb(0 0 0 / 2%), 0 2px 8px rgba(0, 0, 0, 0.04)',
        where: 'k',
      );
      expect(layers, hasLength(2));
      expect(layers[0].blur, 12);
      expect(layers[0].color.a, closeTo(0.02, 1e-9));
      expect(layers[1].spread, 0);
      expect(ShadowValue.parseList('none', where: 'k'), isEmpty);
      expect(
        ShadowValue.formatList(layers),
        '0px 4px 12px 0px rgb(0 0 0 / 2%), 0px 2px 8px 0px rgb(0 0 0 / 4%)',
      );
    });

    test('shadow without colour fails', () {
      expect(
        () => ShadowValue.parseList('0 2px 4px', where: 'k'),
        throwsA(isA<ThemeException>()),
      );
    });

    test('gradient angle, stops and bare stop lists', () {
      final g = GradientValue.parse(
        'linear-gradient(180deg, #ffffff 20.19%, rgb(255 255 255 / 0%) 100%)',
        where: 'k',
      );
      expect(g.angleDegrees, 180);
      expect(g.stops.first.position, closeTo(0.2019, 1e-9));
      expect(g.stops.last.color.a, 0);
      final lg = g.toLinearGradient();
      expect(lg.begin, Alignment.topCenter);
      expect(lg.end, Alignment.bottomCenter);
      final bare = GradientValue.parse(
        '#2a2fb6 33.102%, #8b76f6 50.954%, #2a2fb6',
        where: 'k',
      );
      expect(bare.angleDegrees, isNull);
      expect(bare.stops.last.position, 1);
    });
  });

  group('inheritance', () {
    test('a pack extending official overrides one token in light only', () {
      final mine = ThemePack.parse(
        pack(
          light: {
            'colors': {'--dsw-alias-button-primary-fill': '#ff0000'},
          },
        ),
      );
      final resolved = mine.resolve(builtInPacks);
      expect(resolved.chain, ['mine', 'official']);
      expect(
        resolved.light.colors['--dsw-alias-button-primary-fill'],
        const Color(0xffff0000),
      );
      expect(
        resolved.dark.colors['--dsw-alias-button-primary-fill'],
        isNot(const Color(0xffff0000)),
      );
      expect(
        resolved.light.colors['--dsw-alias-bg-base'],
        const Color(0xffffffff),
      );
    });

    test('a child common override beats the parent mode value', () {
      final mine = ThemePack.parse(
        pack(
          common: {
            'colors': {'--dsw-alias-bg-layer-2': '#123456'},
          },
        ),
      );
      final resolved = mine.resolve(builtInPacks);
      // Official defines layer-2 per mode; the child's common value wins in both.
      expect(
        resolved.light.colors['--dsw-alias-bg-layer-2'],
        const Color(0xff123456),
      );
      expect(
        resolved.dark.colors['--dsw-alias-bg-layer-2'],
        const Color(0xff123456),
      );
    });

    test('three-level chain resolves nearest first', () {
      final a = ThemePack.parse(
        pack(
          id: 'a',
          light: {
            'colors': {'--dsw-alias-bg-base': '#111111'},
          },
        ),
      );
      final b = ThemePack.parse(
        pack(
          id: 'b',
          extendsId: 'a',
          light: {
            'colors': {
              '--dsw-alias-bg-base': '#222222',
              '--dsw-alias-label-primary': '#333333',
            },
          },
        ),
      );
      final c = ThemePack.parse(
        pack(
          id: 'c',
          extendsId: 'b',
          light: {
            'colors': {'--dsw-alias-label-primary': '#444444'},
          },
        ),
      );
      final resolved = c.resolve({...builtInPacks, 'a': a, 'b': b});
      expect(resolved.chain, ['c', 'b', 'a', 'official']);
      expect(
        resolved.light.colors['--dsw-alias-bg-base'],
        const Color(0xff222222),
      );
      expect(
        resolved.light.colors['--dsw-alias-label-primary'],
        const Color(0xff444444),
      );
    });

    test('an extends cycle is an error that lists the loop', () {
      final a = ThemePack.parse(pack(id: 'a', extendsId: 'b'));
      final b = ThemePack.parse(pack(id: 'b', extendsId: 'a'));
      expectThemeError(
        () => a.resolve({'a': a, 'b': b}),
        where: 'extends',
        contains: 'a -> b -> a',
      );
    });

    test('unknown parent is an error', () {
      final a = ThemePack.parse(pack(id: 'a', extendsId: 'ghost'));
      expectThemeError(
        () => a.resolve(builtInPacks),
        where: 'extends',
        contains: 'ghost',
      );
    });

    test('a standalone pack must be complete', () {
      final partial = ThemePack.parse(
        pack(
          extendsId: null,
          light: {
            'colors': {'--dsw-alias-bg-base': '#fff'},
          },
        ),
      );
      expect(
        () => partial.resolve(),
        throwsA(
          isA<ThemeException>()
              .having((e) => e.where, 'where', 'modes.light')
              .having(
                (e) => e.message,
                'message',
                contains('contract token(s) missing'),
              ),
        ),
      );
    });

    test('resolveTheme folds fonts from the parent', () {
      final mine = ThemePack.parse(
        pack(
          extra: {
            'fonts': {
              'code': ['Berkeley Mono', 'monospace'],
            },
          },
        ),
      );
      final theme = resolveTheme(mine, ThemeSettings(), Brightness.light);
      expect(theme.fontStacks[FontRole.code], ['Berkeley Mono', 'monospace']);
      expect(theme.fontStacks[FontRole.text], contains('sans-serif'));
    });
  });
}
