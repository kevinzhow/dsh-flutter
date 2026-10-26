import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a bottom tooltip flips above its anchor and stays in the viewport',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(300, 240);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(
        dshTestApp(
          const Stack(
            children: [
              Positioned(
                right: 4,
                bottom: 4,
                child: DshTooltip(
                  label: 'Reference tooltip',
                  side: DshTooltipSide.bottom,
                  child: SizedBox(
                    key: ValueKey('anchor'),
                    width: 30,
                    height: 30,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(
        location: t.getCenter(find.byKey(const ValueKey('anchor'))),
      );
      await t.pumpAndSettle();
      final bubble = find.text('Reference tooltip');
      expect(bubble, findsOneWidget);
      expect(
        t.getBottomLeft(bubble).dy,
        lessThan(t.getTopLeft(find.byKey(const ValueKey('anchor'))).dy),
      );
      expect(t.getTopRight(bubble).dx, lessThanOrEqualTo(288));
      await pointer.removePointer();
    },
  );

  testWidgets('keyboard focus opens and blur dismisses a tooltip', (t) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: DshTooltip(
            label: 'Keyboard hint',
            child: Focus(
              focusNode: focus,
              child: const SizedBox(width: 30, height: 30),
            ),
          ),
        ),
      ),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(find.text('Keyboard hint'), findsOneWidget);
    focus.unfocus();
    await t.pumpAndSettle();
    expect(find.text('Keyboard hint'), findsNothing);
  });

  testWidgets('a click-pinned tooltip dismisses outside and with Escape', (
    t,
  ) async {
    var activations = 0;
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: DshTooltip(
            label: 'Pinned hint',
            openOnClick: true,
            child: GestureDetector(
              key: const ValueKey('pin-anchor'),
              behavior: HitTestBehavior.opaque,
              onTap: () => activations++,
              child: const SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const ValueKey('pin-anchor')));
    await t.pumpAndSettle();
    expect(activations, 1);
    expect(find.text('Pinned hint'), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(find.text('Pinned hint'), findsNothing);
    await t.tap(find.byKey(const ValueKey('pin-anchor')));
    await t.pumpAndSettle();
    expect(activations, 2);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Pinned hint'), findsNothing);
  });

  testWidgets('a nested tooltip suppresses its ancestor while visible', (
    t,
  ) async {
    await t.pumpWidget(
      dshTestApp(
        const Center(
          child: DshTooltip(
            label: 'Outer hint',
            child: SizedBox(
              width: 100,
              height: 60,
              child: Center(
                child: DshTooltip(
                  label: 'Inner hint',
                  child: SizedBox(
                    key: ValueKey('nested-anchor'),
                    width: 30,
                    height: 30,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(
      location: t.getCenter(find.byKey(const ValueKey('nested-anchor'))),
    );
    await t.pumpAndSettle();
    expect(find.text('Inner hint'), findsOneWidget);
    expect(find.text('Outer hint'), findsNothing);
    await pointer.removePointer();
  });

  testWidgets(
    'disabling during hover hides the bubble without replacing the anchor',
    (t) async {
      final disabled = ValueNotifier(false);
      addTearDown(disabled.dispose);
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: disabled,
              builder: (_, value, child) => DshTooltip(
                label: 'Hover hint',
                disabled: value,
                child: child!,
              ),
              child: const SizedBox(
                key: ValueKey('stable-anchor'),
                width: 30,
                height: 30,
              ),
            ),
          ),
        ),
      );
      final anchor = find.byKey(const ValueKey('stable-anchor'));
      final element = t.element(anchor);
      final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: t.getCenter(anchor));
      await t.pumpAndSettle();
      expect(find.text('Hover hint'), findsOneWidget);
      disabled.value = true;
      await t.pumpAndSettle();
      expect(find.text('Hover hint'), findsNothing);
      expect(t.element(anchor), same(element));
      await pointer.removePointer();
    },
  );

  testWidgets('the width cap applies to content before bubble padding', (
    t,
  ) async {
    await t.pumpWidget(
      dshTestApp(
        const Center(
          child: DshTooltip(
            label: 'A long tooltip that must wrap within its content cap',
            maxWidth: 100,
            child: SizedBox(
              key: ValueKey('width-anchor'),
              width: 30,
              height: 30,
            ),
          ),
        ),
      ),
    );
    final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(
      location: t.getCenter(find.byKey(const ValueKey('width-anchor'))),
    );
    await t.pumpAndSettle();
    expect(
      t.getSize(find.byKey(const ValueKey('dsh-tooltip-bubble'))).width,
      114,
    );
    await pointer.removePointer();
  });

  testWidgets(
    'click-readable hover dismisses on Escape, Tab, and outside pointer',
    (t) async {
      await t.pumpWidget(
        dshTestApp(
          const Center(
            child: DshTooltip(
              label: 'Readable hint',
              openOnClick: true,
              child: SizedBox(
                key: ValueKey('readable-anchor'),
                width: 30,
                height: 30,
              ),
            ),
          ),
        ),
      );
      final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: const Offset(5, 5));
      Future<void> hover() async {
        await pointer.moveTo(const Offset(5, 5));
        await t.pump();
        await pointer.moveTo(
          t.getCenter(find.byKey(const ValueKey('readable-anchor'))),
        );
        await t.pumpAndSettle();
        expect(find.text('Readable hint'), findsOneWidget);
      }

      await hover();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Readable hint'), findsNothing);
      await hover();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(find.text('Readable hint'), findsNothing);
      await hover();
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(find.text('Readable hint'), findsNothing);
      await pointer.removePointer();
    },
  );

  testWidgets('pointer-driven refocus stays silent until keyboard input', (
    t,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: DshTooltip(
            label: 'Focus hint',
            child: Focus(
              focusNode: focus,
              child: const SizedBox(width: 30, height: 30),
            ),
          ),
        ),
      ),
    );
    final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(5, 5));
    await pointer.down(const Offset(5, 5));
    await pointer.up();
    focus.requestFocus();
    await t.pumpAndSettle();
    expect(find.text('Focus hint'), findsNothing);
    focus.unfocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    focus.requestFocus();
    await t.pumpAndSettle();
    expect(find.text('Focus hint'), findsOneWidget);
    await pointer.removePointer();
  });

  testWidgets('hover and focus use separate delays and cancel on exit', (
    t,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: DshTooltip(
            label: 'Delayed hint',
            delay: const Duration(milliseconds: 200),
            focusDelay: const Duration(milliseconds: 400),
            child: Focus(
              focusNode: focus,
              child: const SizedBox(
                key: ValueKey('delay-anchor'),
                width: 30,
                height: 30,
              ),
            ),
          ),
        ),
      ),
    );
    final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(
      location: t.getCenter(find.byKey(const ValueKey('delay-anchor'))),
    );
    await t.pump(const Duration(milliseconds: 199));
    expect(find.text('Delayed hint'), findsNothing);
    await pointer.moveTo(const Offset(5, 5));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Delayed hint'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.pump(const Duration(milliseconds: 399));
    expect(find.text('Delayed hint'), findsNothing);
    await t.pump(const Duration(milliseconds: 1));
    await t.pumpAndSettle();
    expect(find.text('Delayed hint'), findsOneWidget);
    focus.unfocus();
    await t.pumpAndSettle();
    expect(find.text('Delayed hint'), findsNothing);
    await pointer.removePointer();
  });

  testWidgets(
    'keyboard activation pins the readable tooltip and still invokes the action',
    (t) async {
      var activations = 0;
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: DshTooltip(
              label: 'Keyboard readable',
              openOnClick: true,
              child: FocusableActionDetector(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                },
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      activations++;
                      return null;
                    },
                  ),
                },
                child: const SizedBox(width: 30, height: 30),
              ),
            ),
          ),
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(find.text('Keyboard readable'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(activations, 1);
      expect(find.text('Keyboard readable'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(activations, 2);
      expect(find.text('Keyboard readable'), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(activations, 3);
      expect(find.text('Keyboard readable'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Keyboard readable'), findsNothing);
    },
  );

  testWidgets('shortcut-only descriptions are exposed to accessibility', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: DshTooltip(
            label: '',
            shortcutKeys: const ['⌘', 'K'],
            child: Semantics(
              button: true,
              label: 'Open',
              child: const SizedBox(width: 30, height: 30),
            ),
          ),
        ),
      ),
    );
    final described = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.tooltip == '⌘ K',
    );
    expect(described, findsOneWidget);
    expect(t.getSemantics(described).getSemanticsData().tooltip, '⌘ K');
    final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: t.getCenter(described));
    await t.pumpAndSettle();
    expect(find.text('⌘'), findsOneWidget);
    expect(find.text('K'), findsOneWidget);
    await pointer.removePointer();
    semantics.dispose();
  });

  testWidgets('a pinned bubble follows a moving anchor', (t) async {
    final top = ValueNotifier(50.0);
    addTearDown(top.dispose);
    await t.pumpWidget(
      dshTestApp(
        ValueListenableBuilder<double>(
          valueListenable: top,
          builder: (_, value, _) => Stack(
            children: [
              Positioned(
                left: 80,
                top: value,
                child: DshTooltip(
                  label: 'Moving hint',
                  side: DshTooltipSide.bottom,
                  openOnClick: true,
                  child: GestureDetector(
                    key: const ValueKey('moving-anchor'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: const SizedBox(width: 30, height: 30),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const ValueKey('moving-anchor')));
    await t.pumpAndSettle();
    final bubble = find.byKey(const ValueKey('dsh-tooltip-bubble'));
    final before = t.getTopLeft(bubble).dy;
    top.value = 120;
    await t.pumpAndSettle();
    expect(t.getTopLeft(bubble).dy - before, closeTo(70, 0.01));
  });

  testWidgets('releasing outside the anchor does not pin a tooltip', (t) async {
    await t.pumpWidget(
      dshTestApp(
        const Center(
          child: DshTooltip(
            label: 'Drag hint',
            openOnClick: true,
            child: SizedBox(
              key: ValueKey('drag-anchor'),
              width: 30,
              height: 30,
            ),
          ),
        ),
      ),
    );
    final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(
      location: t.getCenter(find.byKey(const ValueKey('drag-anchor'))),
    );
    await t.pumpAndSettle();
    expect(find.text('Drag hint'), findsOneWidget);
    await pointer.down(t.getCenter(find.byKey(const ValueKey('drag-anchor'))));
    await pointer.moveTo(const Offset(5, 5));
    await pointer.up();
    await t.pumpAndSettle();
    expect(find.text('Drag hint'), findsNothing);
    await pointer.removePointer();
  });
}
