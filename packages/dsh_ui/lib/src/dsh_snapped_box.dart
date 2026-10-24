import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'dsh_pixel_snap.dart';

/// A [DecoratedBox] whose decoration (fill, border, shadow) is painted at the
/// rectangle Blink paints a box at: every edge rounded to a whole device pixel
/// ([dshSnapRect], `PixelSnappedIntRect`), measured on the display and not in
/// the box's own coordinates.
///
/// Layout is untouched (the box keeps its fractional size and position, and so
/// does its child); only the painted rectangle moves by up to half a device
/// pixel. At a whole density with whole logical sizes that is nothing; on a
/// fractional density (2.625x) it is the difference between a crisp 1-device
/// pixel border and one smeared over two rows. A box under a rotation or scale
/// is painted as it is.
class DshDecoratedBox extends SingleChildRenderObjectWidget {
  const DshDecoratedBox({super.key, required this.decoration, super.child});

  final Decoration decoration;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDshDecoratedBox(
        decoration,
        dshDevicePixelRatioOf(context),
        Directionality.maybeOf(context),
      );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderDshDecoratedBox)
      ..decoration = decoration
      ..devicePixelRatio = dshDevicePixelRatioOf(context)
      ..textDirection = Directionality.maybeOf(context);
  }
}

class _RenderDshDecoratedBox extends RenderProxyBox {
  _RenderDshDecoratedBox(
    this._decoration,
    this._devicePixelRatio,
    this._textDirection,
  );

  Decoration _decoration;
  double _devicePixelRatio;
  TextDirection? _textDirection;
  BoxPainter? _painter;

  set decoration(Decoration value) {
    if (value == _decoration) return;
    _painter?.dispose();
    _painter = null;
    _decoration = value;
    markNeedsPaint();
  }

  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  set textDirection(TextDirection? value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsPaint();
  }

  @override
  bool hitTestSelf(Offset position) => _decoration.hitTest(size, position);

  @override
  void detach() {
    _painter?.dispose();
    _painter = null;
    super.detach();
    markNeedsPaint();
  }

  @override
  void dispose() {
    _painter?.dispose();
    _painter = null;
    super.dispose();
  }

  /// [offset] & [size] with its edges snapped on the display.
  Rect _paintRect(Offset offset) {
    final rect = offset & size;
    final matrix = getTransformTo(null);
    final m = matrix.storage;
    final translationOnly =
        m[0] == 1 &&
        m[5] == 1 &&
        m[1] == 0 &&
        m[4] == 0 &&
        m[3] == 0 &&
        m[7] == 0;
    if (!translationOnly) return rect;
    final origin = Offset(m[12], m[13]);
    final snapped = dshSnapRect(origin & size, _devicePixelRatio);
    return snapped.shift(offset - origin);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _painter ??= _decoration.createBoxPainter(markNeedsPaint);
    final rect = _paintRect(offset);
    _painter!.paint(
      context.canvas,
      rect.topLeft,
      ImageConfiguration(size: rect.size, textDirection: _textDirection),
    );
    super.paint(context, offset);
  }
}

/// A [Container] with a decoration painted by [DshDecoratedBox]: the same
/// alignment, padding (plus the decoration's own), constraints and margin
/// around it (no clip, no transform: no site of the product needs them).
class DshContainer extends StatelessWidget {
  DshContainer({
    super.key,
    this.alignment,
    this.padding,
    required this.decoration,
    double? width,
    double? height,
    BoxConstraints? constraints,
    this.margin,
    this.child,
  }) : constraints = (width != null || height != null)
           ? (constraints?.tighten(width: width, height: height) ??
                 BoxConstraints.tightFor(width: width, height: height))
           : constraints;

  final AlignmentGeometry? alignment;
  final EdgeInsetsGeometry? padding;
  final Decoration decoration;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? margin;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    Widget? current = child;
    if (child == null && (constraints == null || !constraints!.isTight)) {
      current = LimitedBox(
        maxWidth: 0,
        maxHeight: 0,
        child: ConstrainedBox(constraints: const BoxConstraints.expand()),
      );
    } else if (alignment != null) {
      current = Align(alignment: alignment!, child: current);
    }
    final effectivePadding = padding == null
        ? decoration.padding
        : padding!.add(decoration.padding);
    if (effectivePadding != EdgeInsets.zero) {
      current = Padding(padding: effectivePadding, child: current);
    }
    current = DshDecoratedBox(decoration: decoration, child: current);
    if (constraints != null) {
      current = ConstrainedBox(constraints: constraints!, child: current);
    }
    if (margin != null) current = Padding(padding: margin!, child: current);
    return current;
  }
}
