import 'dart:math' as math;

import 'package:flutter/widgets.dart';

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
  });

  final Color color;
  final double radius;
  final List<BoxShadow> shadows;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _OuterShadowPainter(shadows, radius),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
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
  _OuterShadowPainter(this.shadows, this.radius);

  final List<BoxShadow> shadows;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(
        Rect.fromLTWH(-200, -200, size.width + 400, size.height + 400),
      ),
      Path()..addRRect(box),
    );
    canvas.save();
    canvas.clipPath(outside);
    for (final s in shadows.reversed) {
      final rrect = box.shift(s.offset).inflate(s.spreadRadius);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = s.color
          ..maskFilter = s.blurRadius > 0
              ? MaskFilter.blur(BlurStyle.normal, _chromiumSigma(s.blurRadius))
              : null,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.radius != radius || old.shadows != shadows;
}
