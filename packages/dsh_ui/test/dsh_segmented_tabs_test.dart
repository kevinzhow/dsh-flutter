import 'dart:ui' show SemanticsRole, Tristate;

import 'package:dsh_ui/dsh_ui.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('announces a named tab list with selectable focused tabs', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    var selected = 'first';
    await t.pumpWidget(
      dshTestApp(
        StatefulBuilder(
          builder: (context, set) => DshSegmentedTabs(
            items: const [
              DshSegmentedTab('first', 'First'),
              DshSegmentedTab('second', 'Second'),
            ],
            value: selected,
            label: 'Synthetic views',
            onChanged: (value) => set(() => selected = value),
          ),
        ),
      ),
    );
    final group = t.getSemantics(find.bySemanticsLabel('Synthetic views'));
    expect(group.getSemanticsData().role, SemanticsRole.tabBar);
    final first = t.getSemantics(find.bySemanticsLabel('First'));
    expect(first.getSemanticsData().role, SemanticsRole.tab);
    expect(
      first.getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(first.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(first.getSemanticsData().hasAction(SemanticsAction.focus), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(
      t
          .getSemantics(find.bySemanticsLabel('First'))
          .getSemanticsData()
          .flagsCollection
          .isFocused,
      Tristate.isTrue,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(selected, 'second');
    expect(
      t
          .getSemantics(find.bySemanticsLabel('Second'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  for (final reduceMotion in [false, true]) {
    testWidgets('selection indicator respects reduced motion=$reduceMotion', (
      t,
    ) async {
      var selected = 'first';
      await t.pumpWidget(
        dshTestApp(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: StatefulBuilder(
              builder: (context, set) => Align(
                alignment: Alignment.topLeft,
                child: DshSegmentedTabs(
                  items: const [
                    DshSegmentedTab('first', 'First'),
                    DshSegmentedTab('second', 'Second'),
                  ],
                  value: selected,
                  label: 'Synthetic views',
                  onChanged: (value) => set(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      );
      final indicator = find
          .descendant(
            of: find.byType(DshSegmentedTabs),
            matching: find.byType(IgnorePointer),
          )
          .first;
      final start = t.getTopLeft(indicator).dx;
      Color? labelColor() => t.widget<Text>(find.text('Second')).style!.color;
      final colorStart = labelColor();
      await t.tap(find.text('Second'));
      await t.pump();
      final immediate = t.getTopLeft(indicator).dx;
      final colorImmediate = labelColor();
      expect(
        t.widget<Text>(find.text('Second')).style!.fontWeight,
        FontWeight.w600,
      );
      await t.pump(const Duration(milliseconds: 90));
      final midpoint = t.getTopLeft(indicator).dx;
      final colorMidpoint = labelColor();
      await t.pump(const Duration(milliseconds: 110));
      final end = t.getTopLeft(indicator).dx;
      final colorEnd = labelColor();
      expect(end, greaterThan(start));
      expect(colorEnd, isNot(colorStart));
      if (reduceMotion) {
        expect(immediate, end);
        expect(colorImmediate, colorEnd);
      } else {
        expect(immediate, start);
        expect(midpoint, greaterThan(start));
        expect(midpoint, lessThan(end));
        expect(colorImmediate, colorStart);
        expect(colorMidpoint, isNot(colorStart));
        expect(colorMidpoint, isNot(colorEnd));
      }
    });
  }

  testWidgets(
    'arrow/Home/End selection moves focus and preserves a single tab stop',
    (t) async {
      var selected = 'first';
      final changes = <String>[];
      await t.pumpWidget(
        dshTestApp(
          StatefulBuilder(
            builder: (context, set) => Align(
              alignment: Alignment.topLeft,
              child: DshSegmentedTabs(
                items: const [
                  DshSegmentedTab('first', 'First'),
                  DshSegmentedTab('second', 'Second'),
                  DshSegmentedTab('third', 'Third'),
                ],
                value: selected,
                label: 'Synthetic views',
                onChanged: (value) {
                  changes.add(value);
                  set(() => selected = value);
                },
              ),
            ),
          ),
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(selected, 'third');
      await t.sendKeyEvent(LogicalKeyboardKey.home);
      await t.pump();
      expect(selected, 'first');
      await t.sendKeyEvent(LogicalKeyboardKey.end);
      await t.pump();
      expect(selected, 'third');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(selected, 'first');
      expect(changes, ['third', 'first', 'third', 'first']);
      final detectors = t
          .widgetList<FocusableActionDetector>(
            find.byType(FocusableActionDetector),
          )
          .where((d) => d.focusNode != null)
          .toList();
      expect(detectors.where((d) => !d.focusNode!.skipTraversal), hasLength(1));
      expect(
        detectors
            .singleWhere((d) => !d.focusNode!.skipTraversal)
            .focusNode!
            .hasFocus,
        isTrue,
      );
    },
  );
}
