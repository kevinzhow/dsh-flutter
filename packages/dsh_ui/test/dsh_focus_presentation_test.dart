import 'dart:async';

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _openerKey = ValueKey('focus-reader-opener');
const _outsideKey = ValueKey('focus-reader-outside');
const _tabsKey = ValueKey('focus-reader-tabs');
const _closeKey = ValueKey('focus-reader-close');

class _ReaderHarness {
  final scene = GlobalKey();
  final opener = FocusNode(debugLabel: 'reader opener');
  final outside = FocusNode(debugLabel: 'outside');
  final initialHighlights = <bool>[];
  bool allowOpen = true;
  bool passiveAfterClose = false;
  int passiveActivations = 0;

  void open(BuildContext context) {
    if (!allowOpen) {
      passiveActivations++;
      return;
    }
    final highlight = dshHasVisibleFocus(opener);
    initialHighlights.add(highlight);
    unawaited(
      showDshReaderDialog<void>(
        context,
        title: 'Standard mode',
        intro: 'Read the preset without changing it.',
        closeLabel: 'Close reader',
        tabsLabel: 'Guide sections',
        identifier: 'focus-reader',
        initialValue: 'explanation',
        initialHighlight: highlight,
        restoreFocus: opener,
        tabsKey: _tabsKey,
        closeKey: _closeKey,
        tabs: const [
          DshReaderTab(
            'explanation',
            'Mode details',
            child: Text('How it works'),
          ),
          DshReaderTab('usage', 'How to use', child: Text('Fix a bug')),
        ],
      ).then((_) {
        if (passiveAfterClose) allowOpen = false;
      }),
    );
  }

  Widget get widget => RepaintBoundary(
    key: scene,
    child: dshTestApp(
      Builder(
        builder: (context) => Column(
          children: [
            DshButton(
              key: _openerKey,
              focusNode: opener,
              onPressed: () => open(context),
              child: const Text('Read preset'),
            ),
            DshButton(
              key: _outsideKey,
              focusNode: outside,
              onPressed: outside.requestFocus,
              child: const Text('Outside'),
            ),
          ],
        ),
      ),
    ),
  );

  void dispose() {
    opener.dispose();
    outside.dispose();
  }
}

void main() {
  Future<_ReaderHarness> pump(WidgetTester t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(800, 760);
    addTearDown(t.view.reset);
    final harness = _ReaderHarness();
    addTearDown(harness.dispose);
    await t.pumpWidget(harness.widget);
    await t.pumpAndSettle();
    return harness;
  }

  Future<TestGesture> mouse(WidgetTester t) async {
    final gesture = await t.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(799, 759));
    addTearDown(gesture.removePointer);
    return gesture;
  }

  Future<void> click(WidgetTester t, TestGesture mouse, Key key) async {
    final point = t.getCenter(find.byKey(key));
    await mouse.moveTo(point);
    await mouse.down(point);
    await mouse.up();
    await mouse.moveTo(const Offset(799, 759));
    await t.pumpAndSettle();
  }

  Finder openerRing() => find.descendant(
    of: find.byKey(_openerKey),
    matching: find.byKey(DshButton.focusRingKey),
  );

  Future<List<int>> tabsPixels(WidgetTester t, _ReaderHarness harness) async {
    final rect = t.getRect(find.byKey(_tabsKey));
    return (await t.runAsync(() async {
      final image =
          await (harness.scene.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      final out = <int>[];
      for (var y = rect.top.floor(); y < rect.bottom.ceil(); y++) {
        out.addAll(
          bytes.sublist(
            (y * image.width + rect.left.floor()) * 4,
            (y * image.width + rect.right.ceil()) * 4,
          ),
        );
      }
      image.dispose();
      return out;
    }))!;
  }

  void initial(WidgetTester t, bool expected) {
    final reader = t.widget<DshDialogReader>(find.byType(DshDialogReader));
    expect(reader.initialHighlight, expected);
    final tabNodes = t
        .widgetList<FocusableActionDetector>(
          find.descendant(
            of: find.byKey(_tabsKey),
            matching: find.byType(FocusableActionDetector),
          ),
        )
        .map((control) => control.focusNode!)
        .toList();
    expect(tabNodes.first.hasPrimaryFocus, isTrue);
    expect(tabNodes.last.hasFocus, isFalse);
  }

  testWidgets(
    'reader inherits the source pointer-close and Escape-close history',
    (t) async {
      final harness = await pump(t);
      final pointer = await mouse(t);
      await click(t, pointer, _openerKey);
      initial(t, false);
      final pointerOpened = await tabsPixels(t, harness);
      await click(t, pointer, _closeKey);
      expect(harness.opener.hasPrimaryFocus, isTrue);
      expect(dshHasVisibleFocus(harness.opener), isFalse);
      expect(openerRing(), findsNothing);

      await click(t, pointer, _openerKey);
      initial(t, false);
      expect(await tabsPixels(t, harness), pointerOpened);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(harness.opener.hasPrimaryFocus, isTrue);
      expect(dshHasVisibleFocus(harness.opener), isTrue);
      expect(openerRing(), findsNothing);

      await click(t, pointer, _openerKey);
      initial(t, true);
      final keyboardOpened = await tabsPixels(t, harness);
      expect(keyboardOpened, isNot(pointerOpened));
      expect(harness.initialHighlights, [false, false, true]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('keyboard opening displays the selected underline immediately', (
    t,
  ) async {
    final harness = await pump(t);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    expect(harness.opener.hasPrimaryFocus, isTrue);
    expect(dshHasVisibleFocus(harness.opener), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    initial(t, true);
    final beforeNavigation = await tabsPixels(t, harness);
    await t.sendKeyEvent(LogicalKeyboardKey.home);
    await t.pumpAndSettle();
    expect(await tabsPixels(t, harness), beforeNavigation);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'a Control-only key does not change pointer-return focus history',
    (t) async {
      final harness = await pump(t);
      final pointer = await mouse(t);
      await click(t, pointer, _openerKey);
      initial(t, false);
      await click(t, pointer, _closeKey);
      expect(harness.opener.hasPrimaryFocus, isTrue);
      expect(dshHasVisibleFocus(harness.opener), isFalse);
      await t.sendKeyEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      await click(t, pointer, _openerKey);
      initial(t, false);
      expect(harness.initialHighlights, [false, false]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('automatic return suppresses outlines until navigation or blur', (
    t,
  ) async {
    final harness = await pump(t)
      ..passiveAfterClose = true;
    final pointer = await mouse(t);
    await click(t, pointer, _openerKey);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(harness.opener.hasPrimaryFocus, isTrue);
    expect(dshHasVisibleFocus(harness.opener), isTrue);
    expect(openerRing(), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(harness.passiveActivations, 1);
    expect(openerRing(), findsNothing);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.home);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(openerRing(), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.home);
    await t.pumpAndSettle();
    expect(openerRing(), findsOneWidget);

    harness.allowOpen = true;
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    initial(t, true);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(openerRing(), findsNothing);
    await click(t, pointer, _outsideKey);
    expect(harness.outside.hasPrimaryFocus, isTrue);
    expect(harness.opener.hasFocus, isFalse);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pumpAndSettle();
    expect(harness.opener.hasPrimaryFocus, isTrue);
    expect(openerRing(), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
