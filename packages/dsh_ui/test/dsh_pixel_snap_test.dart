// Blink's native-density snapping (docs/parity.md, "What Blink does at a native density"): border widths, box edges,
// the baseline model in device pixels, and the emulated model that reproduces the older reference.
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => dshPixelModel = DshPixelModel.native);

  group('border width', () {
    test('0.5px is one device pixel at every density', () {
      expect(dshSnapBorderWidth(0.5, 1), 1);
      expect(dshSnapBorderWidth(0.5, 2), 0.5);
      expect(dshSnapBorderWidth(0.5, 2.625), closeTo(1 / 2.625, 1e-12));
      expect(dshSnapBorderWidth(0.5, 3), closeTo(1 / 3, 1e-12));
    });

    test('1px and wider floor to whole device pixels', () {
      expect(dshSnapBorderWidth(1, 2), 1);
      expect(dshSnapBorderWidth(1, 2.625), closeTo(2 / 2.625, 1e-12));
      expect(dshSnapBorderWidth(1, 3), 1);
      expect(dshSnapBorderWidth(2, 2.625), closeTo(5 / 2.625, 1e-12));
      expect(dshSnapBorderWidth(0, 3), 0);
    });

    test('the emulated model works in CSS pixels', () {
      dshPixelModel = DshPixelModel.emulated;
      for (final dpr in [1.0, 2.0, 2.625, 3.0]) {
        expect(dshSnapBorderWidth(0.5, dpr), 1);
        expect(dshSnapBorderWidth(1, dpr), 1);
        expect(dshSnapBorderWidth(2, dpr), 2);
      }
    });

    testWidgets('dshHairlineOf follows the view', (t) async {
      late double width;
      t.view.devicePixelRatio = 2.625;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        Builder(
          builder: (context) {
            width = dshHairlineOf(context);
            return const SizedBox();
          },
        ),
      );
      expect(width, closeTo(1 / 2.625, 1e-12));
    });
  });

  group('box edges', () {
    test('every edge rounds to a device pixel, halves up', () {
      expect(dshSnapToPixel(136.5, 2.625), closeTo(358 / 2.625, 1e-12));
      expect(dshSnapToPixel(10.5 / 2.625, 2.625), closeTo(11 / 2.625, 1e-12));
      expect(dshSnapToPixel(3.3, 1), 3);
      expect(dshSnapToPixel(3.5, 1), 4);
    });

    test('the snapped size is the difference of the snapped edges', () {
      final r = dshSnapRect(const Rect.fromLTWH(0, 16, 420, 36), 2.625);
      // top 42 device px, bottom 52 * 2.625 = 136.5 -> 137.
      expect(r.top * 2.625, closeTo(42, 1e-9));
      expect(r.bottom * 2.625, closeTo(137, 1e-9));
      expect(r.right * 2.625, closeTo(1103, 1e-9));
    });

    testWidgets('DshDecoratedBox paints the border on whole device pixels', (
      t,
    ) async {
      t.view.devicePixelRatio = 2.625;
      t.view.physicalSize = const Size(200, 200) * 2.625;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SizedBox(
                    width: 100,
                    height: 36,
                    child: DshDecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFF000000),
                          width: 1 / 2.625,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final image = await t.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 2.625);
        final data = await img.toByteData();
        return (img.width, data!);
      });
      final (width, data) = image!;
      int gray(int x, int y) => data.getUint8((y * width + x) * 4);
      // The box spans 42 .. 137 device rows (bottom edge 136.5 rounds up):
      // the top and bottom border are one fully dark row each, no smear.
      expect(gray(100, 42), 0);
      expect(gray(100, 41), 255);
      expect(gray(100, 43), 255);
      expect(gray(100, 136), 0);
      expect(gray(100, 135), 255);
      expect(gray(100, 137), 255);
    });
  });

  group('baseline in device pixels', () {
    // The test font (Ahem) has an ascent of 0.75em and a descent of 0.25em.
    TextStyle ahem(double size, double line) => TextStyle(
      fontSize: size,
      height: line / size,
      leadingDistribution: TextLeadingDistribution.even,
    );

    test(
      'Blink rounds the metrics and floors the half leading in device px',
      () {
        // 10px on 14 at 2x: ascent 15, descent 5, line 28 device px, so the
        // baseline is 15 + floor(4) = 19 device px = 9.5 logical; Flutter's
        // rounded baseline is 10 logical (7.5 + 2).
        expect(dshBaselineNudge(ahem(10, 14), 2), -0.5);
        // At 1x the CSS-pixel model of the emulated capture: 8 + floor(1.5) = 9 against 10.
        expect(dshBaselineNudge(ahem(10, 14), 1), -1);
      },
    );

    test('the emulated model ignores the density', () {
      dshPixelModel = DshPixelModel.emulated;
      expect(dshBaselineNudge(ahem(10, 14), 3), -1);
      expect(dshBaselineNudge(ahem(10, 14), 2.625), -1);
    });

    test('dshBlinkBaseline: round the metrics, floor half the leading', () {
      expect(
        dshBlinkBaseline(ascent: 15.5, descent: 5.5, lineHeight: 28),
        16 + ((28 - 16 - 6) / 2).floor(),
      );
      // 1/64 layout units absorb float noise in `height * size`.
      expect(
        dshBlinkBaseline(ascent: 8, descent: 3, lineHeight: 15.000000001),
        8 + 2,
      );
    });
  });

  group('object-fit position', () {
    test(
      'snaps to a device pixel in the native model, a CSS pixel otherwise',
      () {
        const source = (width: 189, height: 126);
        // A 126 device px box is 63 logical at 2x; the 189 px picture is 94.5
        // logical wide, so half the free space is -15.75 logical = -31.5
        // device px: a device pixel layout rounds it half up to -31 (-15.5
        // logical), the CSS-pixel layout of the emulated capture to -16.
        final native = dshSnappedAlignment(
          box: const Size.square(63),
          source: source,
          fit: DshImageFit.cover,
          devicePixelRatio: 2,
        );
        final free = 63 - 189 * (63 / 126);
        expect(native.x * free / 2 + free / 2, closeTo(-15.5, 1e-9));
        dshPixelModel = DshPixelModel.emulated;
        final css = dshSnappedAlignment(
          box: const Size.square(63),
          source: source,
          fit: DshImageFit.cover,
          devicePixelRatio: 2,
        );
        expect(css.x * free / 2 + free / 2, closeTo(-16, 1e-9));
      },
    );
  });
}
