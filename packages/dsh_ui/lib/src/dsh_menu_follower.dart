import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'dsh_recipes.g.dart';

/// Linked menu placement with the source portal's viewport clamping. The
/// zero-sized follower measures the actual composited anchor, including scroll
/// and ancestor transforms; the visible card is laid out in overlay coordinates.
/// Its parent must fill the overlay so its entire visible card receives input.
class DshMenuFollower extends StatefulWidget {
  const DshMenuFollower({
    super.key,
    required this.link,
    required this.child,
    this.alignEnd = false,
    this.above = false,
    this.frameOverlayTop,
  });
  final LayerLink link;
  final Widget child;
  final bool alignEnd, above;
  final double? frameOverlayTop;
  @override
  State<DshMenuFollower> createState() => _DshMenuFollowerState();
}

class _DshMenuFollowerState extends State<DshMenuFollower> {
  final _root = GlobalKey(), _probe = GlobalKey();
  Rect? _anchor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  void _measure(Duration _) {
    if (!mounted) return;
    final root = _root.currentContext?.findRenderObject();
    final probe = _probe.currentContext?.findRenderObject();
    final size = widget.link.leaderSize;
    final anchor =
        widget.link.leader == null ||
            size == null ||
            root is! RenderBox ||
            probe is! RenderBox
        ? null
        : MatrixUtils.transformRect(
            probe.getTransformTo(root),
            Offset.zero & size,
          );
    if (_anchor != anchor) setState(() => _anchor = anchor);
    // This does not schedule idle frames. A scrolling/transforming anchor
    // already causes a frame; observe its composition and update if it moved.
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    key: _root,
    child: Stack(
      children: [
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          child: SizedBox.shrink(key: _probe),
        ),
        if (_anchor case final Rect anchor)
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _MenuPlacement(
                anchor,
                alignEnd: widget.alignEnd,
                above: widget.above,
                top: math.max(
                  DshMenuRecipe.portalMargin,
                  widget.frameOverlayTop ?? DshMenuRecipe.portalMargin,
                ),
              ),
              child: widget.child,
            ),
          ),
      ],
    ),
  );
}

class _MenuPlacement extends SingleChildLayoutDelegate {
  const _MenuPlacement(
    this.anchor, {
    required this.alignEnd,
    required this.above,
    required this.top,
  });
  final Rect anchor;
  final bool alignEnd, above;
  final double top;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = alignEnd ? anchor.right - childSize.width : anchor.left;
    final y = above
        ? anchor.top - childSize.height - DshMenuRecipe.anchorGap
        : anchor.bottom + DshMenuRecipe.anchorGap;
    return Offset(
      math.min(
        math.max(x, DshMenuRecipe.portalMargin),
        size.width - childSize.width - DshMenuRecipe.portalMargin,
      ),
      math.min(
        math.max(y, top),
        size.height - childSize.height - DshMenuRecipe.portalMargin,
      ),
    );
  }

  @override
  bool shouldRelayout(_MenuPlacement old) =>
      anchor != old.anchor ||
      alignEnd != old.alignEnd ||
      above != old.above ||
      top != old.top;
}
