import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'dsh_snapped_box.dart';
import 'dsh_corners.dart';

/// A rounded surface with CSS `box-shadow` semantics: [shadows] are painted
/// outside the border box only, so a translucent [color] (dsh's menu surface)
/// does not show them through, unlike Flutter's own `BoxDecoration.boxShadow`.
class DshShadowBox extends StatelessWidget {
  const DshShadowBox({
    super.key,
    required this.color,
    required this.radius,
    required this.shadows,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.shape,
  });

  final Color color;
  final double radius;
  final List<BoxShadow> shadows;
  final EdgeInsetsGeometry padding;
  final Widget child;
  final DshCornerBorder? shape;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _OuterShadowPainter(shadows, radius, shape),
    child: DshDecoratedBox(
      decoration: shape == null
          ? BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
            )
          : ShapeDecoration(color: color, shape: shape!),
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// Blink ShadowData::BlurRadiusToStdDev uses half the authored CSS radius.
/// This differs from Flutter Shadow's legacy radius-to-sigma conversion.
double _cssShadowSigma(double blur) => blur / 2;

class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter(this.shadows, this.radius, this.shape);

  final List<BoxShadow> shadows;
  final double radius;
  final DshCornerBorder? shape;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final outer =
        shape?.getOuterPath(Offset.zero & size) ?? (Path()..addRRect(box));
    for (final s in shadows.reversed) {
      final rrect = box.shift(s.offset).inflate(s.spreadRadius);
      if (rrect.isEmpty) continue;
      // Dart exposes no inverse path clip. Mask each shadow separately to
      // preserve CSS layer ordering and avoid an extra antialiased exterior
      // rectangle at a fractional shadow or ancestor-clip edge.
      canvas.saveLayer(null, Paint());
      final paint = Paint()
        ..color = s.color
        ..maskFilter = s.blurRadius > 0
            ? MaskFilter.blur(BlurStyle.normal, _cssShadowSigma(s.blurRadius))
            : null;
      if (shape == null) {
        canvas.drawRRect(rrect, paint);
      } else {
        canvas.drawPath(
          shape!
              .copyWith(radius: math.max(0, radius + s.spreadRadius))
              .getOuterPath(
                (Offset.zero & size).shift(s.offset).inflate(s.spreadRadius),
              ),
          paint,
        );
      }
      canvas.drawPath(outer, Paint()..blendMode = BlendMode.dstOut);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.radius != radius || old.shadows != shadows || old.shape != shape;
}
