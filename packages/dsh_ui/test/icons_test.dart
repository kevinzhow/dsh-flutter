import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
  theme: ThemeData(
    extensions: [
      resolveTheme(
        officialPack,
        ThemeSettings(preference: ThemePreference.light),
        Brightness.light,
      ),
    ],
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('the brand mark is the whale emoji fitted to its box', (t) async {
    await t.pumpWidget(host(const DshWhaleMark(size: 34)));
    expect(find.text(DshWhaleMark.glyph), findsOneWidget);
    expect(DshWhaleMark.glyph, '🐳');
    expect(t.getSize(find.byType(DshWhaleMark)), const Size(34, 34));
    final emoji = t.getSize(find.byKey(const ValueKey('whale-mark')));
    expect(emoji.width, lessThanOrEqualTo(34));
    expect(emoji.height, lessThanOrEqualTo(34));
  });

  testWidgets('an icon without a colour draws inside an icon theme', (t) async {
    await t.pumpWidget(
      host(
        IconTheme(
          data: const IconThemeData(color: Color(0xFF123456)),
          child: DshIcon(CharcoalIcons.lock, size: 24),
        ),
      ),
    );
    final paint = t.widget<CustomPaint>(
      find.descendant(
        of: find.byType(DshIcon),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paint.size, const Size.square(24));
  });

  test('the Charcoal and dsh inline glyphs are filled path data', () {
    for (final icon in [
      CharcoalIcons.list,
      CharcoalIcons.lock,
      DshShellIcons.send,
      DshShellIcons.stop,
      DshShellIcons.panelFullscreen,
      DshShellIcons.panelExitFullscreen,
      DshShellIcons.dockSplit,
      DshShellIcons.shortcutError,
      DshShellIcons.dockZoneLeft,
    ]) {
      expect(icon.shapes, isNotEmpty);
      expect(icon.viewBox, anyOf(16, 24, 12));
    }
    // The archive-off slash carves a gap out of the box strokes.
    expect(DshShellIcons.archiveOff.shapes.any((s) => s.cutWidth > 0), isTrue);
  });
}
