import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'dsh_recipes.g.dart';

/// Browser page viewports exclude OS bars. Flutter overlays can cover those
/// bars even when a parent's SafeArea already consumed its MediaQuery padding.
EdgeInsets dshMenuSafeInsetsOf(BuildContext context) {
  final menu = context
      .dependOnInheritedWidgetOfExactType<_MenuViewportInsets>();
  if (menu != null) return menu.insets;
  final view = View.of(context);
  return EdgeInsets.fromViewPadding(view.viewPadding, view.devicePixelRatio);
}

class _MenuViewportInsets extends InheritedWidget {
  const _MenuViewportInsets({required this.insets, required super.child});
  final EdgeInsets insets;
  @override
  bool updateShouldNotify(_MenuViewportInsets old) => insets != old.insets;
}

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
    this.gap = DshMenuRecipe.anchorGap,
    this.viewportMargin = DshMenuRecipe.portalMargin,
  });
  final LayerLink link;
  final Widget child;
  final bool alignEnd, above;
  final double? frameOverlayTop;
  final double gap, viewportMargin;
  @override
  State<DshMenuFollower> createState() => _DshMenuFollowerState();
}

class _DshMenuFollowerState extends State<DshMenuFollower>
    with WidgetsBindingObserver {
  final _root = GlobalKey(), _probe = GlobalKey();
  Rect? _anchor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
  Widget build(BuildContext context) => _MenuViewportInsets(
    insets: EdgeInsets.fromViewPadding(
      View.of(context).viewPadding,
      View.of(context).devicePixelRatio,
    ),
    child: SizedBox.expand(
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
                  safeInsets: dshMenuSafeInsetsOf(context),
                  alignEnd: widget.alignEnd,
                  above: widget.above,
                  gap: widget.gap,
                  margin: widget.viewportMargin,
                  top: math.max(
                    widget.viewportMargin,
                    widget.frameOverlayTop ?? widget.viewportMargin,
                  ),
                ),
                child: widget.child,
              ),
            ),
        ],
      ),
    ),
  );
}

class _MenuPlacement extends SingleChildLayoutDelegate {
  const _MenuPlacement(
    this.anchor, {
    required this.alignEnd,
    required this.above,
    required this.top,
    required this.safeInsets,
    required this.gap,
    required this.margin,
  });
  final Rect anchor;
  final bool alignEnd, above;
  final double top;
  final double gap, margin;
  final EdgeInsets safeInsets;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = alignEnd ? anchor.right - childSize.width : anchor.left;
    final y = above ? anchor.top - childSize.height - gap : anchor.bottom + gap;
    return Offset(
      math.min(
        math.max(x, safeInsets.left + margin),
        size.width - childSize.width - safeInsets.right - margin,
      ),
      math.min(
        math.max(y, safeInsets.top + top),
        size.height - childSize.height - safeInsets.bottom - margin,
      ),
    );
  }

  @override
  bool shouldRelayout(_MenuPlacement old) =>
      anchor != old.anchor ||
      alignEnd != old.alignEnd ||
      above != old.above ||
      top != old.top ||
      gap != old.gap ||
      margin != old.margin ||
      safeInsets != old.safeInsets;
}
