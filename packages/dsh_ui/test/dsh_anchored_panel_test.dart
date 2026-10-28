import 'package:dsh_theme/testing.dart';
import 'package:dsh_theme/dsh_theme.dart' show ColorValue;
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final domOffsetGeometry in [false, true]) {
    testWidgets(
      'fractional card uses source DOM placement only when opted in: $domOffsetGeometry',
      (t) async {
        const density = 2.625;
        t.view.physicalSize = const Size(1024, 1050);
        t.view.devicePixelRatio = density;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          dshTestApp(
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DshAnchoredPanel(
                  menuViewport: true,
                  domOffsetGeometry: domOffsetGeometry,
                  side: DshPanelSide.top,
                  gap: 8,
                  builder: (_, panel) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: panel.toggle,
                    child: const SizedBox(
                      key: ValueKey('fractional-anchor'),
                      width: 50,
                      height: 22,
                    ),
                  ),
                  panelBuilder: (_, _) => const SizedBox(
                    key: ValueKey('fractional-card'),
                    width: 300,
                    height: 158 + 1 / density,
                  ),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.byKey(const ValueKey('fractional-anchor')));
        await t.pumpAndSettle();
        final card = t.getRect(find.byKey(const ValueKey('fractional-card')));
        expect(card.width, 300);
        expect(card.height, closeTo(158 + 1 / density, .0001));
        expect(
          card.left,
          closeTo(domOffsetGeometry ? 78 : 78 + .25 / density, .0001),
        );
        expect(
          card.top,
          closeTo(domOffsetGeometry ? 196 : 196 - 1 / density, .0001),
        );
        final firstPixel = (card.left * density + .0001).floor();
        final lastPixel = (card.right * density - .0001).ceil();
        expect(lastPixel - firstPixel, domOffsetGeometry ? 789 : 788);
      },
    );
  }

  testWidgets('static panels retain focus and pass a single outside action', (
    t,
  ) async {
    final first = FocusNode(), second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    var outsideActions = 0;
    await t.pumpWidget(
      dshTestApp(
        Align(
          alignment: Alignment.bottomLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (final (label, focus) in [
                    ('First', first),
                    ('Second', second),
                  ])
                    DshAnchoredPanel(
                      focusPanel: false,
                      exclusiveGroup: #statDialogs,
                      menuViewport: true,
                      side: DshPanelSide.top,
                      builder: (_, panel) => DshButton(
                        focusNode: focus,
                        onPressed: panel.toggle,
                        child: Text(label),
                      ),
                      panelBuilder: (_, _) => SizedBox(
                        width: 100,
                        height: 60,
                        child: Text('$label detail'),
                      ),
                    ),
                ],
              ),
              DshButton(
                onPressed: () => outsideActions++,
                child: const Text('Outside action'),
              ),
            ],
          ),
        ),
      ),
    );
    first.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('First detail'), findsOneWidget);
    expect(first.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(second.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('First detail'), findsNothing);
    expect(find.text('Second detail'), findsOneWidget);
    await t.tap(find.text('First'));
    await t.pumpAndSettle();
    expect(find.text('Second detail'), findsNothing);
    expect(find.text('First detail'), findsOneWidget);
    await t.tap(find.text('Outside action'));
    await t.pumpAndSettle();
    expect(outsideActions, 1);
    expect(find.text('First detail'), findsNothing);
    first.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('First detail'), findsNothing);
    expect(first.hasPrimaryFocus, isTrue);
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });

  testWidgets('root portal retains platform material and live frame insets', (
    t,
  ) async {
    double overlayTop = 68;
    var platform = ShellPlatform.darwin;
    late StateSetter update;
    await t.pumpWidget(
      dshTestApp(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ShellScope(
              chrome: ShellChrome(platform: platform),
              child: FrameInsetsScope(
                insets: FrameInsets(overlayTop: overlayTop),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: DshAnchoredPanel(
                    menuViewport: true,
                    side: DshPanelSide.top,
                    gap: 8,
                    builder: (_, panel) => DshButton(
                      onPressed: panel.toggle,
                      child: const Text('Scoped opener'),
                    ),
                    panelBuilder: (context, _) => ColoredBox(
                      key: const ValueKey('scoped-panel'),
                      color: dshSpecificMenuFillOf(context),
                      child: const SizedBox(width: 200, height: 100),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await t.tap(find.text('Scoped opener'));
    await t.pumpAndSettle();
    final panel = find.byKey(const ValueKey('scoped-panel'));
    expect(t.getTopLeft(panel).dy, 68);
    expect(
      t.widget<ColoredBox>(panel).color,
      ColorValue.parse('#f8f9faf0', where: 'source darwin material'),
    );
    update(() => overlayTop = 90);
    await t.pumpAndSettle();
    expect(t.getTopLeft(panel).dy, 90);
    update(() => platform = ShellPlatform.other);
    await t.pumpAndSettle();
    expect(
      t.widget<ColoredBox>(panel).color,
      ColorValue.parse('#f8f9fa94', where: 'source generic material'),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(panel, findsNothing);
  });

  testWidgets('source-specific anchored gap applies to an intrinsic card', (
    t,
  ) async {
    await t.pumpWidget(
      dshTestApp(
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DshAnchoredPanel(
              menuViewport: true,
              side: DshPanelSide.top,
              align: DshPanelAlign.end,
              gap: 8,
              builder: (_, panel) => DshButton(
                key: const ValueKey('source-anchor'),
                onPressed: panel.toggle,
                child: const Text('Open intrinsic'),
              ),
              panelBuilder: (_, _) => const SizedBox(
                key: ValueKey('intrinsic-card'),
                width: 240,
                height: 72,
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open intrinsic'));
    await t.pumpAndSettle();
    final anchor = t.getRect(find.byKey(const ValueKey('source-anchor')));
    final card = t.getRect(find.byKey(const ValueKey('intrinsic-card')));
    expect(card.bottom, anchor.top - 8);
    expect(card.right, anchor.right);
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'Escape closes a panel and restores keyboard focus to its trigger',
    (t) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await t.pumpWidget(
        dshTestApp(
          Align(
            alignment: Alignment.topLeft,
            child: DshAnchoredPanel(
              builder: (_, panel) => DshButton(
                focusNode: focus,
                onPressed: panel.toggle,
                child: const Text('Open'),
              ),
              panelBuilder: (_, panel) => DshButton(
                onPressed: panel.close,
                child: const Text('Panel action'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      expect(find.text('Panel action'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Panel action'), findsNothing);
      focus.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.text('Panel action'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Panel action'), findsNothing);
      expect(focus.hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.text('Panel action'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Panel action'), findsNothing);
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    },
  );
}
