import 'dart:async';

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<BuildContext> pumpHome(
    WidgetTester t, {
    required WidgetBuilder dialog,
    FocusNode? opener,
    FocusNode? other,
    ValueListenable<bool>? showOpener,
    GlobalKey? openerBoundary,
  }) async {
    late BuildContext home;
    await t.pumpWidget(
      dshTestApp(
        Builder(
          builder: (context) {
            home = context;
            Widget trigger() {
              final button = DshButton(
                focusNode: opener,
                onPressed: () => unawaited(
                  showDshDialog<void>(
                    context,
                    label: 'Parent dialog',
                    builder: dialog,
                    restoreFocus: opener,
                  ),
                ),
                child: const Text('Open dialog'),
              );
              return openerBoundary == null
                  ? button
                  : RepaintBoundary(
                      key: openerBoundary,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: button,
                      ),
                    );
            }

            return Column(
              children: [
                if (other != null)
                  DshButton(
                    focusNode: other,
                    onPressed: () {},
                    child: const Text('Other'),
                  ),
                if (showOpener == null)
                  trigger()
                else
                  ValueListenableBuilder<bool>(
                    valueListenable: showOpener,
                    builder: (_, visible, _) =>
                        visible ? trigger() : const SizedBox(),
                  ),
              ],
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    return home;
  }

  Widget twoControls(
    FocusNode first,
    FocusNode last, {
    bool autofocus = true,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Parent body'),
      DshButton(
        focusNode: first,
        autofocus: autofocus,
        onPressed: () {},
        child: const Text('First'),
      ),
      DshButton(focusNode: last, onPressed: () {}, child: const Text('Last')),
    ],
  );

  testWidgets('entry focuses the first control without caller autofocus', (
    t,
  ) async {
    final first = FocusNode(), last = FocusNode();
    addTearDown(first.dispose);
    addTearDown(last.dispose);
    await pumpHome(
      t,
      dialog: (_) => twoControls(first, last, autofocus: false),
    );
    await t.tap(find.text('Open dialog'));
    await t.pumpAndSettle();
    expect(first.hasPrimaryFocus, isTrue);
  });

  testWidgets('Tab and Shift+Tab stay within the foreground dialog', (t) async {
    final opener = FocusNode(), first = FocusNode(), last = FocusNode();
    addTearDown(opener.dispose);
    addTearDown(first.dispose);
    addTearDown(last.dispose);
    await pumpHome(t, opener: opener, dialog: (_) => twoControls(first, last));
    opener.requestFocus();
    await t.pump();
    await t.tap(find.text('Open dialog'));
    await t.pumpAndSettle();
    expect(first.hasPrimaryFocus, isTrue);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pumpAndSettle();
    expect(last.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    expect(first.hasPrimaryFocus, isTrue);
    expect(opener.hasFocus, isFalse);
  });

  testWidgets('modified Escape leaves the modal open', (t) async {
    final first = FocusNode(), last = FocusNode();
    addTearDown(first.dispose);
    addTearDown(last.dispose);
    await pumpHome(t, dialog: (_) => twoControls(first, last));
    await t.tap(find.text('Open dialog'));
    await t.pumpAndSettle();
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.shiftLeft,
    ]) {
      await t.sendKeyDownEvent(modifier);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.sendKeyUpEvent(modifier);
      await t.pumpAndSettle();
      expect(find.text('Parent body'), findsOneWidget);
    }
  });

  testWidgets('a focused local handler can consume Escape before dismissal', (
    t,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pumpHome(
      t,
      dialog: (_) => Focus(
        focusNode: focus,
        autofocus: true,
        onKeyEvent: (_, event) => event.logicalKey == LogicalKeyboardKey.escape
            ? KeyEventResult.handled
            : KeyEventResult.ignored,
        child: const Text('Locally handled'),
      ),
    );
    await t.tap(find.text('Open dialog'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Locally handled'), findsOneWidget);
  });

  testWidgets('a newer local menu owns Escape ahead of its dialog', (t) async {
    final menuFocus = FocusNode();
    addTearDown(menuFocus.dispose);
    await pumpHome(
      t,
      dialog: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Parent body'),
          DshMenu(
            entries: const [DshMenuItem('one', 'Menu item')],
            onSelect: (_) {},
            builder: (_, menu) => DshButton(
              focusNode: menuFocus,
              autofocus: true,
              onPressed: menu.toggle,
              child: const Text('Open menu'),
            ),
          ),
        ],
      ),
    );
    await t.tap(find.text('Open dialog'));
    await t.pumpAndSettle();
    await t.tap(find.text('Open menu'));
    await t.pumpAndSettle();
    expect(find.text('Menu item'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Menu item'), findsNothing);
    expect(find.text('Parent body'), findsOneWidget);
    expect(menuFocus.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Parent body'), findsNothing);
  });

  testWidgets(
    'Escape closes only the child and restores both keyboard openers',
    (t) async {
      final root = FocusNode(), childOpener = FocusNode(), child = FocusNode();
      addTearDown(root.dispose);
      addTearDown(childOpener.dispose);
      addTearDown(child.dispose);
      await pumpHome(
        t,
        opener: root,
        dialog: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Parent body'),
            DshButton(
              focusNode: childOpener,
              autofocus: true,
              onPressed: () => unawaited(
                showDshDialog<void>(
                  context,
                  label: 'Child dialog',
                  builder: (_) => DshButton(
                    focusNode: child,
                    autofocus: true,
                    onPressed: () {},
                    child: const Text('Child body'),
                  ),
                ),
              ),
              child: const Text('Open child'),
            ),
          ],
        ),
      );
      root.requestFocus();
      await t.pump();
      await t.tap(find.text('Open dialog'));
      await t.pumpAndSettle();
      expect(childOpener.hasPrimaryFocus, isTrue);
      await t.tap(find.text('Open child'));
      await t.pumpAndSettle();
      expect(child.hasPrimaryFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Child body'), findsNothing);
      expect(find.text('Parent body'), findsOneWidget);
      expect(childOpener.hasPrimaryFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Parent body'), findsNothing);
      expect(root.hasPrimaryFocus, isTrue);
    },
  );

  testWidgets(
    'a held Escape never dismisses the parent after closing its child',
    (t) async {
      final parent = FocusNode(), child = FocusNode();
      addTearDown(parent.dispose);
      addTearDown(child.dispose);
      await pumpHome(
        t,
        dialog: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Parent body'),
            DshButton(
              focusNode: parent,
              autofocus: true,
              onPressed: () => unawaited(
                showDshDialog<void>(
                  context,
                  label: 'Child dialog',
                  builder: (_) => DshButton(
                    focusNode: child,
                    autofocus: true,
                    onPressed: () {},
                    child: const Text('Child body'),
                  ),
                ),
              ),
              child: const Text('Open child'),
            ),
          ],
        ),
      );
      await t.tap(find.text('Open dialog'));
      await t.pumpAndSettle();
      await t.tap(find.text('Open child'));
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.escape);
      try {
        await t.pumpAndSettle();
        expect(find.text('Child body'), findsNothing);
        expect(find.text('Parent body'), findsOneWidget);
        await t.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.text('Parent body'), findsOneWidget);
      } finally {
        await t.sendKeyUpEvent(LogicalKeyboardKey.escape);
      }
    },
  );

  testWidgets(
    'Escape during an active IME composition does not close the dialog',
    (t) async {
      final controller = TextEditingController();
      final input = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(input.dispose);
      await pumpHome(
        t,
        dialog: (_) => DshTextField(
          controller: controller,
          focusNode: input,
          autofocus: true,
        ),
      );
      await t.tap(find.text('Open dialog'));
      await t.pumpAndSettle();
      expect(input.hasPrimaryFocus, isTrue);
      t.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'a',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
      );
      await t.pump();
      expect(
        controller.value.composing.isValid &&
            !controller.value.composing.isCollapsed,
        isTrue,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(DshTextField), findsOneWidget);
    },
  );

  testWidgets(
    'an explicit pointer opener is restored rather than previous focus',
    (t) async {
      final opener = FocusNode(),
          other = FocusNode(),
          first = FocusNode(),
          last = FocusNode();
      addTearDown(opener.dispose);
      addTearDown(other.dispose);
      addTearDown(first.dispose);
      addTearDown(last.dispose);
      await pumpHome(
        t,
        opener: opener,
        other: other,
        dialog: (_) => twoControls(first, last),
      );
      other.requestFocus();
      await t.pump();
      expect(other.hasPrimaryFocus, isTrue);
      await t.tap(find.text('Open dialog'));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(opener.hasPrimaryFocus, isTrue);
      expect(other.hasFocus, isFalse);
    },
  );

  testWidgets('the late closing key after composition end does not dismiss', (
    t,
  ) async {
    final controller = TextEditingController();
    final input = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(input.dispose);
    await pumpHome(
      t,
      dialog: (_) => DshTextField(
        controller: controller,
        focusNode: input,
        autofocus: true,
      ),
    );
    await t.tap(find.text('Open dialog'));
    await t.pumpAndSettle();
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'a',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await t.pump();
    expect(controller.value.composing.isCollapsed, isFalse);
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'a',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange.empty,
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(DshTextField), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(DshTextField), findsNothing);
  });

  testWidgets('automatic opener restoration omits a new keyboard outline', (
    t,
  ) async {
    final opener = FocusNode(), first = FocusNode(), last = FocusNode();
    addTearDown(opener.dispose);
    addTearDown(first.dispose);
    addTearDown(last.dispose);
    final boundary = GlobalKey();
    await pumpHome(
      t,
      opener: opener,
      openerBoundary: boundary,
      dialog: (_) => twoControls(first, last),
    );
    Future<List<int>> pixels() async => (await t.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final data = (await image.toByteData())!.buffer.asUint8List().toList();
      image.dispose();
      return data;
    }))!;
    final normal = await pixels();
    await t.tap(find.text('Open dialog'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(opener.hasPrimaryFocus, isTrue);
    expect(await pixels(), normal);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    expect(await pixels(), isNot(normal));
  });

  testWidgets('removing the opener does not steal child focus or restore it', (
    t,
  ) async {
    final visible = ValueNotifier(true);
    final opener = FocusNode(), first = FocusNode(), last = FocusNode();
    addTearDown(visible.dispose);
    addTearDown(opener.dispose);
    addTearDown(first.dispose);
    addTearDown(last.dispose);
    await pumpHome(
      t,
      opener: opener,
      showOpener: visible,
      dialog: (_) => twoControls(first, last),
    );
    opener.requestFocus();
    await t.pump();
    await t.tap(find.text('Open dialog'));
    await t.pumpAndSettle();
    visible.value = false;
    await t.pump();
    expect(first.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNot(opener));
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'removing a dialog below a new route does not restore its opener',
    (t) async {
      final opener = FocusNode(),
          first = FocusNode(),
          last = FocusNode(),
          page = FocusNode();
      addTearDown(opener.dispose);
      addTearDown(first.dispose);
      addTearDown(last.dispose);
      addTearDown(page.dispose);
      late ModalRoute<void> dialogRoute;
      final home = await pumpHome(
        t,
        opener: opener,
        dialog: (context) {
          dialogRoute = ModalRoute.of<void>(context)!;
          return twoControls(first, last);
        },
      );
      await t.tap(find.text('Open dialog'));
      await t.pumpAndSettle();
      expect(first.hasPrimaryFocus, isTrue);
      final navigator = Navigator.of(home);
      unawaited(
        navigator.push(
          PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => Focus(
              focusNode: page,
              autofocus: true,
              child: const Text('New route'),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(page.hasPrimaryFocus, isTrue);
      navigator.removeRoute(dialogRoute);
      await t.pumpAndSettle();
      expect(page.hasPrimaryFocus, isTrue);
      expect(opener.hasFocus, isFalse);
      expect(find.text('New route'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('simultaneous modal entry preserves the foreground autofocus', (
    t,
  ) async {
    final first = FocusNode(), last = FocusNode(), foreground = FocusNode();
    addTearDown(first.dispose);
    addTearDown(last.dispose);
    addTearDown(foreground.dispose);
    await t.pumpWidget(
      dshTestApp(
        Builder(
          builder: (context) => DshButton(
            onPressed: () {
              unawaited(
                showDshDialog<void>(
                  context,
                  label: 'Older modal',
                  builder: (_) => twoControls(first, last, autofocus: false),
                ),
              );
              unawaited(
                showDshDialog<void>(
                  context,
                  label: 'Foreground modal',
                  builder: (_) => DshButton(
                    focusNode: foreground,
                    autofocus: true,
                    onPressed: () {},
                    child: const Text('Foreground control'),
                  ),
                ),
              );
            },
            child: const Text('Open both'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open both'));
    await t.pumpAndSettle();
    expect(foreground.hasPrimaryFocus, isTrue);
    expect(first.hasFocus || last.hasFocus, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Foreground control'), findsNothing);
    expect(find.text('Parent body'), findsOneWidget);
  });

  testWidgets('caption paint remains clear while the modal blocks its clicks', (
    t,
  ) async {
    final scene = GlobalKey();
    var backgroundTaps = 0;
    await t.pumpWidget(
      RepaintBoundary(
        key: scene,
        child: dshTestApp(
          Listener(
            onPointerDown: (_) => backgroundTaps++,
            child: FrameInsetsScope(
              insets: const FrameInsets(chromeTop: 40, overlayTop: 60),
              child: Builder(
                builder: (context) => DshButton(
                  onPressed: () => unawaited(
                    showDshDialog<void>(
                      context,
                      label: 'Caption-safe dialog',
                      builder: (_) => const Text('Dialog content'),
                    ),
                  ),
                  child: const Text('Open caption-safe dialog'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    Future<List<List<int>>> captureColors() async =>
        (await t.runAsync(() async {
          final image =
              await (scene.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = (await image.toByteData())!.buffer.asUint8List();
          List<int> rgb(int x, int y) => bytes.sublist(
            (y * image.width + x) * 4,
            (y * image.width + x) * 4 + 3,
          );
          final result = [rgb(10, 10), rgb(10, 50)];
          image.dispose();
          return result;
        }))!;
    final underlying = await captureColors();
    await t.tap(find.text('Open caption-safe dialog'));
    await t.pumpAndSettle();
    final before = backgroundTaps;
    final colors = await captureColors();
    expect(colors[0], underlying[0]);
    expect(colors[1], isNot(underlying[1]));
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(find.text('Dialog content'), findsOneWidget);
    expect(backgroundTaps, before);
    await t.tapAt(const Offset(10, 100));
    await t.pumpAndSettle();
    expect(find.text('Dialog content'), findsNothing);
    expect(backgroundTaps, before);
  });
}
