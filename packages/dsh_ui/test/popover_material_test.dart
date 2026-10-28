import 'dart:ui' as ui;

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (brightness, expected) in [
    (Brightness.light, const Color(0xfffbfcfc)),
    (Brightness.dark, const Color(0xff292a2e)),
  ]) {
    testWidgets('macOS MenuSurface uses its own released fill in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(300, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: dshTestApp(
            const ShellScope(
              chrome: ShellChrome(platform: ShellPlatform.darwin),
              child: Center(
                child: SizedBox(
                  width: 240,
                  height: 76,
                  child: DshMenuSurface(child: SizedBox.expand()),
                ),
              ),
            ),
            brightness: brightness,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final actual = await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final pixel = (100 * image.width + 150) * 4;
          // Actual upstream ModelSelect root-card ground pixels over bgBase;
          // MenuSurface uses --dsw-menu-surface-fill, while statistics use
          // the separate macOS-scoped --dsw-specific-menu token.
          return Color.fromARGB(
            bytes.getUint8(pixel + 3),
            bytes.getUint8(pixel),
            bytes.getUint8(pixel + 1),
            bytes.getUint8(pixel + 2),
          );
        } finally {
          image.dispose();
        }
      });
      expect(actual, expected);
    });
  }

  testWidgets('CSS backdrop mirror survives the saturation/blur composition', (
    tester,
  ) async {
    await tester.pumpWidget(
      dshTestApp(
        const Center(
          child: DshPopoverSurface(child: SizedBox(width: 300, height: 159)),
        ),
      ),
    );
    final filter = tester
        .widget<BackdropFilter>(find.byType(BackdropFilter))
        .filter;
    // The pinned engine materializes unspecified blur modes as clamp while
    // composing. Assert the source edge-mode contract at that API boundary;
    // the three real-source smoke pairs separately exercise rendered pixels.
    expect(filter.toString(), contains('mirror'));
    expect(filter.toString(), isNot(contains('unspecified')));
  });
}
