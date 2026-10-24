import 'package:flutter/widgets.dart';

/// Marks a subtree whose right column belongs to the desktop shell frame (dsh
/// `ui-layout` `rightbar` slot). Inside it the conversation does not draw the
/// right sidebar next to itself: the frame renders it as its own third column
/// and reports its presentation. Outside one (the phone and tablet layout) the
/// conversation keeps placing the sidebar inline.
class DshRightbarHost extends InheritedWidget {
  const DshRightbarHost({super.key, required super.child});

  /// Whether an enclosing frame owns the right column.
  static bool owned(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DshRightbarHost>() != null;

  @override
  bool updateShouldNotify(DshRightbarHost oldWidget) => false;
}

/// The right column's geometry as the frame solved it (dsh `RightbarOwnerProps`),
/// handed down to the occupant that draws the session's sidebar.
class DshRightbarGeometry extends InheritedWidget {
  const DshRightbarGeometry({
    super.key,
    required this.width,
    required this.viewportWidth,
    required this.canShow,
    required super.child,
  });

  /// Resolved normal panel width in px, not the saved preference; zero if it
  /// cannot fit.
  final double width;

  /// Current frame width in px.
  final double viewportWidth;

  /// Whether a normal right panel can retain 300px beside a 400px centre.
  final bool canShow;

  /// The enclosing geometry, or null outside a frame.
  static DshRightbarGeometry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DshRightbarGeometry>();

  @override
  bool updateShouldNotify(DshRightbarGeometry old) =>
      width != old.width ||
      viewportWidth != old.viewportWidth ||
      canShow != old.canShow;
}
