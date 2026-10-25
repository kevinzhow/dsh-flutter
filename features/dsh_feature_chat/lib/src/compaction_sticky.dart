import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Pins the first child inside this row's bounds, rather than imposing a
/// second scrollport on a long summary. Paint, pointer and semantics geometry
/// use the same offset; it works inside either side of the chat timeline.
class CompactionSticky extends MultiChildRenderObjectWidget {
  CompactionSticky({super.key, required Widget header, required Widget body})
    : super(children: [header, body]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _Sticky(Scrollable.maybeOf(context)?.position);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _Sticky).position = Scrollable.maybeOf(context)?.position;
  }
}

class _StickyParentData extends ContainerBoxParentData<RenderBox> {}

class _Sticky extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _Sticky(this._position);
  ScrollPosition? _position;
  set position(ScrollPosition? value) {
    if (_position == value) return;
    if (attached) _position?.removeListener(_scrolled);
    _position = value;
    if (attached) _position?.addListener(_scrolled);
    markNeedsPaint();
  }

  void _scrolled() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position?.addListener(_scrolled);
  }

  @override
  void detach() {
    _position?.removeListener(_scrolled);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _StickyParentData();
    }
  }

  @override
  void performLayout() {
    final header = firstChild!, body = lastChild!;
    final childConstraints = BoxConstraints(
      minWidth: constraints.minWidth,
      maxWidth: constraints.maxWidth,
    );
    header.layout(childConstraints, parentUsesSize: true);
    body.layout(childConstraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(
        math.max(header.size.width, body.size.width),
        header.size.height + body.size.height,
      ),
    );
  }

  double get _pin {
    if (_position == null) return 0;
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport == null) return 0;
    final top = localToGlobal(Offset.zero, ancestor: viewport).dy;
    return (-top).clamp(0, math.max(0, size.height - firstChild!.size.height));
  }

  Offset _offset(RenderBox child) => child == firstChild
      ? Offset(0, _pin)
      : Offset(0, firstChild!.size.height);
  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(lastChild!, offset + _offset(lastChild!));
    context.paintChild(firstChild!, offset + _offset(firstChild!));
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = _offset(child);
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in [firstChild!, lastChild!]) {
      if (result.addWithPaintOffset(
        offset: _offset(child),
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      )) {
        return true;
      }
    }
    return false;
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    RenderBox? child = firstChild;
    while (child != null) {
      visitor(child);
      child =
          (child.parentData! as ContainerBoxParentData<RenderBox>).nextSibling;
    }
  }
}
