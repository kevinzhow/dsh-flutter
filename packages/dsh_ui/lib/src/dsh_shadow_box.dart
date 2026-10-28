import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'dsh_snapped_box.dart';
import 'dsh_corners.dart';

/// A rounded surface with CSS `box-shadow` semantics: [shadows] are painted
/// outside the source owner's exclusion contour. Translucent source owners
/// exclude the full border box; an authored opaque background uses Blink's
/// one-CSS-pixel inset to prevent antialias gaps. This preserves the existing
/// local paint coordinates; source pre-transform snapping remains separate.
class DshShadowBox extends StatelessWidget {
  const DshShadowBox({
    super.key,
    required this.color,
    required this.radius,
    required this.shadows,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.shape,
    this.authoredOpaqueBackground = false,
  });

  final Color color;
  final double radius;
  final List<BoxShadow> shadows;
  final EdgeInsetsGeometry padding;
  final Widget child;
  final DshCornerBorder? shape;

  /// Whether the source shadow owner itself has an opaque authored background.
  /// A translucent source material precomposited onto an opaque ground does
  /// not qualify. Keep that distinction explicit at the canonical caller.
  final bool authoredOpaqueBackground;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _OuterShadowPainter(
      shadows,
      radius,
      shape,
      authoredOpaqueBackground: authoredOpaqueBackground,
    ),
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

// Pinned Chromium145 box_painter_base.cc::ClipToBorderEdge. This is a renderer
// coverage operation, independent of the generated component's geometry.
const _opaqueShadowClipInset = 1.0;

class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter(
    this.shadows,
    this.radius,
    this.shape, {
    this.authoredOpaqueBackground = false,
  });

  final List<BoxShadow> shadows;
  final double radius;
  final DshCornerBorder? shape;
  final bool authoredOpaqueBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final box = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    // Chromium145 ClipToBorderEdge insets the excluded contour by one CSS
    // pixel only for an authored opaque owner, preventing antialias gaps.
    // DshCornerBorder's inner path preserves curvature and shrinks radii.
    final maskRect = authoredOpaqueBackground
        ? rect.deflate(_opaqueShadowClipInset)
        : rect;
    final outer = maskRect.isEmpty
        ? null
        : shape != null
        ? authoredOpaqueBackground
              ? shape!
                    .copyWith(
                      side: const BorderSide(width: _opaqueShadowClipInset),
                    )
                    .getInnerPath(rect)
              : shape!.getOuterPath(rect)
        : (Path()..addRRect(
            RRect.fromRectAndRadius(
              maskRect,
              Radius.circular(
                math.max(
                  0,
                  radius -
                      (authoredOpaqueBackground ? _opaqueShadowClipInset : 0),
                ),
              ),
            ),
          ));
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
              .getOuterPath(rect.shift(s.offset).inflate(s.spreadRadius)),
          paint,
        );
      }
      if (outer != null) {
        canvas.drawPath(outer, Paint()..blendMode = BlendMode.dstOut);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.radius != radius ||
      old.shadows != shadows ||
      old.shape != shape ||
      old.authoredOpaqueBackground != authoredOpaqueBackground;
}
