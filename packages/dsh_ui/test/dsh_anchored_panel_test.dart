import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
