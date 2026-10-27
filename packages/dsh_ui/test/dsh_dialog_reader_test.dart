import 'dart:async';

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget reader() => DshDialogReader(
    title: 'Reader',
    intro: 'Independent pages',
    closeLabel: 'Close reader',
    tabsLabel: 'Pages',
    identifier: 'test-reader',
    initialValue: 'first',
    tabsKey: const ValueKey('reader-tabs'),
    closeKey: const ValueKey('reader-close'),
    onClose: () {},
    tabs: [
      for (final page in ['first', 'second'])
        DshReaderTab(
          page,
          page,
          tabKey: ValueKey('$page-tab'),
          panelKey: ValueKey('$page-panel'),
          child: Column(
            key: ValueKey('$page-content'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 100; i++)
                SizedBox(height: 24, child: Text('$page row $i')),
            ],
          ),
        ),
    ],
  );
  Finder scrollable(String page) => find.descendant(
    of: find.byKey(ValueKey('$page-panel')),
    matching: find.byType(Scrollable),
  );
  Future<void> pumpReader(WidgetTester t, {double height = 600}) async {
    await t.pumpWidget(
      dshTestApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 640, height: height, child: reader()),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('published reader geometry reserves the native stable gutter', (
    t,
  ) async {
    await pumpReader(t);
    expect(
      t.getSize(find.byKey(const ValueKey('reader-tabs'))),
      const Size(584, 42),
    );
    expect(
      t.getSize(find.byKey(const ValueKey('reader-close'))),
      const Size(32, 32),
    );
    expect(t.getSize(find.byKey(const ValueKey('first-content'))).width, 583);
  });

  testWidgets(
    'both pages retain independent scroll positions and mounted content',
    (t) async {
      await pumpReader(t, height: 340);
      final first = t.state<ScrollableState>(scrollable('first')).position;
      await t.drag(
        find.byKey(const ValueKey('first-panel')),
        const Offset(0, -220),
      );
      await t.pumpAndSettle();
      final firstOffset = first.pixels;
      expect(firstOffset, greaterThan(0));
      await t.tap(find.byKey(const ValueKey('second-tab')));
      await t.pumpAndSettle();
      final second = t.state<ScrollableState>(scrollable('second')).position;
      expect(second.pixels, 0);
      await t.drag(
        find.byKey(const ValueKey('second-panel')),
        const Offset(0, -160),
      );
      await t.pumpAndSettle();
      final secondOffset = second.pixels;
      expect(secondOffset, greaterThan(0));
      await t.tap(find.byKey(const ValueKey('first-tab')));
      await t.pumpAndSettle();
      expect(
        t.state<ScrollableState>(scrollable('first')).position,
        same(first),
      );
      expect(first.pixels, firstOffset);
      await t.tap(find.byKey(const ValueKey('second-tab')));
      await t.pumpAndSettle();
      expect(
        t.state<ScrollableState>(scrollable('second')).position,
        same(second),
      );
      expect(second.pixels, secondOffset);
    },
  );

  testWidgets('keyboard PageDown scrolls the focused reader panel', (t) async {
    await pumpReader(t, height: 340);
    final detector = t.widget<FocusableActionDetector>(
      find
          .descendant(
            of: find.byKey(const ValueKey('first-panel')),
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    );
    detector.focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pumpAndSettle();
    expect(
      t.state<ScrollableState>(scrollable('first')).position.pixels,
      greaterThan(0),
    );
  });

  testWidgets('short viewports clip fixed chrome without overflowing layout', (
    t,
  ) async {
    await pumpReader(t, height: 80);
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(DshDialogReader)).height, 80);
  });

  testWidgets(
    'published frame inset excludes mask paint but blocks caption input',
    (t) async {
      var backgroundTaps = 0;
      await t.pumpWidget(
        dshTestApp(
          FrameInsetsScope(
            insets: const FrameInsets(overlayTop: 64, chromeTop: 40),
            child: Builder(
              builder: (context) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => backgroundTaps++,
                child: Center(
                  child: DshButton(
                    onPressed: () => unawaited(
                      showDshDialog<void>(
                        context,
                        label: 'Inset modal',
                        width: 1000,
                        height: 1000,
                        builder: (_) => const Text('Modal body'),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(DshDialogFrame)), const Size(752, 472));
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(find.text('Modal body'), findsOneWidget);
      expect(backgroundTaps, 0);
      await t.tapAt(const Offset(10, 80));
      await t.pumpAndSettle();
      expect(find.text('Modal body'), findsNothing);
      expect(backgroundTaps, 0);
    },
  );
}
