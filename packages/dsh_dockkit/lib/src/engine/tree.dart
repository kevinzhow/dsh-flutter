/// Pure tree helpers over [LayoutState] (dsh `engine/tree.ts`). Every reader
/// throws on a dangling id (the operation vocabulary is closed, so a miss is a
/// caller defect), and every writer returns a new state that keeps untouched
/// nodes at their old identity.
library;

import 'types.dart';

/// Thrown by the layout engine on an invalid operation or a dangling id.
class DockLayoutError extends Error {
  DockLayoutError(this.message);

  final String message;

  @override
  String toString() => 'layout: $message';
}

/// Read any node.
LayoutNode getNode(LayoutState state, String id) {
  final node = state.nodes[id];
  if (node == null) throw DockLayoutError('unknown node $id');
  return node;
}

/// Read a pane. Throws when [id] is missing or names a split.
PaneNode getPane(LayoutState state, String id) {
  final node = getNode(state, id);
  if (node is! PaneNode) throw DockLayoutError('$id is not a pane');
  return node;
}

/// Read a split. Throws when [id] is missing or names a pane.
SplitNode getSplit(LayoutState state, String id) {
  final node = getNode(state, id);
  if (node is! SplitNode) throw DockLayoutError('$id is not a split');
  return node;
}

/// Read a tab record. Throws when [id] is not open.
TabRecord getTab(LayoutState state, TabId id) {
  final tab = state.tabs[id];
  if (tab == null) throw DockLayoutError('unknown tab $id');
  return tab;
}

/// A floating pane's rectangle. Throws when [pane] is docked.
FloatRect floatRectOf(PaneNode pane) {
  final rect = pane.rect;
  if (pane.host != PaneHost.float || rect == null) {
    throw DockLayoutError('${pane.id} is not floating');
  }
  return rect;
}

/// A floating pane's position in the z order (bottom first).
int floatIndex(LayoutState state, PaneId id) {
  final index = state.floats.indexOf(id);
  if (index < 0) {
    throw DockLayoutError('floating pane $id is not in the z order');
  }
  return index;
}

/// The one tab a pane holds. Throws when it holds any other number of tabs.
TabId onlyTabId(PaneNode pane) {
  if (pane.tabs.length != 1) {
    throw DockLayoutError('${pane.id} does not hold exactly one tab');
  }
  return pane.tabs.first;
}

/// The split holding a node, or null for the docked root and floating panes.
SplitNode? findParent(LayoutState state, String id) {
  for (final node in state.nodes.values) {
    if (node is SplitNode && node.children.contains(id)) return node;
  }
  return null;
}

/// The pane whose strip lists [tabId]. Throws when no pane lists it.
PaneNode findTabPane(LayoutState state, TabId tabId) {
  for (final node in state.nodes.values) {
    if (node is PaneNode && node.tabs.contains(tabId)) return node;
  }
  throw DockLayoutError('tab $tabId has no pane');
}

/// Docked pane ids in visual order (depth first through the split tree).
List<PaneId> dockPaneIds(LayoutState state) {
  final out = <PaneId>[];
  void walk(String id) {
    final node = getNode(state, id);
    switch (node) {
      case PaneNode():
        out.add(node.paneId);
      case SplitNode():
        node.children.forEach(walk);
    }
  }

  walk(state.rootId);
  return out;
}

/// Scale [sizes] so they sum to 1. Input that already sums to 1 is copied
/// unchanged, so restoring recorded sizes never drifts.
List<double> normalizeSizes(List<double> sizes) {
  final total = sizes.fold<double>(0, (sum, size) => sum + size);
  if (!(total > 0)) throw DockLayoutError('sizes must sum above zero');
  if ((total - 1).abs() < 1e-12) return [...sizes];
  return [for (final size in sizes) size / total];
}

/// Replace or delete nodes: a null update deletes that id. Untouched nodes keep
/// their identity.
LayoutState withNodes(LayoutState state, Map<String, LayoutNode?> updates) {
  final nodes = <String, LayoutNode>{};
  for (final entry in state.nodes.entries) {
    if (!updates.containsKey(entry.key)) nodes[entry.key] = entry.value;
  }
  for (final entry in updates.entries) {
    final node = entry.value;
    if (node != null) nodes[entry.key] = node;
  }
  return state.copyWith(nodes: nodes);
}

/// Replace or delete tab records: a null update deletes that id.
LayoutState withTabs(LayoutState state, Map<String, TabRecord?> updates) {
  final tabs = <String, TabRecord>{};
  for (final entry in state.tabs.entries) {
    if (!updates.containsKey(entry.key)) tabs[entry.key] = entry.value;
  }
  for (final entry in updates.entries) {
    final tab = entry.value;
    if (tab != null) tabs[entry.key] = tab;
  }
  return state.copyWith(tabs: tabs);
}

/// Insert a value into a list; the slot is clamped to the list's bounds.
List<T> insertAt<T>(List<T> items, int index, T value) {
  final at = index.clamp(0, items.length);
  return [...items.sublist(0, at), value, ...items.sublist(at)];
}

/// Remove one entry from a list.
List<T> removeAt<T>(List<T> items, int index) => [
  ...items.sublist(0, index),
  ...items.sublist(index + 1),
];

/// Which tab a pane focuses after one leaves it: the previous neighbour when
/// one exists, otherwise the next, otherwise null.
TabId? neighbourTabId(List<TabId> tabs, int removedIndex) {
  final remaining = removeAt(tabs, removedIndex);
  if (remaining.isEmpty) return null;
  return remaining[(removedIndex - 1) < 0 ? 0 : removedIndex - 1];
}

/// Swap a node for another in its parent's slot, or make the replacement the
/// docked root.
LayoutState replaceInParent(
  LayoutState state,
  String targetId,
  String replacementId,
) {
  final parent = findParent(state, targetId);
  if (parent == null) {
    if (state.rootId != targetId) {
      throw DockLayoutError('$targetId is neither rooted nor parented');
    }
    return state.copyWith(rootId: replacementId);
  }
  final children = [
    for (final child in parent.children)
      child == targetId ? replacementId : child,
  ];
  return withNodes(state, {parent.id: parent.copyWith(children: children)});
}

PaneId _descend(LayoutState state, String? Function(SplitNode split) choose) {
  var node = getNode(state, state.rootId);
  while (node is SplitNode) {
    final next = choose(node);
    if (next == null) throw DockLayoutError('split ${node.id} has no children');
    node = getNode(state, next);
  }
  return (node as PaneNode).paneId;
}

/// The first docked pane in visual order: the docked root, or the first leaf
/// under it. Focus falls back here when the focused pane is removed.
PaneId firstDockPaneId(LayoutState state) =>
    _descend(state, (split) => split.children.first);

/// The docked pane in the top-right corner: from the root, the last child of
/// every row split and the first child of every column split. Its tab strip is
/// where an embedder's surface-wide controls sit.
PaneId topRightPaneId(LayoutState state) => _descend(
  state,
  (split) =>
      split.axis == SplitAxis.row ? split.children.last : split.children.first,
);
