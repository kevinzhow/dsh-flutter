import 'dart:convert';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reported_families_main.dart';

void main() {
  setUpAll(loadPinnedFontsFromEnvironment);
  for (final size in [const Size(1280, 720), const Size(390, 844)]) {
    testWidgets(
      'Header native scene preserves toolbar and exposes actual callbacks at $size',
      (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          dshTestApp(
            const SafeArea(
              child: ReportedFamiliesNativeScenes(DshI18n(DshLocale.en)),
            ),
          ),
        );
        await t.pumpAndSettle();
        final toolbar = [
          for (var i = 0; i < 3; i++)
            t.getRect(find.byKey(ValueKey('scene-$i')).last),
        ];
        final headerBottom = t
            .getBottomLeft(find.text('Sidebar action: none').last)
            .dy;
        await t.sendKeyEvent(LogicalKeyboardKey.f6);
        await t.pumpAndSettle();
        expect(
          find.text('Header callbacks: toggle=0 session=0'),
          findsOneWidget,
        );
        expect(find.byKey(DshButton.focusRingKey), findsNothing);
        for (var i = 0; i < 3; i++) {
          expect(t.getRect(find.byKey(ValueKey('scene-$i')).last), toolbar[i]);
        }
        final toggle = find.byKey(const ValueKey('leading-toggle'));
        final session = find.byKey(const ValueKey('leading-new-session'));
        final toggleRect = t.getRect(toggle), sessionRect = t.getRect(session);
        expect(
          toggleRect.size,
          const Size(
            DshHeaderLeadingRecipe.width,
            DshHeaderLeadingRecipe.height,
          ),
        );
        expect(
          toggleRect.top,
          headerBottom + DshHeaderLeadingRecipe.controlsGap,
        );
        expect(
          sessionRect.left - toggleRect.right,
          DshHeaderLeadingRecipe.controlsGap,
        );
        debugPrint(
          'HEADER_NATIVE_GEOMETRY ${jsonEncode({
            'viewport': [size.width, size.height],
            'toolbarBottom': headerBottom,
            'toggle': [toggleRect.left, toggleRect.top, toggleRect.right, toggleRect.bottom],
            'newSession': [sessionRect.left, sessionRect.top, sessionRect.right, sessionRect.bottom],
            'counter': [t.getTopLeft(find.text('Header callbacks: toggle=0 session=0')).dx, t.getTopLeft(find.text('Header callbacks: toggle=0 session=0')).dy, t.getBottomRight(find.text('Header callbacks: toggle=0 session=0')).dx, t.getBottomRight(find.text('Header callbacks: toggle=0 session=0')).dy],
          })}',
        );
        await t.tap(toggle);
        await t.pump();
        expect(
          find.text('Header callbacks: toggle=1 session=0'),
          findsOneWidget,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(
          find.text('Header callbacks: toggle=2 session=0'),
          findsOneWidget,
        );
        expect(find.byKey(DshButton.focusRingKey), findsNothing);
        await t.sendKeyEvent(LogicalKeyboardKey.home);
        await t.pump();
        expect(find.byKey(DshButton.focusRingKey), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(
          find.text('Header callbacks: toggle=2 session=1'),
          findsOneWidget,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.space);
        await t.pump();
        expect(
          find.text('Header callbacks: toggle=2 session=2'),
          findsOneWidget,
        );
        await t.tap(session);
        await t.pump();
        expect(
          find.text('Header callbacks: toggle=2 session=3'),
          findsOneWidget,
        );
        expect(find.byKey(DshButton.focusRingKey), findsNothing);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
