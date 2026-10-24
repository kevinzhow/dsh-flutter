/// Intent planning (dsh `engine/planner.ts`): each interaction, as a pure
/// function from the current state to the operations that carry it out.
///
/// Planners mint the ids their operations create and enforce the interaction
/// limits, but they hold no state and apply nothing. A planner returning no
/// operations means the intent changes nothing; the caller records nothing and
/// notifies nobody.
library;

import 'constraints.dart';
import 'initial.dart';
import 'operations.dart';
import 'tree.dart';
import 'types.dart';

/// Distance each newly floated panel steps down and right from the last.
const double _floatCascadeStep = 24;

/// Where the first floating panel appears, in viewport pixels.
const double _floatOriginX = 160;
const double _floatOriginY = 120;

const List<LayoutOp> _nothing = [];

/// Where a new tab should go and what it should say.
class OpenContentInput {
  const OpenContentInput({
    required this.contentId,
    required this.title,
    required this.kind,
    this.paneId,
    this.index,
    this.revealIfOpened = true,
  });

  /// Consistency id: with [kind], the identity opening twice focuses instead of adding to.
  final String contentId;
  final String title;
  final String kind;

  /// Target pane; defaults to the active docked pane.
  final PaneId? paneId;

  /// Strip slot in the target pane; defaults to its end.
  final int? index;

  /// Whether a tab already showing this (kind, contentId) is focused instead of
  /// a second one being opened.
  final bool revealIfOpened;
}

/// An intent that both acts and names the tab it settled on.
class PlannedTab {
  const PlannedTab(this.ops, this.tabId);

  final List<LayoutOp> ops;

  /// The tab the intent focused or created.
  final TabId tabId;
}

/// First tab in one pane carrying [contentId], in strip order.
TabId? findPaneContentTab(
  LayoutState state,
  PaneId paneId,
  String contentId, [
  String? kind,
]) {
  for (final tabId in getPane(state, paneId).tabs) {
    final tab = state.tabs[tabId];
    if (tab != null &&
        tab.contentId == contentId &&
        (kind == null || tab.kind == kind)) {
      return tabId;
    }
  }
  return null;
}

/// First tab carrying [contentId], searched docked panes first, in visual order.
TabId? findContentTab(LayoutState state, String contentId, [String? kind]) {
  for (final paneId in [...dockPaneIds(state), ...state.floats]) {
    final found = findPaneContentTab(state, paneId, contentId, kind);
    if (found != null) return found;
  }
  return null;
}

/// The pane a new tab lands in: the active pane when docked, else the first docked pane.
PaneId activeDockPaneId(LayoutState state) {
  final active = getPane(state, state.activePaneId);
  return active.host == PaneHost.dock ? active.paneId : firstDockPaneId(state);
}

/// Send a tab into a docked pane, choosing the operation its current host needs.
LayoutOp _tabInto(PaneNode source, TabId tabId, PaneId toPaneId, int index) =>
    source.host == PaneHost.float
    ? UnfloatOp(paneId: source.paneId, toPaneId: toPaneId, index: index)
    : MoveTabOp(tabId: tabId, toPaneId: toPaneId, index: index);

/// Expand or collapse the docked area (none when the value is already current).
List<LayoutOp> planSetExpanded(LayoutState state, bool expanded) =>
    state.expanded == expanded ? _nothing : [SetExpandedOp(expanded)];

/// Switch the presentation (none when the value is already current).
List<LayoutOp> planSetMode(LayoutState state, DockMode mode) =>
    state.mode == mode ? _nothing : [SetModeOp(mode)];

