import 'dart:ui' as ui;

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<int>> rgbaAt(
  WidgetTester tester,
  GlobalKey key,
  int x,
  int y,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
      final pixel = (y * image.width + x) * 4;
      return List.generate(4, (i) => bytes.getUint8(pixel + i));
    } finally {
      image.dispose();
    }
  }))!;
}

Widget frame(
  GlobalKey key,
  List<BoxShadow> shadows, {
  bool reference = false,
  Rect? ancestorClip,
}) {
  final contents = Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 450,
          top: 90,
          child: reference
              ? CustomPaint(
                  painter: _StandaloneFarShadow(shadows),
                  child: const SizedBox(width: 40, height: 40),
                )
              : DshShadowBox(
                  color: const Color(0x80ffffff),
                  radius: 12,
                  shadows: shadows,
                  child: const SizedBox(width: 40, height: 40),
                ),
        ),
      ],
    ),
  );
  return RepaintBoundary(
    key: key,
    child: ancestorClip == null
        ? contents
        : ClipRect(
            clipper: _ExactClip(ancestorClip),
            clipBehavior: Clip.hardEdge,
            child: contents,
          ),
  );
}

class _ExactClip extends CustomClipper<Rect> {
  const _ExactClip(this.rect);
  final Rect rect;
  @override
  Rect getClip(Size size) => rect;
  @override
  bool shouldReclip(_ExactClip old) => rect != old.rect;
}

// The tested shadow is disjoint from the card, so no interior exclusion is
// needed in this independent renderer reference. Extra edge masks must not
// change its antialias coverage or the ancestor's existing hard clip.
class _StandaloneFarShadow extends CustomPainter {
  _StandaloneFarShadow(this.shadows);
  final List<BoxShadow> shadows;
  @override
  void paint(Canvas canvas, Size size) {
    for (final shadow in shadows.reversed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).shift(shadow.offset),
          const Radius.circular(12),
        ),
        Paint()..color = shadow.color,
      );
    }
  }

  @override
  bool shouldRepaint(_StandaloneFarShadow old) => shadows != old.shadows;
}

Future<List<int>> farShadowPixels(
  WidgetTester tester,
  GlobalKey key,
  double density,
  bool right,
) async => (await tester.runAsync(() async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: density);
  try {
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    final data = bytes.buffer.asUint8List();
    final left = ((right ? 600 : 0) * density).floor();
    final end = ((right ? 1000 : 300) * density).ceil();
    return [
      for (var y = (50 * density).floor(); y < (160 * density).ceil(); y++)
        ...data.sublist(
          (y * image.width + left) * 4,
          (y * image.width + end) * 4,
        ),
    ];
  } finally {
    image.dispose();
  }
}))!;

void main() {
  for (final density in [1.0, 2.625]) {
    for (final offset in [-350.25, 350.25]) {
      testWidgets(
        'fractional far shadow retains single coverage at $density/$offset',
        (tester) async {
          tester.view.physicalSize = Size(1000 * density, 240 * density);
          tester.view.devicePixelRatio = density;
          addTearDown(tester.view.reset);
          final key = GlobalKey();
          final shadows = [
            BoxShadow(
              color: const Color(0xffff0000),
              offset: Offset(offset, 0),
            ),
          ];
          await tester.pumpWidget(frame(key, shadows));
          await tester.pumpAndSettle();
          final actual = await farShadowPixels(
            tester,
            key,
            density,
            offset > 0,
          );
          await tester.pumpWidget(frame(key, shadows, reference: true));
          await tester.pumpAndSettle();
          expect(
            actual,
            await farShadowPixels(tester, key, density, offset > 0),
          );
        },
      );
    }
    testWidgets('fractional hard ancestor stays hard at $density', (
      tester,
    ) async {
      tester.view.physicalSize = Size(1000 * density, 240 * density);
      tester.view.devicePixelRatio = density;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      const clip = Rect.fromLTRB(820.25, 80.25, 870.25, 140.25);
      const shadows = [
        BoxShadow(color: Color(0xffff0000), offset: Offset(350.25, 0)),
      ];
      await tester.pumpWidget(frame(key, shadows, ancestorClip: clip));
      await tester.pumpAndSettle();
      final actual = await farShadowPixels(tester, key, density, true);
      await tester.pumpWidget(
        frame(key, shadows, ancestorClip: clip, reference: true),
      );
      await tester.pumpAndSettle();
      expect(actual, await farShadowPixels(tester, key, density, true));
    });
  }
  for (final blur in [0.0, 8.0, 16.0]) {
    testWidgets('CSS shadow blur radius $blur uses Blink standard deviation', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(frame(key, [BoxShadow(blurRadius: blur)]));
      final paint = tester
          .widget<CustomPaint>(
            find
                .descendant(
                  of: find.byType(DshShadowBox),
                  matching: find.byType(CustomPaint),
                )
                .first,
          )
          .painter!;
      final canvas = TestRecordingCanvas();
      paint.paint(canvas, const Size(40, 40));
      final draw = canvas.invocations.singleWhere(
        (call) => call.invocation.memberName == #drawRRect,
      );
      final actual = draw.invocation.positionalArguments.last as Paint;
      // Pinned Blink ShadowData::BlurRadiusToStdDev defines sigma=radius/2.
      expect(
        actual.maskFilter,
        blur == 0 ? isNull : MaskFilter.blur(BlurStyle.normal, blur / 2),
      );
    });
  }

  for (final offset in [-350.0, 350.0]) {
    testWidgets(
      'source shadow offset $offset is not cut off at a fixed reach',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 220);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(
          frame(key, [
            BoxShadow(
              color: const Color(0xffff0000),
              offset: Offset(offset, 0),
            ),
          ]),
        );
        await tester.pumpAndSettle();
        expect(await rgbaAt(tester, key, (470 + offset).round(), 110), [
          255,
          0,
          0,
          255,
        ]);
      },
    );
  }

  testWidgets('exterior shadow does not fill a translucent card interior', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      frame(key, const [BoxShadow(color: Color(0xffff0000), spreadRadius: 20)]),
    );
    await tester.pumpAndSettle();
    expect(await rgbaAt(tester, key, 470, 110), [255, 255, 255, 128]);
    expect(await rgbaAt(tester, key, 440, 110), [255, 0, 0, 255]);
  });

  testWidgets('source first-listed shadow remains the top layer', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      frame(key, const [
        BoxShadow(color: Color(0xffff0000), blurRadius: 8),
        BoxShadow(color: Color(0xff00ff00), blurRadius: 16),
      ]),
    );
    final painter = tester
        .widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(DshShadowBox),
                matching: find.byType(CustomPaint),
              )
              .first,
        )
        .painter!;
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, const Size(40, 40));
    final colors = canvas.invocations
        .where((call) => call.invocation.memberName == #drawRRect)
        .map(
          (call) => (call.invocation.positionalArguments.last as Paint).color,
        );
    expect(colors, [const Color(0xff00ff00), const Color(0xffff0000)]);
  });

  testWidgets('negative spread that removes the box paints no shadow', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      frame(key, const [BoxShadow(spreadRadius: -30, blurRadius: 8)]),
    );
    final painter = tester
        .widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(DshShadowBox),
                matching: find.byType(CustomPaint),
              )
              .first,
        )
        .painter!;
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, const Size(40, 40));
    expect(
      canvas.invocations.where(
        (call) => call.invocation.memberName == #drawRRect,
      ),
      isEmpty,
    );
  });
}
