/// Layout model and operation vocabulary of dsh's `ui-dockkit`
/// (`contract/types.ts`): no Flutter, no host concepts. A tab's `kind` is an
/// opaque string this kit never interprets.
///
/// The model is a normalized recursive split tree. `nodes` holds every split
/// and pane keyed by id; `rootId` names the docked root; `floats` lists
/// floating panes bottom to top. A floating panel is a pane whose `host` is
/// [PaneHost.float], capacity one tab, drawn without a tab strip.
///
/// Ids are distinct types (dsh brands them): a pane, a split and a tab id never
/// stand in for one another, and only an [IdMinter] (or an id the kit wrote
/// itself) produces one. Each is a `String` at run time, so a node id is a plain
/// `String` map key.
library;

/// Identity of a pane node in [LayoutState.nodes].
extension type const PaneId(String value) implements String {}

/// Identity of a split node in [LayoutState.nodes].
extension type const SplitId(String value) implements String {}

/// Identity of one open tab; distinct copies of one content share `contentId`,
/// never the [TabId].
extension type const TabId(String value) implements String {}

/// Direction a split lays its children out in.
enum SplitAxis { row, column }

/// Which side of the reference pane a new pane takes.
enum SplitDirection { before, after }

/// The five drop regions a pane offers a dragged tab.
enum DockZone { center, top, right, bottom, left }

/// How the docked area is presented: `push` takes room from its neighbours,
/// `fullscreen` covers the viewport. The kit records the choice; the embedder
/// positions the surface.
enum DockMode { push, fullscreen }

/// Where a pane is drawn: inside the docked split tree, or as a viewport overlay.
enum PaneHost { dock, float }

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? value) {
  if (value is List) return Object.hashAll(value.map(_deepHash));
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map((e) => Object.hash(e.key, _deepHash(e.value))),
    );
  }
  return value.hashCode;
}

/// Value equality over a list of fields (lists and maps compare deeply).
abstract class DockValue {
  const DockValue();

  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      _deepEquals((other as DockValue).props, props);

  @override
  int get hashCode => Object.hash(runtimeType, _deepHash(props));

  @override
  String toString() => '$runtimeType($props)';
}

/// Viewport rectangle of a floating pane, in logical pixels.
class FloatRect extends DockValue {
  const FloatRect(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  FloatRect copyWith({double? x, double? y, double? width, double? height}) =>
      FloatRect(
        x ?? this.x,
        y ?? this.y,
        width ?? this.width,
        height ?? this.height,
      );

  @override
  List<Object?> get props => [x, y, width, height];
}

/// Either kind of tree node.
sealed class LayoutNode extends DockValue {
  const LayoutNode();

  /// Node id as the map key (`PaneId` or `SplitId`).
  String get id;
}

/// Interior node: an ordered run of children along one axis with fractional
/// sizes.
class SplitNode extends LayoutNode {
  const SplitNode({
    required this.splitId,
    required this.axis,
    required this.children,
    required this.sizes,
  });

  final SplitId splitId;
  final SplitAxis axis;

  /// At least two children; a one-child split collapses into that child.
  final List<String> children;

  /// Same length as [children], each above zero, summing to 1.
  final List<double> sizes;

  @override
  String get id => splitId;

  SplitNode copyWith({List<String>? children, List<double>? sizes}) =>
      SplitNode(
        splitId: splitId,
        axis: axis,
        children: children ?? this.children,
        sizes: sizes ?? this.sizes,
      );

  @override
  List<Object?> get props => [splitId, axis, children, sizes];
}

/// Leaf node: an ordered tab list with at most one active tab.
class PaneNode extends LayoutNode {
  const PaneNode({
    required this.paneId,
    required this.host,
    required this.tabs,
    required this.activeTabId,
    required this.rect,
  });

  /// A fresh empty docked pane.
  const PaneNode.emptyDock(this.paneId)
    : host = PaneHost.dock,
      tabs = const [],
      activeTabId = null,
      rect = null;

  final PaneId paneId;
  final PaneHost host;
  final List<TabId> tabs;

  /// `null` exactly when [tabs] is empty.
  final TabId? activeTabId;

  /// Set exactly when [host] is [PaneHost.float].
  final FloatRect? rect;

  @override
  String get id => paneId;

  PaneNode withTabs(List<TabId> tabs, TabId? activeTabId) => PaneNode(
    paneId: paneId,
    host: host,
    tabs: tabs,
    activeTabId: activeTabId,
    rect: rect,
  );

  PaneNode withRect(FloatRect rect) => PaneNode(
    paneId: paneId,
    host: host,
    tabs: tabs,
    activeTabId: activeTabId,
    rect: rect,
  );

  PaneNode withActive(TabId? activeTabId) => PaneNode(
    paneId: paneId,
    host: host,
    tabs: tabs,
    activeTabId: activeTabId,
    rect: rect,
  );