/// Split a pane to its right and seed the new pane. None when the pane budget
/// is spent.
List<LayoutOp> planSplitPane(
  LayoutState state,
  IdMinter mint, {
  PaneId? paneId,
  TabFactory? makePaneTab,
  int maxPanes = maxDockPanes,
}) {
  if (!canSplit(state, maxPanes)) return _nothing;
  final target = paneId ?? activeDockPaneId(state);
  if (getPane(state, target).host != PaneHost.dock) return _nothing;
  final newPaneId = mint.pane();
  final ops = <LayoutOp>[
    SplitOp(
      paneId: target,
      axis: SplitAxis.row,
      direction: SplitDirection.after,
      newPaneId: newPaneId,
      newSplitId: mint.split(),
    ),
  ];
  // Seeding is its own operation inside the same intent: the record keeps the
  // two apart, one step back undoes both.
  final seed = makePaneTab?.call(mint.tab());
  if (seed != null) ops.add(OpenTabOp(paneId: newPaneId, tab: seed, index: 0));
  return ops;
}

/// Seat the embedder's seeded tab at the end of a docked pane's strip.
List<LayoutOp> planAddTab(
  LayoutState state,
  IdMinter mint,
  PaneId paneId, [
  TabFactory? makeTab,
]) {
  if (makeTab == null) return _nothing;
  final pane = getPane(state, paneId);
  if (pane.host != PaneHost.dock) return _nothing;
  return [
    OpenTabOp(
      paneId: paneId,
      tab: makeTab(mint.tab()),
      index: pane.tabs.length,
    ),
  ];
}

/// Open content, or focus the tab already showing it.
PlannedTab planOpenContent(
  LayoutState state,
  IdMinter mint,
  OpenContentInput input,
) {
  final existing = input.revealIfOpened
      ? findContentTab(state, input.contentId, input.kind)
      : null;
  if (existing != null) return PlannedTab([FocusTabOp(existing)], existing);
  final paneId = input.paneId ?? activeDockPaneId(state);
  final tab = TabRecord(
    id: mint.tab(),
    kind: input.kind,
    contentId: input.contentId,
    title: input.title,
  );
  return PlannedTab([
    OpenTabOp(
      paneId: paneId,
      tab: tab,
      index: input.index ?? getPane(state, paneId).tabs.length,
    ),
  ], tab.id);
}

/// Open a second, independent tab on the same content, beside the original.
PlannedTab planDuplicateTab(LayoutState state, IdMinter mint, TabId tabId) {
  final source = getTab(state, tabId);
  final pane = findTabPane(state, tabId);
  final host = pane.host == PaneHost.dock
      ? pane.paneId
      : activeDockPaneId(state);
  final index = pane.host == PaneHost.dock
      ? pane.tabs.indexOf(tabId) + 1
      : getPane(state, host).tabs.length;
  final tab = source.withId(mint.tab());
  return PlannedTab([OpenTabOp(paneId: host, tab: tab, index: index)], tab.id);
}

/// Put a tab at an explicit strip slot: a reorder inside its own pane,
/// otherwise a move, or a return when it currently floats. [index] is the caret
/// slot over the destination strip's chips as drawn, the dragged chip included
/// when the destination is its own pane.
List<LayoutOp> planPlaceTab(
  LayoutState state,
  TabId tabId,
  PaneId toPaneId,
  int index,
) {
  final source = findTabPane(state, tabId);
  if (getPane(state, toPaneId).host != PaneHost.dock) return _nothing;
  if (source.id == toPaneId) {
    // `reorderTab` indexes the strip without the tab: a caret past the chip
    // counts one slot the chip itself vacates.
    final from = source.tabs.indexOf(tabId);
    final to = index > from ? index - 1 : index;
    return to == from ? _nothing : [ReorderTabOp(tabId: tabId, index: to)];
  }
  return [_tabInto(source, tabId, toPaneId, index)];
}

