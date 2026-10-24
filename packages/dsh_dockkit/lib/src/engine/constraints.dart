/// Interaction limits and dock geometry (dsh `engine/constraints.ts`). The model
/// itself is unbounded; these are the V1 rules the interaction layer enforces
/// before it dispatches, kept pure so they can be asserted without a UI.
library;

import 'tree.dart';
import 'types.dart';

/// V1 caps the docked grid at four panes; floating panes do not count.
const int maxDockPanes = 4;

/// Smallest fraction a divider drag may leave a pane, as a share of its split.
const double minPaneFraction = 0.12;

/// Size a tab takes when it first floats, in logical pixels.
const double floatDefaultWidth = 380;
const double floatDefaultHeight = 300;

/// Smallest size a floating panel may be resized to, in logical pixels.
const double floatMinWidth = 220;
const double floatMinHeight = 140;

/// Fraction of a pane's width or height that counts as its dock edge.
const double dockEdgeFraction = 0.25;

/// Number of docked panes; floating panes do not count.
int dockPaneCount(LayoutState state) => dockPaneIds(state).length;

/// Whether another docked pane is allowed ([maxPanes] defaults to the kit's
/// four; the right sidebar embeds the kit with two).
bool canSplit(LayoutState state, [int maxPanes = maxDockPanes]) =>
    dockPaneCount(state) < maxPanes;

/// The five dock regions a tab can be dropped on.
const List<DockZone> dockZones = [
  DockZone.center,
  DockZone.top,
  DockZone.right,
  DockZone.bottom,
  DockZone.left,
];

/// Which dock region a pointer sits in. [x] and [y] are fractions of the pane's
/// width and height; [edge] is the edge band width as a fraction. The closest
/// edge when the pointer is inside its band, else [DockZone.center].
DockZone zoneAt(double x, double y, [double edge = dockEdgeFraction]) {
  var zone = DockZone.left;
  var distance = x;
  if (1 - x < distance) {
    zone = DockZone.right;
    distance = 1 - x;
  }
  if (y < distance) {
    zone = DockZone.top;
    distance = y;
  }
  if (1 - y < distance) {
    zone = DockZone.bottom;
    distance = 1 - y;
  }
  return distance < edge ? zone : DockZone.center;
}

/// How a dock region splits the pane it targets, or null for
/// [DockZone.center], which moves the tab into the pane instead.
({SplitAxis axis, SplitDirection direction})? zoneSplit(
  DockZone zone,
) => switch (zone) {
  DockZone.center => null,
  DockZone.left => (axis: SplitAxis.row, direction: SplitDirection.before),
  DockZone.right => (axis: SplitAxis.row, direction: SplitDirection.after),
  DockZone.top => (axis: SplitAxis.column, direction: SplitDirection.before),
  DockZone.bottom => (axis: SplitAxis.column, direction: SplitDirection.after),
};

/// Clamp divider sizes so no pane falls under [minimum] (default
/// [minPaneFraction]). Fractions summing to 1 with every entry at or above it.
List<double> clampSizes(
  List<double> sizes, [
  double minimum = minPaneFraction,
]) {
  if (sizes.isEmpty) return [];
  final floor = minimum < 1 / sizes.length ? minimum : 1 / sizes.length;
  final positive = [for (final size in sizes) size > 0 ? size : 0.0];
  final total = positive.fold<double>(0, (sum, size) => sum + size);
  var shares = total > 0
      ? [for (final size in positive) size / total]
      : [for (final _ in sizes) 1 / sizes.length];
  // Pin every share under the floor at the floor and hand the remainder to the
  // others in proportion; a share that only now drops under joins the pinned
  // set on the next pass, so the result holds the floor exactly.
  final pinned = <int>{};
  for (;;) {
    final under = [
      for (var i = 0; i < shares.length; i++)
        if (!pinned.contains(i) && shares[i] < floor) i,
    ];
    if (under.isEmpty) return shares;
    pinned.addAll(under);
    final remainder = 1 - pinned.length * floor;
    var freeTotal = 0.0;
    for (var i = 0; i < shares.length; i++) {
      if (!pinned.contains(i)) freeTotal += shares[i];
    }
    shares = [
      for (var i = 0; i < shares.length; i++)
        pinned.contains(i) ? floor : (shares[i] / freeTotal) * remainder,
    ];
  }
}
