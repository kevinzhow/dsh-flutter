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

BoxDecoration surface(WidgetTester tester) =>
    tester.widget<DecoratedBox>(find.byKey(DshButton.surfaceKey)).decoration
        as BoxDecoration;

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
        expect(
          surface(tester).borderRadius,
          BorderRadius.circular(theme.radiusMd),
        );
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
      expect(surface(tester).border, isNull);
      expect(textColor(tester), theme.labelPrimary);

      await pump(DshButtonVariant.outline);
      expect(surface(tester).color, isNull);
      final border = surface(tester).border! as Border;
      expect(border.top.color, theme.borderL3);
      expect(border.top.width, 0.5);

      await pump(DshButtonVariant.toolbar);
      expect(
        surface(tester).color,
        theme.color('--dsw-alias-button-tool-bar-fill'),
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
      expect(surface(tester).borderRadius, BorderRadius.circular(12));
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
      expect(surface(tester).borderRadius, BorderRadius.circular(8));
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
        expect(surface(tester).color, theme.interactiveBgHover);
        await mouse.down(center);
        await tester.pump();
        expect(surface(tester).color, theme.interactiveBgActive);
        await mouse.up();
        await tester.pump();
        expect(taps, 1);
        expect(surface(tester).color, theme.interactiveBgHover);
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
        final ring =
            tester
                    .widget<DecoratedBox>(find.byKey(DshButton.focusRingKey))
                    .decoration
                as BoxDecoration;
        final border = ring.border! as Border;
        expect(border.top.width, theme.focusRingWidth);
        expect(border.top.color, theme.focusRingColor);
        expect(border.top.color, const Color(0xff4176e6));
        expect(
          tester.getSize(find.byKey(DshButton.focusRingKey)).height,
          36 + 2 * theme.focusRingWidth,
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
        expect(surface(tester).borderRadius, BorderRadius.circular(3));

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.byKey(DshButton.surfaceKey)));
        await tester.pump();
        expect(surface(tester).color, const Color(0xff00ffff));
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
      final ring =
          tester
                  .widget<DecoratedBox>(find.byKey(DshButton.focusRingKey))
                  .decoration
              as BoxDecoration;
      expect((ring.border! as Border).top.color, const Color(0xff00ff00));
      expect((ring.border! as Border).top.width, 5);
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
