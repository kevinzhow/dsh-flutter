import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dsh_button_test.dart' show host, official, surface, textColor;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Header ${brightness.name}: secondary idle/hover and no active fill',
      (t) async {
        final theme = official(brightness);
        var calls = 0;
        await t.pumpWidget(
          host(
            theme,
            DshButton(
              profile: DshButtonProfile.headerAction,
              onPressed: () => calls++,
              child: const Text('Go'),
            ),
          ),
        );
        final button = find.byType(DshButton);
        expect(t.getSize(find.byKey(DshButton.surfaceKey)), const Size(28, 28));
        expect((surface(t).shape as DshCornerBorder).radius, theme.radiusSm);
        expect(textColor(t), theme.labelSecondary);
        expect(surface(t).color, isNull);
        // Touch has no :hover. :active alone does not introduce a fill.
        final touch = await t.startGesture(t.getCenter(button));
        await t.pump(const Duration(milliseconds: 100));
        expect(surface(t).color, isNull);
        await touch.up();
        await t.pump();
        expect(calls, 1);
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(t.getCenter(button));
        await t.pump();
        final hoverFill = DshSurface.quantizeAlpha(theme.interactiveBgHover);
        expect(surface(t).color, hoverFill);
        expect(textColor(t), theme.labelSecondary);
        await mouse.down(t.getCenter(button));
        await t.pump(const Duration(milliseconds: 100));
        expect(surface(t).color, hoverFill);
        await mouse.up();
        await t.pump();
        expect(calls, 2);
        await mouse.moveTo(Offset.zero);
        await t.pump();
        expect(surface(t).color, isNull);
        await mouse.removePointer();
      },
    );
  }

  testWidgets(
    'Header global outline: navigation releases pointer suppression; Enter alone does not',
    (t) async {
      final theme = official(Brightness.dark);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var calls = 0;
      await t.pumpWidget(
        host(
          theme,
          DshButton(
            profile: DshButtonProfile.headerAction,
            focusNode: focus,
            onPressed: () => calls++,
            child: const Text('Go'),
          ),
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      final ring = find.byKey(DshButton.focusRingKey);
      expect(ring, findsOneWidget);
      expect(t.getSize(ring), const Size(30, 30)); // global width2, no offset1
      final decoration =
          t.widget<DshDecoratedBox>(ring).decoration as ShapeDecoration;
      final side = (decoration.shape as DshCornerBorder).side;
      expect(side.width, theme.focusRingWidth);
      expect(side.color, theme.focusRingColor);
      await t.tap(find.byType(DshButton));
      await t.pump();
      expect(focus.hasPrimaryFocus, isTrue);
      expect(ring, findsNothing);
      expect(calls, 1);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(calls, 2);
      expect(ring, findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(ring, findsOneWidget);
      expect(surface(t).color, isNull); // keyboard does not synthesize :hover
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      expect(calls, 3);
    },
  );

  testWidgets('Header disabled has no authored dimming and never activates', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final theme = official(Brightness.light);
    await t.pumpWidget(
      host(
        theme,
        DshSurface(
          color: theme.bgBase,
          child: const DshButton(
            profile: DshButtonProfile.headerAction,
            semanticLabel: 'Header action',
            child: Text('Go'),
          ),
        ),
      ),
    );
    expect(t.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    await t.tap(find.byType(DshButton));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(find.byKey(DshButton.focusRingKey), findsNothing);
    expect(
      t
          .getSemantics(find.byType(DshButton))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(t.getCenter(find.byType(DshButton)));
    await t.pump();
    expect(
      surface(t).color,
      blendLikeChromium(theme.interactiveBgHover, theme.bgBase),
    );
    await pointer.removePointer();
    semantics.dispose();
  });

  testWidgets(
    'a non-navigation key releases Header outline suppression only after focus moves',
    (t) async {
      final first = FocusNode(), second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await t.pumpWidget(
        host(
          official(Brightness.light),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DshButton(
                profile: DshButtonProfile.headerAction,
                focusNode: first,
                onPressed: () {},
                child: const Text('First'),
              ),
              DshButton(
                profile: DshButtonProfile.headerAction,
                focusNode: second,
                onPressed: () {},
                child: const Text('Second'),
              ),
            ],
          ),
        ),
      );
      await t.tap(find.text('First'));
      await t.pump();
      expect(first.hasPrimaryFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.keyA);
      await t.pump();
      expect(find.byKey(DshButton.focusRingKey), findsNothing);
      second.requestFocus();
      await t.pump();
      await t.pump();
      expect(second.hasPrimaryFocus, isTrue);
      expect(find.byKey(DshButton.focusRingKey), findsOneWidget);
    },
  );

  test('Header source profile rejects handwritten metrics', () {
    expect(
      () => DshButton(
        profile: DshButtonProfile.headerAction,
        height: 32,
        onPressed: () {},
        child: const Text('Go'),
      ),
      throwsAssertionError,
    );
  });
}
