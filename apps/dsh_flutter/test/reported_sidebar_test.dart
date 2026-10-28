import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'parity/helpers/reported_sidebar_fixture.dart';

void main() {
  Future<void> pump(WidgetTester t, {bool darwin = true}) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      dshTestApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 280,
            height: 800,
            child: ReportedSidebarFixture(
              i18n: const DshI18n(DshLocale.en),
              platform: darwin ? ShellPlatform.darwin : ShellPlatform.other,
            ),
          ),
        ),
        size: const Size(1280, 800),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'real macOS sidebar clears traffic lights without shifting its content down',
    (t) async {
      await pump(t);
      final toggle = find.byKey(const ValueKey('sidebar-toggle'));
      final newSession = find.byKey(const ValueKey('sidebar-new-session'));
      // Actual published geometry:52px strip starts at0, logo tucks12 back,
      //60px logo +4px margin => New Session at104; toggle centered at25.
      expect(t.getTopLeft(newSession).dy, 104);
      expect(t.getCenter(toggle).dy, 25);
      expect(
        t.getSize(find.byKey(const ValueKey('settings-trigger'))).height,
        32,
      );
      expect(find.text('Plugins'), findsOneWidget);
      expect(find.text('Automation tasks'), findsOneWidget);
      expect(find.text('Default workspace'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'More menu opens above the bottom launcher and Escape dismisses it',
    (t) async {
      await pump(t);
      final launcher = find.byKey(const ValueKey('settings-trigger'));
      final launcherRect = t.getRect(launcher);
      await t.tap(launcher);
      await t.pumpAndSettle();
      final menu = find.byKey(const ValueKey('settings-more-menu'));
      expect(menu, findsOneWidget);
      final menuRect = t.getRect(menu);
      expect(
        menuRect.bottom,
        closeTo(launcherRect.top - DshMenuRecipe.anchorGap, 0.01),
      );
      expect(menuRect.top, greaterThan(400));
      expect(
        menuRect.width,
        greaterThanOrEqualTo(DshSidebarLauncherRecipe.menuMinWidth),
      );
      expect(
        t.getSize(find.byKey(const ValueKey('settings-more-settings'))).height,
        40,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(menu, findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'the full browser switches sessions and More opens the real settings route',
    (t) async {
      await pump(t, darwin: false);
      await t.tap(find.text('分析合成项目进展'));
      await t.pumpAndSettle();
      final row = find.byKey(const ValueKey('session-row-s1'));
      expect(
        t
            .widget<Semantics>(
              find.descendant(of: row, matching: find.byType(Semantics)).first,
            )
            .properties
            .selected,
        isTrue,
      );
      await t.tap(find.byKey(const ValueKey('settings-trigger')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('settings-more-settings')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-more-menu')), findsNothing);
      expect(find.text('Settings'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );
}