/// Resolve a tab release on a pane body: the centre moves the tab in, an edge
/// splits the pane and seats the tab in the new half. A pane's only tab released
/// on that pane's centre changes nothing; released on its edge it splits, and
/// the factory's tab backfills the pane the drag would otherwise empty (without
/// a factory that release also changes nothing).
List<LayoutOp> planDropTab(
  LayoutState state,
  IdMinter mint,
  TabId tabId,
  PaneId targetPaneId,
  DockZone zone, [
  TabFactory? makeTab,
  int maxPanes = maxDockPanes,
]) {
  final source = findTabPane(state, tabId);
  final target = getPane(state, targetPaneId);
  if (target.host != PaneHost.dock) return _nothing;
  final split = zoneSplit(zone);

  if (split == null) {
    if (source.id == targetPaneId) return _nothing;
    return [_tabInto(source, tabId, targetPaneId, target.tabs.length)];
  }

  final vacates = source.id == targetPaneId && source.tabs.length == 1;
  if (vacates && makeTab == null) return _nothing;
  if (!canSplit(state, maxPanes)) return _nothing;
  final newPaneId = mint.pane();
  final ops = <LayoutOp>[
    SplitOp(
      paneId: targetPaneId,
      axis: split.axis,
      direction: split.direction,
      newPaneId: newPaneId,
      newSplitId: mint.split(),
    ),
  ];
  // The backfill seats before the move so the moved tab ends focused, as any
  // other drop leaves it.
  if (vacates && makeTab != null) {
    ops.add(
      OpenTabOp(
        paneId: targetPaneId,
        tab: makeTab(mint.tab()),
        index: source.tabs.length,
      ),
    );
  }
  ops.add(_tabInto(source, tabId, newPaneId, 0));
  return ops;
}

/// Take a tab out into a floating panel. [rect] defaults to a cascade from the
/// last panel.
({List<LayoutOp> ops, PaneId paneId}) planFloatTab(
  LayoutState state,
  IdMinter mint,
  TabId tabId, [
  FloatRect? rect,
]) {
  final step = state.floats.length * _floatCascadeStep;
  final newPaneId = mint.float();
  return (
    ops: [
      FloatOp(
        tabId: tabId,
        newPaneId: newPaneId,
        rect:
            rect ??
            FloatRect(
              _floatOriginX + step,
              _floatOriginY + step,
              floatDefaultWidth,
              floatDefaultHeight,
            ),
      ),
    ],
    paneId: newPaneId,
  );
}

/// Send a floating panel's tab back into the docked tree ([toPaneId] defaults
/// to the active docked pane).
List<LayoutOp> planUnfloatPane(
  LayoutState state,
  PaneId paneId, [
  PaneId? toPaneId,
]) {
  final destination = toPaneId ?? activeDockPaneId(state);
  return [
    UnfloatOp(
      paneId: paneId,
      toPaneId: destination,
      index: getPane(state, destination).tabs.length,
    ),
  ];
}

/// Record the net sizes of a divider drag, clamped to the pane minimum.
List<LayoutOp> planResizeSplit(
  SplitId splitId,
  List<double> sizes, [
  double? minimum,
]) => [
  ResizeOp(
    splitId: splitId,
    sizes: clampSizes(sizes, minimum ?? minPaneFraction),
  ),
];

/// Keep the docked area populated after an intent: drop every docked pane the
/// intent left empty, and when the surviving root pane is itself empty, seed it.
/// The returned operations continue the intent they follow.
List<LayoutOp> planSettle(
  LayoutState state,
  IdMinter mint, [
  TabFactory? makeTab,
]) {
  final ops = <LayoutOp>[];
  var current = state;
  for (;;) {
    PaneId? emptied;
    for (final id in dockPaneIds(current)) {
      if (id != current.rootId && getPane(current, id).tabs.isEmpty) {
        emptied = id;
        break;
      }
    }
    if (emptied == null) break;
    final merge = MergeOp(emptied);
    ops.add(merge);
    current = applyOp(current, merge).state;
  }
  final root = getNode(current, current.rootId);
  if (root is PaneNode && root.tabs.isEmpty && makeTab != null) {
    ops.add(OpenTabOp(paneId: root.paneId, tab: makeTab(mint.tab()), index: 0));
  }
  return ops;
}
