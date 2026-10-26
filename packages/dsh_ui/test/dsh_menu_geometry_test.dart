import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (density, height) in [
    (1.0, 37.0),
    (2.0, 36.5),
    (2.625, 36 + 1 / 2.625),
  ]) {
    testWidgets('source footer reserves its border at ${density}x', (t) async {
      t.view.devicePixelRatio = density;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        dshTestApp(
          const Center(
            child: SizedBox(
              width: 200,
              child: DshMenuFooter(child: SizedBox(height: 30)),
            ),
          ),
        ),
      );
      expect(
        t.getSize(find.byType(DshMenuFooter)).height,
        closeTo(height, .0001),
      );
    });
  }

  testWidgets('separator retains CSS logical height at fractional density', (
    t,
  ) async {
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: DshMenuCard(
            entries: const [
              DshMenuItem('a', 'Alpha'),
              DshMenuSeparator('s'),
              DshMenuItem('b', 'Beta'),
            ],
            onSelect: (_) {},
          ),
        ),
      ),
    );
    // padding 4+4, rows 34+34, margin 3+3, CSS height .5.
    expect(t.getSize(find.byType(DshMenuCard)).height, 82.5);
  });

  for (final (setting, fontSize) in [(14, 12.0), (20, 17.0)]) {
    testWidgets('dock row follows the secondary size at setting $setting', (
      t,
    ) async {
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final theme = resolveTheme(
        officialPack,
        ThemeSettings(fontSize: setting),
        Brightness.light,
      );
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [theme]),
          home: Scaffold(
            body: Center(
              child: DshMenuSurface(
                profile: DshMenuSurfaceProfile.dock,
                child: IntrinsicWidth(
                  child: DshMenuItemButton(
                    profile: DshMenuItemProfile.dock,
                    label: 'Hg',
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final text = t.widget<Text>(find.text('Hg'));
      expect(text.style!.fontSize, fontSize);
      expect(
        t.widget<DshChromeText>(find.byType(DshChromeText)).style!.height,
        kTextHeightNone,
      );
      expect(text.style!.height, greaterThan(0));
      expect(text.strutStyle, isNotNull);
      expect(
        find.byType(DshShadowBox),
        findsNothing,
        reason: 'source dock menu has a border, no elevation',
      );
      // CSS content-box min-width 96, padding 4+4, 1px borders at 1x.
      expect(t.getSize(find.byType(DshMenuSurface)).width, 106);
    });
  }

  testWidgets(
    'menu rows keep distinct semantic bounds inside grouped scrolling content and footer',
    (t) async {
      final semantics = t.ensureSemantics();
      try {
        await t.pumpWidget(
          dshTestApp(
            Center(
              child: SizedBox(
                width: 200,
                child: DshMenuSurface(
                  child: Semantics(
                    container: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SingleChildScrollView(
                          child: DshMenuItemButton(
                            label: 'Alpha',
                            onPressed: () {},
                          ),
                        ),
                        DshMenuFooter(
                          child: DshMenuItemButton(
                            key: const ValueKey('footer-action'),
                            label: 'Add workspace',
                            onPressed: () {},
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final row = t.getSemantics(find.byKey(const ValueKey('footer-action')));
        expect(row.label, 'Add workspace');
        expect(row.rect.height, 34);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('dock Tab traverses without activating; Enter selects once', (
    t,
  ) async {
    var selected = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DshMenuItemButton(
                  profile: DshMenuItemProfile.dock,
                  label: 'Close tab',
                  focusNode: node,
                  onPressed: () => selected++,
                ),
                const Focus(child: SizedBox(width: 20, height: 20)),
              ],
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(selected, 0);
    expect(node.hasPrimaryFocus, isFalse);
    node.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(selected, 1);
    expect(
      dshBaselineNudge(const TextStyle(fontSize: 12, height: kTextHeightNone)),
      0,
    );
  });
}
