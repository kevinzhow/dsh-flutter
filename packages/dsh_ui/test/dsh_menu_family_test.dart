import 'dart:ui' as ui;

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keyboard walks enabled rows, wraps, and selects exactly once', (
    t,
  ) async {
    final picked = <String>[];
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: DshMenuCard(
            autofocus: true,
            entries: const [
              DshMenuItem('a', 'Alpha'),
              DshMenuItem('off', 'Off', disabled: true),
              DshMenuItem('b', 'Beta'),
            ],
            onSelect: picked.add,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    FocusNode focus(String id) => t
        .widget<DshMenuItemButton>(find.byKey(ValueKey('dsh-menu-$id')))
        .focusNode!;
    Future<void> key(LogicalKeyboardKey key) async {
      await t.sendKeyEvent(key);
      await t.pump();
    }

    await key(LogicalKeyboardKey.arrowDown);
    expect(focus('a').hasPrimaryFocus, isTrue);
    await key(LogicalKeyboardKey.arrowDown);
    expect(focus('b').hasPrimaryFocus, isTrue);
    await key(LogicalKeyboardKey.arrowDown);
    expect(focus('a').hasPrimaryFocus, isTrue);
    await key(LogicalKeyboardKey.arrowUp);
    expect(focus('b').hasPrimaryFocus, isTrue);
    await key(LogicalKeyboardKey.home);
    expect(focus('a').hasPrimaryFocus, isTrue);
    await key(LogicalKeyboardKey.end);
    expect(focus('b').hasPrimaryFocus, isTrue);
    for (final k in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.tab,
    ]) {
      await key(k);
    }
    expect(picked, ['b', 'b', 'b']);
    expect(focus('off').hasFocus, isFalse);
  });

  testWidgets('Tab enters a menu and modified navigation leaves it alone', (
    t,
  ) async {
    final picked = <String>[];
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: DshMenuCard(
            autofocus: true,
            entries: const [
              DshMenuItem('a', 'Alpha'),
              DshMenuItem('b', 'Beta'),
            ],
            onSelect: picked.add,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    final first = t
        .widget<DshMenuItemButton>(find.byKey(const ValueKey('dsh-menu-a')))
        .focusNode!;
    expect(first.hasPrimaryFocus, isTrue);
    expect(picked, isEmpty);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    expect(first.hasPrimaryFocus, isTrue);
  });

  for (final shiftTab in [false, true]) {
    testWidgets(
      '${shiftTab ? 'Shift Tab' : 'Escape'} closes and restores anchor focus',
      (t) async {
        final anchor = FocusNode();
        addTearDown(anchor.dispose);
        await t.pumpWidget(
          dshTestApp(
            Align(
              alignment: Alignment.topLeft,
              child: DshMenu(
                entries: const [DshMenuItem('a', 'Alpha')],
                onSelect: (_) {},
                builder: (_, menu) => Focus(
                  focusNode: anchor,
                  autofocus: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: menu.toggle,
                    child: const SizedBox(
                      key: ValueKey('anchor'),
                      width: 30,
                      height: 30,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(
          find
              .ancestor(
                of: find.byKey(const ValueKey('anchor')),
                matching: find.byType(GestureDetector),
              )
              .first,
        );
        await t.pumpAndSettle();
        expect(find.text('Alpha'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pump();
        expect(
          t
              .widget<DshMenuItemButton>(
                find.byKey(const ValueKey('dsh-menu-a')),
              )
              .focusNode!
              .hasPrimaryFocus,
          isTrue,
        );
        if (shiftTab) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await t.sendKeyEvent(
          shiftTab ? LogicalKeyboardKey.tab : LogicalKeyboardKey.escape,
        );
        if (shiftTab) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await t.pumpAndSettle();
        expect(find.text('Alpha'), findsNothing);
        expect(anchor.hasPrimaryFocus, isTrue);
      },
    );
  }

  for (final (dense, compact, height, font, line) in [
    (false, false, 34.0, 13.0, 20.0),
    (true, false, 30.0, 13.0, 20.0),
    (false, true, 24.0, 11.0, 17.0),
  ]) {
    testWidgets('published row dimensions dense=$dense compact=$compact', (
      t,
    ) async {
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: SizedBox(
              width: 240,
              child: DshMenuItemButton(
                label: 'Alpha',
                icon: DshIcons.download,
                onPressed: () {},
                dense: dense,
                compact: compact,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(DshMenuItemButton)).height, height);
      final label = t.widget<Text>(find.text('Alpha'));
      expect(label.style!.fontSize, font);
      expect(label.style!.height, line / font);
      expect(t.widget<DshIcon>(find.byType(DshIcon)).size, compact ? 12 : 14);
    });
  }

  testWidgets(
    'published add-plugin row has its own height and description typography',
    (t) async {
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: SizedBox(
              width: 280,
              child: DshMenuSurface(
                child: DshMenuItemButton(
                  label: 'Install',
                  description: 'From a package',
                  icon: DshIcons.download,
                  profile: DshMenuItemProfile.addPlugin,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(DshMenuItemButton)).height, 72);
      expect(t.widget<Text>(find.text('Install')).style!.fontSize, 13);
      final description = t.widget<Text>(find.text('From a package')).style!;
      expect(description.fontSize, 12);
      expect(description.height, 18 / 12);
      // The material clips its background only, not the contributed row/content.
      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        find.ancestor(
          of: find.byType(DshMenuItemButton),
          matching: find.byType(ClipPath),
        ),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'disabled row cannot activate; selected fill replaces its check',
    (t) async {
      var picked = 0;
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: SizedBox(
              width: 240,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DshMenuItemButton(
                    label: 'Off',
                    disabled: true,
                    onPressed: () => picked++,
                  ),
                  DshMenuItemButton(
                    label: 'Selected',
                    selected: true,
                    selectionFill: true,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Off'));
      await t.pump();
      expect(picked, 0);
      expect(
        t
            .widget<Opacity>(
              find.descendant(
                of: find.widgetWithText(DshMenuItemButton, 'Off'),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        .4,
      );
      expect(find.byType(DshIcon), findsNothing);
    },
  );

  testWidgets(
    'optional shadow shape preserves the default rounded decoration',
    (t) async {
      await t.pumpWidget(
        dshTestApp(
          const Center(
            child: DshShadowBox(
              color: Color(0xff112233),
              radius: 8,
              shadows: [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
              child: SizedBox(width: 120, height: 50),
            ),
          ),
        ),
      );
      expect(
        t.widget<DshDecoratedBox>(find.byType(DshDecoratedBox)).decoration,
        isA<BoxDecoration>(),
      );
      // Force a raster paint, covering both exterior shadow and translucent fill paths.
      final boundary = t.renderObject(find.byType(DshShadowBox));
      expect(boundary.paintBounds.size, const ui.Size(120, 50));
      expect(t.takeException(), isNull);
    },
  );
}
