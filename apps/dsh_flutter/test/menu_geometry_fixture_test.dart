import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'parity/menu_geometry_main.dart';

void main() {
  for (final width in [390.0, 900.0]) {
    testWidgets(
      'native menu fixture routes touches to rows and its footer at $width',
      (t) async {
        t.view.physicalSize = Size(width, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(dshTestApp(menuGeometryFixture()));
        await t.pumpAndSettle();
        await t.longPress(find.text('Synthetic tab'));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(DshMenuItemButton, 'Close tab'));
        await t.pumpAndSettle();
        expect(find.text('Empty pane'), findsOneWidget);
        await t.tap(find.text('Workspaces'));
        await t.pumpAndSettle();
        await t.tap(find.text('Choose workspace'));
        await t.pumpAndSettle();
        await t.tap(find.text('Beta'));
        await t.pumpAndSettle();
        expect(find.text('Selected workspace: beta'), findsOneWidget);
        await t.tap(find.text('Choose workspace'));
        await t.pumpAndSettle();
        await t.tap(find.text('Add workspace'));
        await t.pumpAndSettle();
        expect(find.text('Selected workspace: add'), findsOneWidget);
        await t.tap(find.text('Long list'));
        await t.pumpAndSettle();
        await t.tap(find.text('Choose workspace'));
        await t.pumpAndSettle();
        final footer = t.getRect(find.text('Add workspace'));
        expect(footer.bottom, lessThan(844));
        await t.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -400),
        );
        await t.pumpAndSettle();
        expect(t.getRect(find.text('Add workspace')), footer);
        await t.tap(find.text('Add workspace'));
        await t.pumpAndSettle();
        expect(find.text('Selected workspace: add'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        await t.pump();
        expect(t.takeException(), isNull);
      },
    );
  }
}
