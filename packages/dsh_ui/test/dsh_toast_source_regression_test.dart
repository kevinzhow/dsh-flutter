import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('source omitted icon creates no icon seat', (t) async {
    await t.pumpWidget(dshTestApp(DshToast(text: 'Saved', onDone: () {})));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byType(DshIcon), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  for (final width in [800.0, 390.0]) {
    testWidgets('source content-box cap is outside padding at $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        dshTestApp(
          DshToast(
            text: List.filled(80, 'Long synthetic source notice').join(' '),
            onDone: () {},
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      final rect = t.getRect(find.byType(DshChromeText));
      expect(rect.width, width == 800 ? 640 : 342);
      expect(
        t.getRect(find.byType(DshShadowBox)).width,
        width == 800 ? 672 : 374,
      );
      expect(
        t.widget<DshChromeText>(find.byType(DshChromeText)).maxLines,
        isNull,
      );
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('source deadline is independent of animation frame completion', (
    t,
  ) async {
    var done = 0;
    await t.pumpWidget(
      dshTestApp(DshToast(text: 'Saved', onDone: () => done++)),
    );
    await t.pump();
    await t.pump();
    await t.pump(const Duration(seconds: 4));
    expect(done, 1);
    await t.pump(const Duration(seconds: 2));
    expect(done, 1);
    await t.pumpWidget(const SizedBox());
  });
}
