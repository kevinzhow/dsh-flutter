import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Brightness, Color, FontWeight;

import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final resolved = officialPack.resolve(builtInPacks);

  group('official pack', () {
    test('the committed JSON asset equals the generated Dart const', () {
      final asset = jsonDecode(
        File('assets/themes/official.theme.json').readAsStringSync(),
      );
      expect(asset, officialPackData);
    });

    test('has every contract name in both modes', () {
      expect(dshContractNames, isNotEmpty);
      expect(dshContractNames.toSet().length, dshContractNames.length);
      for (final tables in [resolved.light, resolved.dark]) {
        for (final name in dshContractNames) {
          expect(
            tables.contains(name, dshContractKinds[name]!),
            isTrue,
            reason: name,
          );
        }
        expect(
          tables.length,
          dshContractNames.length,
          reason: 'no token outside the contract',
        );
      }
    });

    test('contract names keep dsh spelling', () {
      expect(
        dshContractNames,
        containsAll([
          '--dsw-alias-bg-base',
          '--dsw-radius-md',
          '--dsw-focus-ring-width',
        ]),
      );
      expect(
        dshContractNames.every(
          (n) => RegExp(r'^--(ds|dsh|dsw|shiki)-').hasMatch(n),
        ),
        isTrue,
      );
    });

    test('records its provenance', () {
      expect(officialPack.source['commit'], matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(officialPack.id, officialPackId);
    });

    test('light and dark resolve to different palettes (values from design-platform.css)', () {
      final light = resolveTheme(
        officialPack,
        ThemeSettings(preference: ThemePreference.light),
        Brightness.dark,
      );
      final dark = resolveTheme(
        officialPack,
        ThemeSettings(preference: ThemePreference.dark),
        Brightness.light,
      );
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.bgBase, const Color(0xffffffff));
      expect(dark.bgBase, const Color(0xff151517));
      expect(light.labelPrimary, const Color(0xff0f1115));
      expect(dark.labelPrimary, const Color(0xfff9fafb));
      expect(light.focusRingColor, const Color(0xff4176e6));
      expect(dark.focusRingColor, const Color(0xff7aaaff));
      // A token that differs in the static palette itself (neutral-bluish-60).
      expect(
        light.color('--dsw-static-neutral-bluish-60'),
        const Color(0xfff5f6f7),
      );
      expect(
        dark.color('--dsw-static-neutral-bluish-60'),
        const Color(0xfff9fafb),
      );
    });

    test('alpha tokens keep their fractional alpha', () {
      final light = resolveTheme(
        officialPack,
        ThemeSettings(preference: ThemePreference.light),
        Brightness.light,
      );
      expect(light.color('--dsw-alias-border-l1').a, closeTo(0.04, 1e-9));
      expect(
        light.color('--dsw-alias-bg-document-selection').a,
        closeTo(0.4, 1e-9),
      );
      expect(light.color('--dsw-alias-bg-mask-drop').a, closeTo(0.7, 1e-9));
    });

    test('numbers, shadows and gradients come through', () {
      final t = resolveTheme(
        officialPack,
        ThemeSettings(preference: ThemePreference.light),
        Brightness.light,
      );
      expect(
        [t.radiusSm, t.radiusMd, t.radiusLg, t.radiusXl, t.radiusPanel],
        [8, 12, 16, 20, 28],
      );
      expect(t.focusRingWidth, 2);
      expect(
        t.duration('--ds-transition-duration'),
        const Duration(milliseconds: 200),
      );
      expect(t.shadow('--dsw-shadow-lv2'), hasLength(2));
      expect(t.shadow('--dsw-elevation-panel'), hasLength(3));
      expect(t.shadow('--dsw-elevation-stroke').single.spread, 0.5);
      expect(t.gradients['--dsw-linear-gradient-think']!.stops, hasLength(2));
      expect(t.string('--dsw-corner-shape'), 'superellipse(1.5)');
    });

    test('the elevation stroke follows the mode (border-l4)', () {
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
      expect(
        light.shadow('--dsw-elevation-stroke').single.color,
        light.color('--dsw-alias-border-l4'),
      );
      expect(
        dark.shadow('--dsw-elevation-stroke').single.color,
        dark.color('--dsw-alias-border-l4'),
      );
    });

    test('the type ladder scales with the size settings', () {
      TypeStyleValue style(String name) => resolved.light.typography[name]!;
      final base = resolveTheme(
        officialPack,
        ThemeSettings(preference: ThemePreference.light),
        Brightness.light,
      );
      final big = resolveTheme(
        officialPack,
        ThemeSettings(
          preference: ThemePreference.light,
          fontSize: 18,
          codeFontSize: 14,
        ),
        Brightness.light,
      );
      // text 14 -> 18 moves the content ladder by +4px; fixed steps stay put.
      expect(base.textStyle('--dsw-font-markdown-h1').fontSize, 21);
      expect(big.textStyle('--dsw-font-markdown-h1').fontSize, 25);
      expect(base.textStyle('--dsw-font-markdown-base').fontSize, 14);
      expect(big.textStyle('--dsw-font-markdown-base').fontSize, 18);
      expect(big.textStyle('--dsw-font-s-14').fontSize, 14);
      // secondary tier: 14 -> 13, 18 -> 16.
      expect(base.textStyle('--dsw-font-markdown-table').fontSize, 13);
      expect(big.textStyle('--dsw-font-markdown-table').fontSize, 16);
      // code: 11 -> 14 moves code-block by +3.
      expect(base.textStyle('--dsw-font-markdown-code-block').fontSize, 11);
      expect(big.textStyle('--dsw-font-markdown-code-block').fontSize, 14);
      expect(big.textStyle('--dsw-font-markdown-code').fontSize, 15);
      // line height follows the same delta: base 24px at 14px text.
      final lineBase = base.textStyle('--dsw-font-markdown-base');
      expect(lineBase.height! * lineBase.fontSize!, closeTo(24, 1e-9));
      expect(style('--dsw-font-markdown-code').role, FontRole.code);
      expect(
        base.textStyle('--dsw-font-s-strong-14').fontWeight,
        FontWeight.w500,
      );
    });

    test('secondary size matches dsh (10->9, 14->13, 15->13, 22->20)', () {
      expect([10, 14, 15, 22].map(secondarySize), [9, 13, 13, 20]);
    });
  });
}
