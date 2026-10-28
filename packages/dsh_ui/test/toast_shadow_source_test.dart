import 'dart:typed_data';

import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<Path>> masks(WidgetTester t, DshShadowBox box, Size size) async {
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1),
        child: Directionality(textDirection: TextDirection.ltr, child: box),
      ),
    );
    final painter = t
        .widget<CustomPaint>(find.byType(CustomPaint).first)
        .painter!;
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, size);
    return [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawPath &&
            (call.invocation.positionalArguments.last as Paint).blendMode ==
                BlendMode.dstOut)
          call.invocation.positionalArguments.first as Path,
    ];
  }

  testWidgets(
    'an opaque computed material does not imply source owner opacity',
    (t) async {
      final paths = await masks(
        t,
        const DshShadowBox(
          color: Color(0xffffffff),
          radius: 12,
          shadows: [BoxShadow(blurRadius: 8)],
          child: SizedBox(),
        ),
        const Size(40, 40),
      );
      expect(paths.single.getBounds(), const Rect.fromLTWH(0, 0, 40, 40));
    },
  );

  for (final curvature in [1.0, 1.5]) {
    testWidgets(
      'opaque inset reduces radius and preserves curvature $curvature',
      (t) async {
        final paths = await masks(
          t,
          DshShadowBox(
            color: const Color(0xffffffff),
            radius: 12,
            shape: DshCornerBorder(radius: 12, curvature: curvature),
            authoredOpaqueBackground: true,
            shadows: const [BoxShadow(blurRadius: 8)],
            child: const SizedBox(),
          ),
          const Size(40, 40),
        );
        final path = paths.single;
        expect(path.getBounds(), const Rect.fromLTWH(1, 1, 38, 38));
        // Circle inset keeps its original corner centre(12,12). Superellipse
        // points here verify the existing canonical reduced-radius model;
        // Chromium's retained-origin inner contour is separate pending work.
        expect(
          path.contains(Offset(curvature == 1 ? 4 : 3, curvature == 1 ? 4 : 3)),
          isFalse,
        );
        expect(
          path.contains(
            Offset(curvature == 1 ? 4.25 : 3.6, curvature == 1 ? 4.25 : 3.6),
          ),
          isTrue,
        );
      },
    );
  }

  testWidgets('empty opaque exclusion does not erase a shadow', (t) async {
    final paths = await masks(
      t,
      const DshShadowBox(
        color: Color(0xffffffff),
        radius: 1,
        authoredOpaqueBackground: true,
        shadows: [BoxShadow(blurRadius: 8)],
        child: SizedBox(),
      ),
      const Size(2, 2),
    );
    expect(paths, isEmpty);
  });

  for (final density in [1.0, 2.625]) {
    for (final brightness in Brightness.values) {
      testWidgets('published opaque Toast shadow mask $density/$brightness', (
        t,
      ) async {
        t.view.devicePixelRatio = density;
        t.view.physicalSize = Size(390 * density, 600 * density);
        addTearDown(t.view.reset);
        await t.pumpWidget(
          dshTestApp(
            DshToast(text: 'Opaque source notice', onDone: () {}),
            brightness: brightness,
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 200));
        final owner = find.byType(DshShadowBox);
        final rect = t.getRect(owner);
        final clipInset = 1 / dshSnapDensity(density);
        // Flutter Path stores coordinates as float32; its reported width is
        // the difference of those stored edges, not a new layout tolerance.
        final edges = Float32List.fromList([
          clipInset,
          rect.width - clipInset,
          rect.height - clipInset,
        ]);
        final widget = t.widget<DshShadowBox>(owner);
        expect(widget.color.a, 1);
        final painter = t
            .widget<CustomPaint>(
              find
                  .descendant(of: owner, matching: find.byType(CustomPaint))
                  .first,
            )
            .painter!;
        final canvas = TestRecordingCanvas();
        painter.paint(canvas, rect.size);
        final masks = canvas.invocations.where((call) {
          if (call.invocation.memberName != #drawPath) return false;
          final paint = call.invocation.positionalArguments.last as Paint;
          return paint.blendMode == BlendMode.dstOut;
        }).toList();
        expect(masks, hasLength(widget.shadows.length));
        for (final mask in masks) {
          final bounds = (mask.invocation.positionalArguments.first as Path)
              .getBounds();
          // Pinned Blink ClipToBorderEdge insets its exclusion contour by
          // exactly one internal paint pixel (1/DPR in the native model) for an authored opaque shadow owner.
          // This test checks that source operation on the existing local
          // contour; it does not certify pre-transform coordinate snapping.
          expect(bounds.width, edges[1] - edges[0]);
          expect(bounds.height, edges[2] - edges[0]);
          expect(bounds.left, edges[0]);
          expect(bounds.top, edges[0]);
        }
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
