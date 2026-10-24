/// Normal column geometry of dsh's three-column frame (`ui-layout`
/// `columns.ts`): the right column shrinks, then loses its track, before the
/// center drops below its minimum. The sidebar never concedes here; the frame
/// supplies its effective preference after responsive collapse.
library;

import 'dart:math' as math;

/// Resolved widths for one frame.
class Columns {
  const Columns({
    required this.sidebar,
    required this.center,
    required this.rightbar,
  });

  final double sidebar;
  final double center;
  final double rightbar;

  @override
  bool operator ==(Object other) =>
      other is Columns &&
      other.sidebar == sidebar &&
      other.center == center &&
      other.rightbar == rightbar;

  @override
  int get hashCode => Object.hash(sidebar, center, rightbar);

  @override
  String toString() =>
      'Columns(sidebar: $sidebar, center: $center, rightbar: $rightbar)';
}

/// Center width protected while the normal right column is open.
const double centerMin = 400;

/// Sidebar drag clamp floor.
const double sidebarMin = 264;

/// Sidebar drag clamp ceiling.
const double sidebarMax = 420;

/// Sidebar width before any user drag.
const double sidebarDefault = 280;

/// Closed-sidebar rail: a 24px icon column between 16px horizontal paddings.
const double sidebarCollapsed = 56;

/// Viewport width below which the sidebar auto-collapses to the rail (deepsuite
/// LG breakpoint); a manual toggle below it re-expands over the squeezed
/// center (the store's `narrowExpanded`).
const double sidebarAutoCollapse = 1024;

/// Below this width dsh presents the right panel fullscreen automatically (and
/// is, by that measure, a phone).
const double phoneBreakpoint = 768;

/// Right column drag clamp floor.
const double rightbarMin = 300;

/// Maximum normal right panel width as a fraction of the frame.
const double rightbarMaxRatio = 0.7;

/// First-open right panel preference as a fraction of the frame.
const double rightbarDefaultRatio = 0.45;

/// JavaScript's `Math.round`: halves go up (Dart's rounds them away from zero).
int jsRound(double value) => (value + 0.5).floorToDouble().toInt();

/// Clamp a panel width into its contract range and round it to whole pixels.
double clampWidth(double px, double min, double max) =>
    math.min(max, math.max(min, jsRound(px).toDouble()));

/// Solve the three column widths for one viewport frame.
///
/// [sidebar] is the sidebar width preference in px (0 = closed), [rightbar] the
/// requested right panel width in px (0 = no track), [collapsedWidth] the track
/// width of the closed sidebar (the default keeps the icon rail, 0 hides the
/// column entirely: macOS and Windows desktop). Returns the actual widths after
/// shrinking or removing the right track; only without that track may the
/// center fall below its minimum, down to zero.
Columns computeColumns(
  double viewport,
  double sidebar,
  double rightbar, [
  double collapsedWidth = sidebarCollapsed,
]) {
  final s = sidebar == 0
      ? collapsedWidth
      : clampWidth(sidebar, sidebarMin, sidebarMax);
  final available = viewport - s - centerMin;
  final r = rightbar == 0 || available < rightbarMin
      ? 0.0
      : math.min(
          available,
          clampWidth(rightbar, rightbarMin, viewport * rightbarMaxRatio),
        );
  return Columns(
    sidebar: s,
    center: math.max(0, viewport - s - r),
    rightbar: r,
  );
}
