import 'dart:ui' show Tristate;

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the button owns its child text as its accessible name', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: DshPill(
            pressed: true,
            onPressed: () {},
            child: const DshChromeText('All'),
          ),
        ),
      ),
    );
    final data = t.getSemantics(find.byType(DshPill)).getSemanticsData();
    expect(data.label, 'All');
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    semantics.dispose();
  });

  testWidgets('static and active pills keep the source geometry', (t) async {
    await t.pumpWidget(
      dshTestApp(
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DshPill(key: ValueKey('plain'), child: Text('Filter')),
              DshPill(
                key: ValueKey('active'),
                active: true,
                child: Text('Filter'),
              ),
              DshPill(
                key: ValueKey('terminal'),
                height: 18,
                child: Text('Status'),
              ),
            ],
          ),
        ),
      ),
    );
    final plain = t.getSize(find.byKey(const ValueKey('plain')));
    expect(plain.height, DshPillRecipe.height);
    expect(
      plain.width,
      t
              .getSize(
                find.descendant(
                  of: find.byKey(const ValueKey('plain')),
                  matching: find.text('Filter'),
                ),
              )
              .width +
          2 * DshPillRecipe.padding,
    );
    expect(t.getSize(find.byKey(const ValueKey('active'))), plain);
    expect(t.getSize(find.byKey(const ValueKey('terminal'))).height, 18);
    expect(find.byType(FocusableActionDetector), findsNothing);
  });

  testWidgets('pointer hides keyboard focus until navigation resumes', (
    t,
  ) async {
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: DshPill(onPressed: () {}, child: const Text('Filter')),
        ),
      ),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    expect(find.byKey(DshPill.focusRingKey), findsOneWidget);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    final center = t.getCenter(find.byType(DshPill));
    await mouse.addPointer(location: center);
    await mouse.down(center);
    await mouse.up();
    await t.pumpAndSettle();
    expect(find.byKey(DshPill.focusRingKey), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(find.byKey(DshPill.focusRingKey), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(find.byKey(DshPill.focusRingKey), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('pointer, keyboard and accessibility operate a pressed pill', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final value = ValueNotifier(false);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: value,
            builder: (_, active, _) => DshPill(
              active: active,
              pressed: active,
              semanticLabel: 'Choose filter',
              onPressed: () => value.value = !value.value,
              child: const Text('Filter'),
            ),
          ),
        ),
      ),
    );
    final pill = find.byType(DshPill);
    var node = t.getSemantics(pill);
    expect(node.getSemanticsData().label, 'Choose filter');
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.focus), isTrue);
    expect(
      node.getSemanticsData().flagsCollection.isSelected,
      Tristate.isFalse,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    expect(find.byKey(DshPill.focusRingKey), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(value.value, isTrue);
    expect(
      t.getSemantics(pill).getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(value.value, isFalse);
    node = t.getSemantics(pill);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await t.pumpAndSettle();
    expect(value.value, isTrue);
    await t.tap(pill);
    await t.pumpAndSettle();
    expect(value.value, isFalse);
    semantics.dispose();
    value.dispose();
  });

  testWidgets(
    'hover wins over active fill and disabled pills cannot activate',
    (t) async {
      var calls = 0;
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: DshPill(
              active: true,
              enabled: false,
              onPressed: () => calls++,
              child: const Text('Filter'),
            ),
          ),
        ),
      );
      final semantics = t.ensureSemantics();
      final pill = find.byType(DshPill);
      final theme = t.element(pill).dsh;
      Color? fill() =>
          (t.widget<DshContainer>(find.byKey(DshPill.surfaceKey)).decoration
                  as BoxDecoration)
              .color;
      expect(fill(), theme.color(DshPillRecipe.activeFillToken));
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: t.getCenter(pill));
      await t.pumpAndSettle();
      expect(fill(), theme.color(DshPillRecipe.hoverToken));
      await t.tap(pill);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pumpAndSettle();
      expect(calls, 0);
      expect(
        t.getSemantics(pill).getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      await mouse.removePointer();
      semantics.dispose();
    },
  );
}
