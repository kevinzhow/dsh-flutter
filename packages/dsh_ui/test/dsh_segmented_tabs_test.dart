import 'package:dsh_ui/dsh_ui.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
