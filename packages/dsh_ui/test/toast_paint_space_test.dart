import 'dart:typed_data';

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Pinned Chromium145 CDP actual Toast paint logs show an integer contour
// BEFORE translateX(-50%), with the fractional translation retained. A direct
// custom icon keeps the natural width fractional even under the test font.
void main() {
  for (final density in [1.0, 2.625]) {
    for (final elapsed in [200, 80]) {
      testWidgets('Toast shares its pre-transform contour $density/$elapsed', (
        t,
      ) async {
        t.view.devicePixelRatio = density;
        t.view.physicalSize = Size(800 * density, 600 * density);
        addTearDown(t.view.reset);
        await t.pumpWidget(
          dshTestApp(
            DshToast(
              text: 'X',
              icon: const SizedBox(width: 0.5, height: 14),
              onDone: () {},
            ),
          ),
        );
        await t.pump();
        await t.pump(Duration(milliseconds: elapsed));
        final owner = find.byType(DshShadowBox);
        final widget = t.widget<DshShadowBox>(owner);
        final actualLayout = t.getRect(owner);
        final origin = Offset(400, DshToastRecipe.top);
        final sourceContour = dshSnapRect(
          origin & actualLayout.size,
          density,
        ).shift(-origin);

        final decorated = find.descendant(
          of: owner,
          matching: find.byType(DshDecoratedBox),
        );
        final fill = TestRecordingCanvas();
        t
            .renderObject<RenderBox>(decorated)
            .paint(TestRecordingPaintingContext(fill), Offset.zero);
        final fillCalls = fill.invocations.where((c) {
          if (c.invocation.memberName != #drawPath) return false;
          return (c.invocation.positionalArguments.last as Paint).color
                  .toARGB32() ==
              widget.color.toARGB32();
        });
        expect(fillCalls, hasLength(1));
        final fillPath =
            fillCalls.single.invocation.positionalArguments.first as Path;
        expect(fillPath.getBounds(), float32Rect(sourceContour));

        final shadowPaint = t
            .widget<CustomPaint>(
              find
                  .descendant(of: owner, matching: find.byType(CustomPaint))
                  .first,
            )
            .painter!;
        final shadows = TestRecordingCanvas();
        shadowPaint.paint(shadows, actualLayout.size);
        final paths = shadows.invocations.where(
          (c) => c.invocation.memberName == #drawPath,
        );
        final outer = paths.where(
          (c) =>
              (c.invocation.positionalArguments.last as Paint).blendMode !=
              BlendMode.dstOut,
        );
        final masks = paths.where(
          (c) =>
              (c.invocation.positionalArguments.last as Paint).blendMode ==
              BlendMode.dstOut,
        );
        expect(outer, hasLength(widget.shadows.length));
        for (final pair in outer.indexed) {
          final s = widget.shadows.reversed.elementAt(pair.$1);
          final path = pair.$2.invocation.positionalArguments.first as Path;
          expect(
            path.getBounds(),
            float32Rect(sourceContour.shift(s.offset).inflate(s.spreadRadius)),
          );
        }
        for (final call in masks) {
          final path = call.invocation.positionalArguments.first as Path;
          final expected = sourceContour.deflate(1 / dshSnapDensity(density));
          expect(path.getBounds(), float32Rect(expected));
        }
        // Paint geometry must not change the actual source centering/layout or
        // quantize the post-layout entry transform.
        expect(actualLayout.center.dx, 400);
        expect(
          actualLayout.top,
          elapsed == 200 ? DshToastRecipe.top : lessThan(DshToastRecipe.top),
        );
        expect(t.getRect(owner), actualLayout);
        await t.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('source paint origin updates without changing default callers', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Widget frame(Offset? sourceOrigin) => Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned(
            left: 10.25,
            top: 30.25,
            child: DshShadowBox(
              color: const Color(0xffffffff),
              radius: 2,
              sourcePaintOrigin: sourceOrigin,
              shadows: const [BoxShadow()],
              child: const SizedBox(width: 20.5, height: 20.5),
            ),
          ),
        ],
      ),
    );
    Rect fillBounds() {
      final canvas = TestRecordingCanvas();
      t
          .renderObject<RenderBox>(find.byType(DshDecoratedBox))
          .paint(TestRecordingPaintingContext(canvas), Offset.zero);
      final draw = canvas.invocations.singleWhere(
        (c) => c.invocation.memberName == #drawRRect,
      );
      return (draw.invocation.positionalArguments.first as RRect).outerRect;
    }

    CustomPainter shadowPainter() => t
        .widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(DshShadowBox),
                matching: find.byType(CustomPaint),
              )
              .first,
        )
        .painter!;

    await t.pumpWidget(frame(null));
    final layout = t.getRect(find.byType(DshShadowBox));
    expect(fillBounds(), const Rect.fromLTRB(-0.25, -0.25, 20.75, 20.75));
    final original = shadowPainter();
    final canvas = TestRecordingCanvas();
    original.paint(canvas, layout.size);
    final draw = canvas.invocations.singleWhere(
      (c) => c.invocation.memberName == #drawRRect,
    );
    expect(
      (draw.invocation.positionalArguments.first as RRect).outerRect,
      const Rect.fromLTWH(0, 0, 20.5, 20.5),
    );

    await t.pumpWidget(frame(const Offset(100, 50)));
    expect(t.getRect(find.byType(DshShadowBox)), layout);
    expect(fillBounds(), const Rect.fromLTWH(0, 0, 21, 21));
    expect(shadowPainter().shouldRepaint(original), isTrue);
    final previous = shadowPainter();
    await t.pumpWidget(frame(const Offset(100.5, 50.5)));
    expect(t.getRect(find.byType(DshShadowBox)), layout);
    expect(fillBounds(), const Rect.fromLTWH(0.5, 0.5, 20, 20));
    expect(shadowPainter().shouldRepaint(previous), isTrue);
  });
}

// SkPath stores coordinates as float32. Compare the representable contour,
// without a fitted logical-coordinate or raster-error tolerance.
Rect float32Rect(Rect r) {
  final values = Float32List.fromList([r.left, r.top, r.right, r.bottom]);
  return Rect.fromLTRB(values[0], values[1], values[2], values[3]);
}
