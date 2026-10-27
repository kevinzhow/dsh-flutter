import 'dart:ui' as ui;

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keyboard focus and Space operate a controlled checkbox', (
    t,
  ) async {
    final value = ValueNotifier(false);
    addTearDown(value.dispose);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: value,
            builder: (_, checked, _) => DshCheckbox(
              value: checked,
              onChanged: (next) => value.value = next,
              label: 'Images',
            ),
          ),
        ),
      ),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dsh-checkbox-focus-ring')),
      findsOneWidget,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(value.value, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(value.value, isTrue);
  });

  testWidgets('accessibility action toggles enabled, not disabled, checkbox', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final value = ValueNotifier(false);
    final enabled = ValueNotifier(true);
    addTearDown(() {
      value.dispose();
      enabled.dispose();
    });
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (_, canChange, _) => ValueListenableBuilder<bool>(
              valueListenable: value,
              builder: (_, checked, _) => DshCheckbox(
                value: checked,
                onChanged: canChange ? (next) => value.value = next : null,
                label: 'Images',
              ),
            ),
          ),
        ),
      ),
    );
    var node = t.getSemantics(find.byType(DshCheckbox));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.focus), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await t.pumpAndSettle();
    expect(value.value, isTrue);
    enabled.value = false;
    await t.pumpAndSettle();
    node = t.getSemantics(find.byType(DshCheckbox));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    await t.tap(find.byType(DshCheckbox));
    await t.pumpAndSettle();
    expect(value.value, isTrue);
    semantics.dispose();
  });

  testWidgets('automatic dialog focus stays unoutlined until navigation', (
    t,
  ) async {
    final value = ValueNotifier(false);
    addTearDown(value.dispose);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: value,
                builder: (_, checked, _) => DshCheckbox(
                  value: checked,
                  onChanged: (next) => value.value = next,
                  label: 'Acknowledge',
                  profile: DshCheckboxProfile.riskAcknowledgement,
                  autofocus: true,
                ),
              ),
              DshButton(onPressed: () {}, child: const Text('Cancel')),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final ring = find.byKey(const ValueKey('dsh-checkbox-focus-ring'));
    expect(ring, findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(value.value, isTrue);
    expect(ring, findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pumpAndSettle();
    expect(ring, findsOneWidget);
  });

  testWidgets('risk dialog focuses acknowledgement and gates confirmation', (
    t,
  ) async {
    await t.pumpWidget(
      dshTestApp(
        const Center(
          child: DshRiskDialog(
            title: 'Enable access?',
            description: 'Review the risks.',
            acknowledgeLabel: 'I understand',
            cancelLabel: 'Cancel',
            closeLabel: 'Close',
            confirmLabel: 'Enable',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('risk-confirm'));
    expect(t.widget<DshButton>(confirm).onPressed, isNull);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(t.widget<DshButton>(confirm).onPressed, isNotNull);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(t.widget<DshButton>(confirm).onPressed, isNull);
  });

  testWidgets(
    'native square changes on hover and press, but not while disabled',
    (t) async {
      final enabled = ValueNotifier(true);
      addTearDown(enabled.dispose);
      const boundaryKey = ValueKey('checkbox-repaint');
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: ValueListenableBuilder<bool>(
                valueListenable: enabled,
                builder: (_, canChange, _) => DshCheckbox(
                  value: false,
                  onChanged: canChange ? (_) {} : null,
                  label: 'Images',
                ),
              ),
            ),
          ),
        ),
      );
      Future<List<int>> pixels() async {
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        final captured = await t.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List().toList();
        });
        return captured!;
      }

      await t.pumpAndSettle();
      final normal = await pixels();
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      final center = t.getCenter(
        find.byKey(const ValueKey('dsh-checkbox-box')),
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(center);
      await t.pumpAndSettle();
      final hover = await pixels();
      expect(hover, isNot(orderedEquals(normal)));
      await mouse.down(center);
      await t.pumpAndSettle();
      expect(await pixels(), isNot(orderedEquals(hover)));
      await mouse.up();
      enabled.value = false;
      await t.pumpAndSettle();
      final disabled = await pixels();
      await mouse.moveTo(Offset.zero);
      await t.pumpAndSettle();
      expect(await pixels(), orderedEquals(disabled));
      await mouse.removePointer();
    },
  );
}
