import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A CSS `display: flex; flex-wrap: wrap; align-items: center; gap: spacing`
/// row with one growing spacer (`flex: 1 1 0`), as dsh's dialog footer is: the
/// items fill a line in order and wrap onto the next one when they no longer
/// fit; on the line that holds the spacer it takes the free space, which pushes
/// what follows to the far edge. A line without the spacer is start-aligned.
class FlexWrapRow extends MultiChildRenderObjectWidget {
  const FlexWrapRow({
    super.key,
    required this.spacerIndex,
    this.spacing = 8,
    this.runSpacing = 8,
    super.children,
  });

  /// The index of the spacer among [children] (its own size is ignored).
  final int spacerIndex;
  final double spacing;
  final double runSpacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFlexWrap(spacerIndex, spacing, runSpacing);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    renderObject as _RenderFlexWrap;
    renderObject
      ..spacerIndex = spacerIndex
      ..spacing = spacing
      ..runSpacing = runSpacing;
  }
}

class _ParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderFlexWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ParentData> {
  _RenderFlexWrap(this._spacerIndex, this._spacing, this._runSpacing);

  int _spacerIndex;
  double _spacing;
  double _runSpacing;

  set spacerIndex(int v) {
    if (v == _spacerIndex) return;
    _spacerIndex = v;
    markNeedsLayout();
  }

  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  set runSpacing(double v) {
    if (v == _runSpacing) return;
    _runSpacing = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ParentData) child.parentData = _ParentData();
  }

  List<RenderBox> get _items {
    final out = <RenderBox>[];
    var c = firstChild;
    while (c != null) {
      out.add(c);
      c = (c.parentData! as _ParentData).nextSibling;
    }
    return out;
  }

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth;
    final items = _items;
    final sizes = <Size>[];
    for (var i = 0; i < items.length; i++) {
      if (i == _spacerIndex) {
        items[i].layout(BoxConstraints.tight(Size.zero), parentUsesSize: true);
        sizes.add(Size.zero);
      } else {
        items[i].layout(
          BoxConstraints(maxWidth: maxWidth),
          parentUsesSize: true,
        );
        sizes.add(items[i].size);
      }
    }
    // Greedy line breaking, the gap counted between every pair of items.
    final lines = <List<int>>[];
    var line = <int>[];
    var used = 0.0;
    for (var i = 0; i < items.length; i++) {
      final next = line.isEmpty
          ? sizes[i].width
          : used + _spacing + sizes[i].width;
      if (line.isNotEmpty && next > maxWidth + 0.001) {
        lines.add(line);
        line = [i];
        used = sizes[i].width;
      } else {
        line.add(i);
        used = next;
      }
    }
    if (line.isNotEmpty) lines.add(line);
    var y = 0.0;
    var width = 0.0;
    for (final l in lines) {
      var natural = 0.0;
      var height = 0.0;
      for (var k = 0; k < l.length; k++) {
        natural += sizes[l[k]].width + (k == 0 ? 0 : _spacing);
        if (sizes[l[k]].height > height) height = sizes[l[k]].height;
      }
      final spacerHere = l.contains(_spacerIndex);
      final grow = spacerHere ? (maxWidth - natural).clamp(0.0, maxWidth) : 0.0;
      var x = 0.0;
      for (var k = 0; k < l.length; k++) {
        final i = l[k];
        final w = i == _spacerIndex ? grow : sizes[i].width;
        (items[i].parentData! as _ParentData).offset = Offset(
          x,
          y + (height - sizes[i].height) / 2,
        );
        x += w + _spacing;
      }
      x -= _spacing;
      if (x > width) width = x;
      y += height + _runSpacing;
    }
    if (lines.isNotEmpty) y -= _runSpacing;
    size = constraints.constrain(Size(width, y));
  }

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      Size(constraints.maxWidth, 0);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
