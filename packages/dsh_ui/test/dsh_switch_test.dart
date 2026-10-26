import 'dart:ui' show Tristate;

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a nested switch draws its own focus ring without the card ring',
    (t) async {
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: DshButton(
              onPressed: () {},
              child: DshSwitch(
                label: 'Nested switch',
                value: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dsh-switch-focus-ring')),
        findsOneWidget,
      );
      expect(find.byKey(DshButton.focusRingKey), findsNothing);
    },
  );

  testWidgets('keyboard focus, Space and Enter operate the named switch', (
    t,
  ) async {
    final value = ValueNotifier(false);
    addTearDown(value.dispose);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: value,
            builder: (_, checked, _) => DshSwitch(
              label: 'Synthetic setting',
              value: checked,
              onChanged: (next) => value.value = next,
            ),
          ),
        ),
      ),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('dsh-switch-focus-ring')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(value.value, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(value.value, isFalse);
  });

  testWidgets('accessibility can activate the switch but not a disabled one', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final value = ValueNotifier(false);
    final enabled = ValueNotifier(true);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (_, canChange, _) => ValueListenableBuilder<bool>(
              valueListenable: value,
              builder: (_, checked, _) => DshSwitch(
                label: 'Synthetic setting',
                value: checked,
                onChanged: canChange ? (next) => value.value = next : null,
              ),
            ),
          ),
        ),
      ),
    );
    var node = t.getSemantics(find.byType(DshSwitch));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.focus), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.focus);
    await t.pumpAndSettle();
    node = t.getSemantics(find.byType(DshSwitch));
    expect(
      t
          .widget<FocusableActionDetector>(find.byType(FocusableActionDetector))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    expect(node.getSemanticsData().flagsCollection.isFocused, Tristate.isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await t.pumpAndSettle();
    expect(value.value, isTrue);
    enabled.value = false;
    await t.pumpAndSettle();
    node = t.getSemantics(find.byType(DshSwitch));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(value.value, isTrue);
    semantics.dispose();
    value.dispose();
    enabled.dispose();
  });

  testWidgets('pointer activation does not draw a keyboard focus ring', (
    t,
  ) async {
    final value = ValueNotifier(false);
    addTearDown(value.dispose);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: value,
            builder: (_, checked, _) => DshSwitch(
              label: 'Synthetic setting',
              value: checked,
              onChanged: (next) => value.value = next,
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byType(DshSwitch));
    await t.pumpAndSettle();
    expect(value.value, isTrue);
    expect(find.byKey(const ValueKey('dsh-switch-focus-ring')), findsNothing);
  });

  testWidgets(
    'pointer input hides the ring until keyboard navigation resumes',
    (t) async {
      final value = ValueNotifier(false);
      addTearDown(value.dispose);
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: value,
              builder: (_, checked, _) => DshSwitch(
                label: 'Synthetic setting',
                value: checked,
                onChanged: (next) => value.value = next,
              ),
            ),
          ),
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      final ring = find.byKey(const ValueKey('dsh-switch-focus-ring'));
      expect(ring, findsOneWidget);
      final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
      final center = t.getCenter(find.byType(DshSwitch));
      await pointer.addPointer(location: center);
      await pointer.down(center);
      await pointer.up();
      await t.pumpAndSettle();
      expect(ring, findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pumpAndSettle();
      expect(ring, findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(ring, findsOneWidget);
      await pointer.removePointer();
    },
  );

  testWidgets('the thumb moves over time and respects reduced motion', (
    t,
  ) async {
    final value = ValueNotifier(false);
    addTearDown(value.dispose);
    Widget control(bool reduced) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: value,
          builder: (_, checked, _) => DshSwitch(
            label: 'Synthetic setting',
            value: checked,
            onChanged: (next) => value.value = next,
          ),
        ),
      ),
    );
    await t.pumpWidget(dshTestApp(control(false)));
    final thumb = find.byKey(const ValueKey('dsh-switch-thumb'));
    final off = t.getCenter(thumb).dx;
    await t.tap(find.byType(DshSwitch));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    final middle = t.getCenter(thumb).dx;
    await t.pumpAndSettle();
    final on = t.getCenter(thumb).dx;
    expect(middle, greaterThan(off));
    expect(middle, lessThan(on));
    expect(on - off, 16);
    await t.pumpWidget(dshTestApp(control(true)));
    await t.tap(find.byType(DshSwitch));
    await t.pump();
    expect(t.getCenter(thumb).dx, off);
  });
}