  @override
  List<Object?> get props => [paneId, host, tabs, activeTabId, rect];
}

/// One open tab. `kind` selects the embedder's content family; `contentId` is
/// the identity `openContent` de-duplicates against, so two tabs sharing it are
/// deliberate copies of one thing.
class TabRecord extends DockValue {
  const TabRecord({
    required this.id,
    required this.kind,
    required this.contentId,
    required this.title,
  });

  final TabId id;
  final String kind;
  final String contentId;
  final String title;

  TabRecord withId(TabId id) =>
      TabRecord(id: id, kind: kind, contentId: contentId, title: title);

  @override
  List<Object?> get props => [id, kind, contentId, title];
}

/// The whole layout of one docking surface. Every field is replaced rather
/// than mutated, and untouched sub-objects keep their identity so consumers can
/// compare by reference.
class LayoutState extends DockValue {
  const LayoutState({
    required this.nodes,
    required this.tabs,
    required this.rootId,
    required this.floats,
    required this.activePaneId,
    required this.expanded,
    required this.mode,
  });

  final Map<String, LayoutNode> nodes;
  final Map<String, TabRecord> tabs;

  /// Root of the docked tree; always a split or pane that exists in [nodes].
  final String rootId;

  /// Floating panes, bottom to top; the last entry is on top.
  final List<PaneId> floats;

  /// Focused pane, docked or floating.
  final PaneId activePaneId;

  /// Whether the docked area is expanded; floating panes ignore it.
  final bool expanded;

  /// How the docked area is presented; floating panes ignore it.
  final DockMode mode;

  LayoutState copyWith({
    Map<String, LayoutNode>? nodes,
    Map<String, TabRecord>? tabs,
    String? rootId,
    List<PaneId>? floats,
    PaneId? activePaneId,
    bool? expanded,
    DockMode? mode,
  }) => LayoutState(
    nodes: nodes ?? this.nodes,
    tabs: tabs ?? this.tabs,
    rootId: rootId ?? this.rootId,
    floats: floats ?? this.floats,
    activePaneId: activePaneId ?? this.activePaneId,
    expanded: expanded ?? this.expanded,
    mode: mode ?? this.mode,
  );

  @override
  List<Object?> get props => [
    nodes,
    tabs,
    rootId,
    floats,
    activePaneId,
    expanded,
    mode,
  ];
}

/// Recipe for putting a pane back where it was, used by [InsertPaneOp].
sealed class PaneAttachment extends DockValue {
  const PaneAttachment();
}

/// Re-insert as a child of an existing split, restoring that split's sizes verbatim.
class ChildAttachment extends PaneAttachment {
  const ChildAttachment({
    required this.parentId,
    required this.index,
    required this.sizes,
  });

  final SplitId parentId;
  final int index;
  final List<double> sizes;

  @override
  List<Object?> get props => [parentId, index, sizes];
}

/// Re-create a collapsed split in [targetId]'s slot; [split] already lists both children.
class WrapAttachment extends PaneAttachment {
  const WrapAttachment({required this.targetId, required this.split});

  final String targetId;
  final SplitNode split;

  @override
  List<Object?> get props => [targetId, split];
}

/// Re-insert a floating pane at its former z index.
class FloatAttachment extends PaneAttachment {
  const FloatAttachment(this.index);

  final int index;

  @override
  List<Object?> get props => [index];
}

/// One recorded layout mutation. Ids that an operation creates are carried in
/// the operation itself, so replaying a sequence from the same initial state
/// reproduces the same ids without any minting during apply.
///
/// [InsertPaneOp], [InsertTabOp] and [RestoreFocusOp] exist to express inverses
/// exactly; they are applied like any other operation.
sealed class LayoutOp extends DockValue {
  const LayoutOp();
}

/// Give [paneId] a new empty sibling pane along [axis].
class SplitOp extends LayoutOp {
  const SplitOp({
    required this.paneId,
    required this.axis,
    required this.direction,
    required this.newPaneId,
    required this.newSplitId,
  });

  final PaneId paneId;
  final SplitAxis axis;
  final SplitDirection direction;
  final PaneId newPaneId;

  /// Used only when the reference pane's parent cannot host [axis] directly.
  final SplitId newSplitId;

  @override
  List<Object?> get props => [paneId, axis, direction, newPaneId, newSplitId];
}

/// Drop an empty docked pane and collapse the split it leaves behind.
class MergeOp extends LayoutOp {
  const MergeOp(this.paneId);

  final PaneId paneId;

  @override
  List<Object?> get props => [paneId];
}

/// Add a new tab to a docked pane and focus it.
class OpenTabOp extends LayoutOp {
  const OpenTabOp({
    required this.paneId,
    required this.tab,
    required this.index,
  });

