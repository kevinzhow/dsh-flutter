import 'dart:convert';

import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

DshThemeData official(Brightness b) => resolveTheme(
  officialPack,
  ThemeSettings(
    preference: b == Brightness.dark
        ? ThemePreference.dark
        : ThemePreference.light,
  ),
  Brightness.light,
);

Widget host(DshThemeData theme, Widget child) => MaterialApp(
  theme: ThemeData(extensions: [theme]),
  themeAnimationDuration: Duration.zero,
  home: Scaffold(body: Center(child: child)),
);

ShapeDecoration surface(WidgetTester tester) =>
    tester.widget<DshDecoratedBox>(find.byKey(DshButton.surfaceKey)).decoration
        as ShapeDecoration;

DshCornerBorder shape(WidgetTester tester) =>
    surface(tester).shape as DshCornerBorder;

/// The painted focus ring (a stroke centred on the button's border edge).
DshCornerBorder ring(WidgetTester tester) =>
    (tester
                    .widget<DshDecoratedBox>(find.byKey(DshButton.focusRingKey))
                    .decoration
                as ShapeDecoration)
            .shape
        as DshCornerBorder;

Color? textColor(WidgetTester tester) =>
    DefaultTextStyle.of(tester.element(find.text('Go'))).style.color;

void main() {
  group('tokens drive the look', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('primary under official ${brightness.name}', (tester) async {
        final theme = official(brightness);
        await tester.pumpWidget(
          host(
            theme,
            DshButton(
              variant: DshButtonVariant.primary,
              onPressed: () {},
              child: const Text('Go'),
            ),
          ),
        );
        expect(
          surface(tester).color,
          theme.color('--dsw-alias-button-primary-fill'),
        );
        expect(textColor(tester), theme.labelPrimaryForeground);
        expect(shape(tester).radius, theme.radiusMd);
      });
    }

    testWidgets(
      'light and dark official themes paint different primary fills',
      (tester) async {
        Future<Color?> fill(Brightness b) async {
          await tester.pumpWidget(
            host(
              official(b),
              DshButton(
                variant: DshButtonVariant.primary,
                onPressed: () {},
                child: const Text('Go'),
              ),
            ),
          );
          return surface(tester).color;
        }

        final light = await fill(Brightness.light);
        final dark = await fill(Brightness.dark);
        expect(light, const Color(0xff0f1115));
        expect(dark, const Color(0xfff9fafb));
      },
    );

    testWidgets('variants read their own token families', (tester) async {
      final theme = official(Brightness.light);
      Future<void> pump(DshButtonVariant v) => tester.pumpWidget(
        host(
          theme,
          DshButton(variant: v, onPressed: () {}, child: const Text('Go')),
        ),
      );

      await pump(DshButtonVariant.ghost);
      expect(surface(tester).color, isNull);
      expect(shape(tester).side, BorderSide.none);
      expect(textColor(tester), theme.labelPrimary);

      await pump(DshButtonVariant.outline);
      expect(surface(tester).color, isNull);
      // 0.5px is a whole pixel in Chromium's border snapping.
      final border = shape(tester).side;
      expect(border.color, DshSurface.quantizeAlpha(theme.borderL3));
      expect(
        border.width,
        dshHairlineOf(tester.element(find.byType(DshButton).first)),
      );

      await pump(DshButtonVariant.toolbar);
      expect(
        surface(tester).color,
        DshSurface.quantizeAlpha(
          theme.color('--dsw-alias-button-tool-bar-fill'),
        ),
      );
    });

    testWidgets('sizes: md 36px with radius-md, sm 28px with radius-sm', (
      tester,
    ) async {
      final theme = official(Brightness.light);
      await tester.pumpWidget(
        host(theme, DshButton(onPressed: () {}, child: const Text('Go'))),
      );
      expect(tester.getSize(find.byKey(DshButton.surfaceKey)).height, 36);
      expect(shape(tester).radius, 12);
      await tester.pumpWidget(
        host(
          theme,
          DshButton(
            size: DshButtonSize.sm,
            onPressed: () {},
            child: const Text('Go'),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(DshButton.surfaceKey)).height, 28);
      expect(shape(tester).radius, 8);
      final style = DefaultTextStyle.of(tester.element(find.text('Go'))).style;
      expect(style.fontSize, 12);
    });

    testWidgets('label uses the theme text stack with the user font in front', (
      tester,
    ) async {
      final theme = resolveTheme(
        officialPack,
        ThemeSettings(textFontFamily: 'Inter'),
        Brightness.light,
      );
      await tester.pumpWidget(
        host(theme, DshButton(onPressed: () {}, child: const Text('Go'))),
      );
      final style = DefaultTextStyle.of(tester.element(find.text('Go'))).style;
      expect(style.fontFamily, 'Inter');
      expect(style.fontSize, 14);
    });
  });

  group('states', () {
    testWidgets('hover swaps to the hover token', (tester) async {
      final theme = official(Brightness.light);
      await tester.pumpWidget(
        host(
          theme,
          DshButton(
            variant: DshButtonVariant.primary,
            onPressed: () {},
            child: const Text('Go'),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(DshButton.surfaceKey)));
      await tester.pump();
      expect(
        surface(tester).color,
        theme.color('--dsw-alias-button-primary-hover'),
      );
      await mouse.moveTo(const Offset(2, 2));
      await tester.pump();
      expect(
        surface(tester).color,
        theme.color('--dsw-alias-button-primary-fill'),
      );
    });

    testWidgets(
      'ghost: hover then pressed use the hover and active tokens, tap fires once',
      (tester) async {
        final theme = official(Brightness.dark);
        var taps = 0;
        await tester.pumpWidget(
          host(
            theme,
            DshButton(onPressed: () => taps++, child: const Text('Go')),
          ),
        );
        final center = tester.getCenter(find.byKey(DshButton.surfaceKey));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(center);
        await tester.pump();
        expect(
          surface(tester).color,
          DshSurface.quantizeAlpha(theme.interactiveBgHover),
        );
        await mouse.down(center);
        await tester.pump();
        expect(
          surface(tester).color,
          DshSurface.quantizeAlpha(theme.interactiveBgActive),
        );
        await mouse.up();
        await tester.pump();
        expect(taps, 1);
        expect(
          surface(tester).color,
          DshSurface.quantizeAlpha(theme.interactiveBgHover),
        );
      },
    );

    testWidgets('disabled: dimmed, no hover, no tap', (tester) async {
      final theme = official(Brightness.light);
      await tester.pumpWidget(
        host(
          theme,
          const DshButton(
            variant: DshButtonVariant.primary,
            onPressed: null,
            child: Text('Go'),
          ),
        ),
      );
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.byKey(DshButton.surfaceKey),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        DshButton.disabledOpacity,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(DshButton.surfaceKey)));
      await tester.pump();
      expect(
        surface(tester).color,
        theme.color('--dsw-alias-button-primary-fill'),
      );
      await tester.tap(find.byKey(DshButton.surfaceKey));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'keyboard focus shows a ring of the standard width and focus colour; pointer focus does not',
      (tester) async {
        final theme = official(Brightness.light);
        var activated = 0;
        await tester.pumpWidget(
          host(
            theme,
            DshButton(onPressed: () => activated++, child: const Text('Go')),
          ),
        );
        expect(find.byKey(DshButton.focusRingKey), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final side = ring(tester).side;
        expect(side.width, theme.focusRingWidth);
        expect(side.color, theme.focusRingColor);
        expect(side.color, const Color(0xff4176e6));
        // `outline-style: auto`: centred on the border edge, so half the
        // ring is outside the button and half inside.
        expect(
          tester.getSize(find.byKey(DshButton.focusRingKey)).height,
          36 + theme.focusRingWidth,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        expect(activated, 2);
      },
    );
  });

  group('no branching on theme names', () {
    final syntheticSource = jsonEncode({
      'format': 'dsh-theme/1',
      'id': 'synthetic',
      'name': 'Synthetic',
      'version': '1',
      'extends': 'official',
      'common': {
        'numbers': {
          '--dsw-radius-md': 3,
          '--dsw-radius-sm': 1,
          '--dsw-focus-ring-width': 5,
        },
      },
      'modes': {
        'light': {
          'colors': {
            '--dsw-alias-button-primary-fill': '#ff00ff',
            '--dsw-alias-button-primary-hover': '#00ffff',
            '--dsw-alias-label-primary-foreground': '#010203',
            '--dsw-alias-state-business-primary': '#00ff00',
          },
        },
      },
    });

    testWidgets(
      'a user pack with different values renders different colours and geometry',
      (tester) async {
        final synthetic = resolveTheme(
          ThemePack.parse(syntheticSource),
          ThemeSettings(preference: ThemePreference.light),
          Brightness.light,
        );
        final reference = official(Brightness.light);
        await tester.pumpWidget(
          host(
            synthetic,
            DshButton(
              variant: DshButtonVariant.primary,
              onPressed: () {},
              child: const Text('Go'),
            ),
          ),
        );
        expect(surface(tester).color, const Color(0xffff00ff));
        expect(
          surface(tester).color,
          isNot(reference.color('--dsw-alias-button-primary-fill')),
        );
        expect(textColor(tester), const Color(0xff010203));
        expect(shape(tester).radius, 3);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.byKey(DshButton.surfaceKey)));
        await tester.pump();
        expect(surface(tester).color, const Color(0xff00ffff));
      },
    );

    testWidgets(
      'generated button recipe preserves user typography ladder overrides',
      (tester) async {
        final base = official(Brightness.light);
        final altered = base.copyWith(
          typography: {
            ...base.typography,
            '--dsw-font-s-14': const TypeStyleValue(
              role: FontRole.text,
              size: SizeExpr(19),
              line: SizeExpr(27),
              weight: 500,
            ),
          },
        );
        await tester.pumpWidget(
          host(altered, DshButton(onPressed: () {}, child: const Text('Go'))),
        );
        final style = DefaultTextStyle.of(tester.element(find.text('Go')))
            .style;
        expect(style.fontSize, 19);
        expect(style.height, 27 / 19);
        expect(style.fontWeight, FontWeight.w500);
      },
    );

    testWidgets('the focus ring follows the user pack too', (tester) async {
      final synthetic = resolveTheme(
        ThemePack.parse(syntheticSource),
        ThemeSettings(preference: ThemePreference.light),
        Brightness.light,
      );
      await tester.pumpWidget(
        host(synthetic, DshButton(onPressed: () {}, child: const Text('Go'))),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(tester).side.color, const Color(0xff00ff00));
      expect(ring(tester).side.width, 5);
    });

    testWidgets(
      'only values matter: same pack id and brightness, different tokens, different paint',
      (tester) async {
        final base = official(Brightness.light);
        final altered = base.copyWith(
          colors: {
            ...base.colors,
            '--dsw-alias-button-primary-fill': const Color(0xff123456),
          },
        );
        expect(altered.packId, base.packId);
        await tester.pumpWidget(
          host(
            altered,
            DshButton(
              variant: DshButtonVariant.primary,
              onPressed: () {},
              child: const Text('Go'),
            ),
          ),
        );
        expect(surface(tester).color, const Color(0xff123456));
      },
    );

    testWidgets('a missing extension is a clear error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: DshButton(child: Text('Go'))),
      );
      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (e) => e.message,
          'message',
          contains('DshThemeData'),
        ),
      );
    });
  });
}
