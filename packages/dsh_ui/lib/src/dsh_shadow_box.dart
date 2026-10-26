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

/// The Gaussian sigma (logical px) Chromium's low-alpha box shadows land on
/// for a CSS blur radius. Fitted on Chromium's own output for dsh's panel
/// elevation (8px and 16px layers at 2-3%): Chromium truncates the Gaussian
/// tails of faint shadows, so the textbook `blur / 2` over-spreads them and
/// Flutter's own `blur * 0.58 + 0.5` still does.
double _chromiumSigma(double blur) => math.max(0.5, 0.45 * blur - 2.1);

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
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(
        Rect.fromLTWH(-200, -200, size.width + 400, size.height + 400),
      ),
      outer,
    );
    canvas.save();
    canvas.clipPath(outside);
    for (final s in shadows.reversed) {
      final rrect = box.shift(s.offset).inflate(s.spreadRadius);
      final paint = Paint()
        ..color = s.color
        ..maskFilter = s.blurRadius > 0
            ? MaskFilter.blur(BlurStyle.normal, _chromiumSigma(s.blurRadius))
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
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.radius != radius || old.shadows != shadows || old.shape != shape;
}
