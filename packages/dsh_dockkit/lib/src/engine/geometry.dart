/// Pure geometry for the drag interaction (dsh `engine/geometry.ts`): point
/// tests, dock-zone resolution against a real element rectangle, and tab-strip
/// insertion slots. Free of Flutter types so the drop rules can be asserted
/// without a UI; the widget layer measures rectangles and calls in.
library;

import 'constraints.dart';
import 'types.dart';

/// A measured rectangle in viewport coordinates.
class DockRect extends DockValue {
  const DockRect(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  @override
  List<Object?> get props => [x, y, width, height];
}

/// Where a drag would land if released now.
sealed class DropTarget extends DockValue {
  const DropTarget();
}

/// Into a tab strip at an explicit slot: a reorder or a cross-pane move.
class StripDrop extends DropTarget {
  const StripDrop(this.paneId, this.index);

  final PaneId paneId;
  final int index;

  @override
  List<Object?> get props => [paneId, index];
}

/// Onto a pane body: the centre moves the tab in, an edge splits the pane.
class ZoneDrop extends DropTarget {
  const ZoneDrop(this.paneId, this.zone);

  final PaneId paneId;
  final DockZone zone;

  @override
  List<Object?> get props => [paneId, zone];
}

/// Whether a point is inside a rectangle, edges included.
bool containsPoint(DockRect rect, double x, double y) =>
    x >= rect.x &&
    x <= rect.x + rect.width &&
    y >= rect.y &&
    y <= rect.y + rect.height;

/// Dock region a point falls in, relative to one pane's rectangle.
DockZone zoneInRect(
  DockRect rect,
  double x,
  double y, [
  double edge = dockEdgeFraction,
]) {
  if (!(rect.width > 0) || !(rect.height > 0)) return DockZone.center;
  return zoneAt((x - rect.x) / rect.width, (y - rect.y) / rect.height, edge);
}

/// Slot a tab would take in a strip, by comparing the pointer with each tab's
/// midpoint. From 0 to `tabRects.length`.
int insertionIndex(List<DockRect> tabRects, double x) {
  var index = 0;
  for (final rect in tabRects) {
    if (x < rect.x + rect.width / 2) break;
    index += 1;
  }
  return index;
}

/// What one pane's strip measured, for the room rule.
class PaneMeasure {
  const PaneMeasure({
    required this.pane,
    required this.strip,
    required this.chipsWidth,
    required this.fillWidth,
    this.splitControlWidth = 0,
  });

  /// The pane's box, borders included.
  final DockRect pane;

  /// The strip's box, inside the borders; its height is what a vertical half must carry.
  final DockRect strip;

  /// Width of the chip box, the strip's one shrinking part.
  final double chipsWidth;

  /// Width of the fill: free space, not a control.
  final double fillWidth;

  /// Footprint of the rendered split control for embedders that hide blocked
  /// split controls (see dsh `PaneMeasure.splitControlWidth`). 0 keeps the
  /// control in the fixed part.
  final double splitControlWidth;
}

/// Pixel minimums the room rule holds each half to.
class SplitMinimums {
  const SplitMinimums({
    required this.divider,
    required this.chip,
    required this.body,
  });

  /// The divider a split puts between the halves.
  final double divider;

  /// One chip at its minimum: the smallest strip that still names a tab.
  final double chip;

  /// The smallest body under a strip.
  final double body;
}

/// The minimums where no computed style can be read (dsh `dockkit.module.css`):
/// the divider takes no layout width, a chip is 80 + 10 + 10, a body 48.
const SplitMinimums defaultSplitMinimums = SplitMinimums(
  divider: 0,
  chip: 100,
  body: 48,
);

/// Whether a pane's two halves after an equal split would each still work.
class HalvesFit {
  const HalvesFit({required this.row, required this.column});

  /// A row split: each half holds the strip's fixed controls and one minimum chip.
  final bool row;

  /// A column split: each half holds the strip and a minimum body.
  final bool column;
}

/// The room rule: after an equal split each half must hold what cannot shrink.
/// An unmeasured pane (no layout) fits: the rule only blocks on a positive
/// reading.
HalvesFit halvesFit(
  PaneMeasure measure, [
  SplitMinimums minimums = defaultSplitMinimums,
]) {
  final pane = measure.pane;
  final strip = measure.strip;
  if (!(pane.width > 0) || !(pane.height > 0) || !(strip.width > 0)) {
    return const HalvesFit(row: true, column: true);
  }
  final borders = (pane.width - strip.width) < 0
      ? 0.0
      : pane.width - strip.width;
  final rawFixed =
      strip.width -
      measure.chipsWidth -
      measure.fillWidth -
      measure.splitControlWidth;
  final fixed = rawFixed < 0 ? 0.0 : rawFixed;
  final halfWidth = (pane.width - minimums.divider) / 2 - borders;
  final halfHeight = (pane.height - minimums.divider) / 2 - borders;
  return HalvesFit(
    row: halfWidth >= fixed + minimums.chip,
    column: halfHeight >= strip.height + minimums.body,
  );
}

/// How far a pointer must travel before a press becomes a drag, in pixels.
const double dragThreshold = 4;

/// Whether a press has travelled far enough to be a drag.
bool passedThreshold(double startX, double startY, double x, double y) =>
    (x - startX).abs() >= dragThreshold || (y - startY).abs() >= dragThreshold;

/// Split fractions after a divider drag: the boundary between [index] and
/// `index + 1` moves by [delta] (a fraction of the split's extent); the two
/// neighbours absorb the whole change.
List<double> dividerSizes(List<double> sizes, int index, double delta) {
  if (index < 0 || index + 1 >= sizes.length) return [...sizes];
  final next = [...sizes];
  next[index] = sizes[index] + delta;
  next[index + 1] = sizes[index + 1] - delta;
  return next;
}

/// A width/height pair used as a floating-panel bound.
class DockSize {
  const DockSize(this.width, this.height);

  final double width;
  final double height;
}

/// A floating panel's rectangle after a drag; the size is unchanged.
FloatRect movedRect(FloatRect rect, double dx, double dy) =>
    rect.copyWith(x: rect.x + dx, y: rect.y + dy);

/// A floating panel's rectangle after a bottom-right resize; the origin is
/// unchanged.
FloatRect resizedRect(FloatRect rect, double dx, double dy, DockSize min) =>
    rect.copyWith(
      width: (rect.width + dx) < min.width ? min.width : rect.width + dx,
      height: (rect.height + dy) < min.height ? min.height : rect.height + dy,
    );

/// How far the new panel's origin sits above and left of the drop point.
const double _grabOffsetX = 60;
const double _grabOffsetY = 14;

/// Where a panel should appear when a tab is dropped outside the docked area:
/// a rectangle whose header sits under the drop point.
FloatRect floatRectAt(double x, double y, DockSize size) => FloatRect(
  (x - _grabOffsetX) < 0 ? 0 : x - _grabOffsetX,
  (y - _grabOffsetY) < 0 ? 0 : y - _grabOffsetY,
  size.width,
  size.height,
);