  final PaneId paneId;
  final TabRecord tab;
  final int index;

  @override
  List<Object?> get props => [paneId, tab, index];
}

/// Destroy a tab and its content state; a floating host pane goes with it.
class CloseTabOp extends LayoutOp {
  const CloseTabOp(this.tabId);

  final TabId tabId;

  @override
  List<Object?> get props => [tabId];
}

/// Move a tab to a different docked pane.
class MoveTabOp extends LayoutOp {
  const MoveTabOp({
    required this.tabId,
    required this.toPaneId,
    required this.index,
  });

  final TabId tabId;
  final PaneId toPaneId;
  final int index;

  @override
  List<Object?> get props => [tabId, toPaneId, index];
}

/// Move a tab within its own pane.
class ReorderTabOp extends LayoutOp {
  const ReorderTabOp({required this.tabId, required this.index});

  final TabId tabId;
  final int index;

  @override
  List<Object?> get props => [tabId, index];
}

/// Focus a tab, its owning pane, and raise that pane when floating.
class FocusTabOp extends LayoutOp {
  const FocusTabOp(this.tabId);

  final TabId tabId;

  @override
  List<Object?> get props => [tabId];
}

/// Focus a pane and raise it when floating.
class FocusPaneOp extends LayoutOp {
  const FocusPaneOp(this.paneId);

  final PaneId paneId;

  @override
  List<Object?> get props => [paneId];
}

/// Net result of a divider drag.
class ResizeOp extends LayoutOp {
  const ResizeOp({required this.splitId, required this.sizes});

  final SplitId splitId;
  final List<double> sizes;

  @override
  List<Object?> get props => [splitId, sizes];
}

/// Take a tab out of the docked tree into a new floating pane.
class FloatOp extends LayoutOp {
  const FloatOp({
    required this.tabId,
    required this.newPaneId,
    required this.rect,
  });

  final TabId tabId;
  final PaneId newPaneId;
  final FloatRect rect;

  @override
  List<Object?> get props => [tabId, newPaneId, rect];
}

/// Return a floating pane's only tab to a docked pane and destroy the floating pane.
class UnfloatOp extends LayoutOp {
  const UnfloatOp({
    required this.paneId,
    required this.toPaneId,
    required this.index,
  });

  final PaneId paneId;
  final PaneId toPaneId;
  final int index;

  @override
  List<Object?> get props => [paneId, toPaneId, index];
}

/// Net result of dragging a floating pane; the pane is focused and raised with it.
class MoveFloatOp extends LayoutOp {
  const MoveFloatOp({required this.paneId, required this.x, required this.y});

  final PaneId paneId;
  final double x;
  final double y;

  @override
  List<Object?> get props => [paneId, x, y];
}

/// Net result of resizing a floating pane; the pane is focused and raised with it.
class ResizeFloatOp extends LayoutOp {
  const ResizeFloatOp({required this.paneId, required this.rect});

  final PaneId paneId;
  final FloatRect rect;

  @override
  List<Object?> get props => [paneId, rect];
}

/// Expand or collapse the docked area.
class SetExpandedOp extends LayoutOp {
  const SetExpandedOp(this.expanded);

  final bool expanded;

  @override
  List<Object?> get props => [expanded];
}

/// Switch how the docked area is presented.
class SetModeOp extends LayoutOp {
  const SetModeOp(this.mode);

  final DockMode mode;

  @override
  List<Object?> get props => [mode];
}

/// Put a pane back, with the tab records it owned.
class InsertPaneOp extends LayoutOp {
  const InsertPaneOp({
    required this.pane,
    required this.tabs,
    required this.attach,
  });

  final PaneNode pane;
  final List<TabRecord> tabs;
  final PaneAttachment attach;

  @override
  List<Object?> get props => [pane, tabs, attach];
}

/// Put one tab record back into a docked pane.
class InsertTabOp extends LayoutOp {
  const InsertTabOp({
    required this.paneId,
    required this.tab,
    required this.index,
  });

  final PaneId paneId;
  final TabRecord tab;
  final int index;

  @override
  List<Object?> get props => [paneId, tab, index];
}

/// Restore focus facts an operation displaced.
class RestoreFocusOp extends LayoutOp {
  const RestoreFocusOp({
    required this.activePaneId,
    required this.floats,
    required this.paneActiveTabs,
  });

  final PaneId activePaneId;
  final List<PaneId> floats;

  /// Active tab per pane, for the panes the inverted operation touched.
  final Map<PaneId, TabId?> paneActiveTabs;

  @override
  List<Object?> get props => [activePaneId, floats, paneActiveTabs];
}

/// Result of applying one operation: the next state plus the operations that
/// undo it, in order.
class ApplyResult {
  const ApplyResult(this.state, this.inverse);

  final LayoutState state;
  final List<LayoutOp> inverse;
}
