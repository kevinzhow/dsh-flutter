import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<String>> pump(
    WidgetTester t, {
    List<String> selected = const [],
    DshMenuAlign align = DshMenuAlign.end,
  }) async {
    final picked = <String>[];
    t.view.physicalSize = const Size(600, 400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      dshTestApp(
        Align(
          alignment: Alignment.topRight,
          child: DshMenu(
            align: align,
            selectedIds: selected,
            entries: const [
              DshMenuSeparator('lead'),
              DshMenuLabel('h', 'Group by'),
              DshMenuItem('a', 'Alpha', icon: DshIcons.check),
              DshMenuSeparator('s1'),
              DshMenuSeparator('s2'),
              DshMenuItem('b', 'Beta'),
              DshMenuItem('off', 'Off', disabled: true),
              DshMenuItem('del', 'Delete', danger: true),
            ],
            onSelect: picked.add,
            builder: (context, menu) => GestureDetector(
              key: const ValueKey('anchor'),
              behavior: HitTestBehavior.opaque,
              onTap: menu.toggle,
              child: const SizedBox(width: 28, height: 28),
            ),
          ),
        ),
        size: const Size(600, 400),
      ),
    );
    return picked;
  }

  testWidgets('opens under its anchor, marks selection and heads groups', (
    t,
  ) async {
    await pump(t, selected: ['b'], align: DshMenuAlign.end);
    expect(find.text('Alpha'), findsNothing);
    await t.tap(find.byKey(const ValueKey('anchor')));
    await t.pumpAndSettle();
    expect(find.text('Group by'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    // The card's right edge meets the anchor's: it opens to the left.
    final card = t.getRect(find.byKey(const ValueKey('dsh-menu')));
    final anchor = t.getRect(find.byKey(const ValueKey('anchor')));
    expect(card.right, anchor.right);
    expect(card.top, anchor.bottom + 4);
    // One check, on the selected row.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dsh-menu-b')),
        matching: find.byType(DshIcon),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dsh-menu-a')),
        matching: find.byType(DshIcon),
      ),
      findsOneWidget,
      reason: 'its own icon, no check',
    );
  });

  testWidgets('a selection closes the card; a press outside does too', (
    t,
  ) async {
    final picked = await pump(t);
    await t.tap(find.byKey(const ValueKey('anchor')));
    await t.pumpAndSettle();
    await t.tap(find.text('Beta'));
    await t.pumpAndSettle();
    expect(picked, ['b']);
    expect(find.text('Beta'), findsNothing);
    await t.tap(find.byKey(const ValueKey('anchor')));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(10, 380));
    await t.pumpAndSettle();
    expect(find.text('Beta'), findsNothing);
    expect(picked, ['b']);
  });

  testWidgets('a disabled row selects nothing', (t) async {
    final picked = await pump(t);
    await t.tap(find.byKey(const ValueKey('anchor')));
    await t.pumpAndSettle();
    await t.tap(find.text('Off'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(picked, isEmpty);
    expect(find.text('Off'), findsOneWidget);
  });
}
