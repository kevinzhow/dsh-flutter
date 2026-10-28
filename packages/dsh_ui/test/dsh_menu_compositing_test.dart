import 'dart:ui' as ui;

import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Color> _rowPixel(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Finder row,
) async {
  final rect = tester.getRect(row);
  // A blank interior point between the left label and trailing value/check.
  final point = Offset(rect.left + rect.width / 3, rect.center.dy);
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
      return Color.fromARGB(
        bytes.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  for (final (brightness, plain, focused) in [
    (Brightness.light, const Color(0xfffbfcfc), const Color(0xffeef0f1)),
    (Brightness.dark, const Color(0xff292a2e), const Color(0xff393a3e)),
  ]) {
    for (final profile in [
      DshMenuItemProfile.modelCell,
      DshMenuItemProfile.modelOption,
    ]) {
      testWidgets('released menu row pixels and actions: $brightness $profile', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        try {
          final focus = FocusNode();
          addTearDown(focus.dispose);
          final boundary = GlobalKey();
          const rowKey = ValueKey('source-menu-row');
          final target = find.byKey(rowKey);
          var activations = 0;
          Widget app({bool disabled = false, bool selectionFill = false}) =>
              RepaintBoundary(
                key: boundary,
                child: dshTestApp(
                  Center(
                    child: SizedBox(
                      width: 248,
                      child: DshMenuSurface(
                        child: DshMenuItemButton(
                          key: rowKey,
                          label: 'Max',
                          value: profile == DshMenuItemProfile.modelCell
                              ? 'Current'
                              : null,
                          profile: profile,
                          selected: true,
                          selectionFill: selectionFill,
                          disabled: disabled,
                          focusVisible: true,
                          focusNode: focus,
                          onPressed: () => activations++,
                        ),
                      ),
                    ),
                  ),
                  brightness: brightness,
                ),
              );

          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          expect(await _rowPixel(tester, boundary, target), plain);
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(focus.hasPrimaryFocus, isTrue);
          // Actual pinned Chromium 145 root/effort-card pixels, from published
          // 0.2.1-rc.2 MenuSurface + interactive-bg-hover. Dark is (57,58,62),
          // while raw Flutter alpha-over currently renders (58,59,62).
          expect(await _rowPixel(tester, boundary, target), focused);
          final data = tester.getSemantics(target).getSemanticsData();
          expect(data.flagsCollection.isSelected, ui.Tristate.isTrue);
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(activations, 1);

          focus.unfocus();
          await tester.pumpAndSettle();
          expect(await _rowPixel(tester, boundary, target), plain);
          await tester.pumpWidget(app(selectionFill: true));
          await tester.pumpAndSettle();
          expect(await _rowPixel(tester, boundary, target), focused);
          await tester.pumpWidget(app(disabled: true));
          await tester.pumpAndSettle();
          expect(await _rowPixel(tester, boundary, target), plain);
          expect(
            tester
                .getSemantics(target)
                .getSemanticsData()
                .hasAction(ui.SemanticsAction.tap),
            isFalse,
          );
          await tester.tap(target);
          await tester.pump();
          expect(activations, 1);
        } finally {
          semantics.dispose();
        }
      });
    }
    testWidgets('dock menu declares its painted ground in $brightness', (
      tester,
    ) async {
      Color? declared;
      await tester.pumpWidget(
        dshTestApp(
          Center(
            child: DshMenuSurface(
              profile: DshMenuSurfaceProfile.dock,
              child: Builder(
                builder: (context) {
                  declared = DshSurface.maybeOf(context);
                  return const SizedBox(width: 120, height: 34);
                },
              ),
            ),
          ),
          brightness: brightness,
        ),
      );
      expect(declared, plain);
    });
  }

  for (final under in [null, const Color(0x80151517)]) {
    testWidgets('unknown or translucent ground retains caller alpha: $under', (
      tester,
    ) async {
      const fill = Color.fromRGBO(84, 85, 87, .5);
      final base = resolveTheme(
        officialPack,
        ThemeSettings(),
        Brightness.light,
      );
      final theme = base.copyWith(
        colors: {...base.colors, DshModelMenuRecipe.hoverToken: fill},
      );
      final row = DshMenuItemButton(
        label: 'Caller-owned ground',
        profile: DshMenuItemProfile.modelOption,
        active: true,
        onPressed: () {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [theme]),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: under == null
                    ? row
                    : DshSurface(color: under, child: row),
              ),
            ),
          ),
        ),
      );
      final paint = tester.widget<DshContainer>(
        find.descendant(
          of: find.byType(DshMenuItemButton),
          matching: find.byType(DshContainer),
        ),
      );
      final actual = (paint.decoration as ShapeDecoration).color!;
      expect(actual, fill);
      expect(actual.a, .5);
    });
  }
}
