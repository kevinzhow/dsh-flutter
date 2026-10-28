import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dsh_button_test.dart' show host, official, surface, textColor;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('iconAction ${brightness.name}: touch-down is source idle', (
      t,
    ) async {
      final theme = official(brightness);
      var calls = 0;
      await t.pumpWidget(
        host(
          theme,
          DshButton(
            profile: DshButtonProfile.iconAction,
            onPressed: () => calls++,
            child: const Text('Go'),
          ),
        ),
      );
      final touch = await t.startGesture(t.getCenter(find.byType(DshButton)));
      await t.pump(const Duration(milliseconds: 100));
      // Actual published touch trace: no :hover during touch-down. Native
      // Chromium's synthetic sticky hover after release remains unmatched.
      expect(surface(t).color, isNull);
      expect(textColor(t), theme.color('--dsw-alias-label-caption'));
      expect(calls, 0);
      await touch.up();
      await t.pump();
      expect(calls, 1);
      expect(surface(t).color, isNull);
    });

    testWidgets('iconAction ${brightness.name}: held mouse follows hover', (
      t,
    ) async {
      final theme = official(brightness);
      var calls = 0;
      await t.pumpWidget(
        host(
          theme,
          DshButton(
            profile: DshButtonProfile.iconAction,
            onPressed: () => calls++,
            child: const Text('Go'),
          ),
        ),
      );
      final button = find.byType(DshButton);
      final bounds = t.getRect(button);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(bounds.center);
      await t.pump();
      final hoverFill = surface(t).color;
      expect(hoverFill, isNotNull);
      expect(textColor(t), theme.labelSecondary);
      await mouse.down(bounds.center);
      await t.pump(const Duration(milliseconds: 100));
      expect(surface(t).color, hoverFill);
      // One pixel beyond the real 28px control, still below drag slop. This
      // proves :active alone does not keep the hover fill/foreground alive.
      await mouse.moveTo(Offset(bounds.left - 1, bounds.center.dy));
      await t.pump();
      expect(surface(t).color, isNull);
      expect(textColor(t), theme.color('--dsw-alias-label-caption'));
      await mouse.moveTo(bounds.center);
      await t.pump();
      expect(surface(t).color, hoverFill);
      await mouse.up();
      await t.pump();
      expect(calls, 1);
      await mouse.removePointer();
    });
  }

  testWidgets(
    'iconAction keyboard and semantics activate once; disabled blocks',
    (t) async {
      final theme = official(Brightness.dark);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var calls = 0;
      Future<void> show(bool enabled) => t.pumpWidget(
        host(
          theme,
          DshButton(
            profile: DshButtonProfile.iconAction,
            focusNode: focus,
            onPressed: enabled ? () => calls++ : null,
            semanticLabel: 'Action',
            child: const Text('Go'),
          ),
        ),
      );
      await show(true);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(focus.hasPrimaryFocus, isTrue);
      expect(find.byKey(DshButton.focusRingKey), findsOneWidget);
      expect(surface(t).color, isNull);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      expect(calls, 2);
      final node = t.getSemantics(find.byType(DshButton));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await t.pump();
      expect(calls, 3);
      await show(false);
      await t.tap(find.byType(DshButton));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      expect(calls, 3);
      expect(
        t
            .getSemantics(find.byType(DshButton))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
    },
  );
}
