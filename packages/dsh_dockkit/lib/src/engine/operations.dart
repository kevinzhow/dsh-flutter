/// The operation engine (dsh `engine/operations.ts`): one pure [applyOp] that
/// returns the next state plus the operations that undo it. No Flutter, no
/// ambient state: replaying the same operations over the same initial state
/// always yields the same result, because every id an operation creates travels
/// inside the operation.
///
/// Interaction limits (pane count, drag preview coalescing) are not enforced
/// here; they belong to the interaction layer (`constraints.dart`, the widgets).
library;

import 'tree.dart';
import 'types.dart';

/// Capture the focus facts of [paneIds] plus global focus, as the operation
/// that restores them.
RestoreFocusOp _focusSnapshot(LayoutState state, List<PaneId> paneIds) {
  final paneActiveTabs = <PaneId, TabId?>{};
  for (final id in paneIds) {
    paneActiveTabs[id] = getPane(state, id).activeTabId;
  }
  return RestoreFocusOp(
    activePaneId: state.activePaneId,
    floats: state.floats,
    paneActiveTabs: paneActiveTabs,
  );
}

/// Move [paneId] to the top of the floating z order.
List<PaneId> _raise(List<PaneId> floats, PaneId paneId) => [
  ...floats.where((id) => id != paneId),
  paneId,
];

/// Keep `activePaneId` on a live pane after [state] lost the focused one.
LayoutState _reseatFocus(LayoutState state, PaneId removedPaneId) {
  if (state.activePaneId != removedPaneId) return state;
  return state.copyWith(activePaneId: firstDockPaneId(state));
}

void _assertFreeNode(LayoutState state, String id) {
  if (state.nodes[id] != null) throw DockLayoutError('node $id already exists');
}

void _assertFreeTab(LayoutState state, TabId id) {
  if (state.tabs[id] != null) throw DockLayoutError('tab $id already exists');
}

/// Give `paneId` an empty sibling along `axis`.
ApplyResult _applySplit(LayoutState state, SplitOp op) {
  final pane = getPane(state, op.paneId);
  if (pane.host != PaneHost.dock) {
    throw DockLayoutError('split requires a docked pane');
  }
  _assertFreeNode(state, op.newPaneId);
  final newPane = PaneNode.emptyDock(op.newPaneId);
  final parent = findParent(state, op.paneId);

  if (parent != null && parent.axis == op.axis) {
    final index = parent.children.indexOf(op.paneId);
    final at = op.direction == SplitDirection.after ? index + 1 : index;
    final children = insertAt<String>(parent.children, at, op.newPaneId);
    // The reference pane's share is halved between it and the new pane; the two
    // halves are equal, so the sizes align with `children` whichever side it took.
    final sizes = <double>[
      for (var i = 0; i < parent.sizes.length; i++)
        if (i == index) ...[
          parent.sizes[i] / 2,
          parent.sizes[i] / 2,
        ] else
          parent.sizes[i],
    ];
    return ApplyResult(
      withNodes(state, {
        op.newPaneId: newPane,
        parent.id: parent.copyWith(children: children, sizes: sizes),
      }),
      [
        MergeOp(op.newPaneId),
        ResizeOp(splitId: parent.splitId, sizes: parent.sizes),
      ],
    );
  }

  _assertFreeNode(state, op.newSplitId);
  // The reference pane's slot takes the new split; compute that swap before the
  // split node exists, or findParent would find the split itself.
  final rehomed = replaceInParent(state, op.paneId, op.newSplitId);
  final children = op.direction == SplitDirection.after
      ? <String>[op.paneId, op.newPaneId]
      : <String>[op.newPaneId, op.paneId];
  return ApplyResult(
    withNodes(rehomed, {
      op.newPaneId: newPane,
      op.newSplitId: SplitNode(
        splitId: op.newSplitId,
        axis: op.axis,
        children: children,
        sizes: const [0.5, 0.5],
      ),
    }),
    [MergeOp(op.newPaneId)],
  );
}

/// Drop an empty pane; a two-child split collapses into its surviving child.
ApplyResult _applyMerge(LayoutState state, MergeOp op) {
  final pane = getPane(state, op.paneId);
  if (pane.tabs.isNotEmpty) {
    throw DockLayoutError('merge requires an empty pane');
  }
  final focus = _focusSnapshot(state, const []);

  if (pane.host == PaneHost.float) {
    final index = floatIndex(state, op.paneId);
    final dropped = withNodes(
      state.copyWith(floats: removeAt(state.floats, index)),
      {op.paneId: null},
    );
    return ApplyResult(_reseatFocus(dropped, op.paneId), [
      InsertPaneOp(pane: pane, tabs: const [], attach: FloatAttachment(index)),
      focus,
    ]);
  }

  final parent = findParent(state, op.paneId);
  if (parent == null) {
    throw DockLayoutError('the docked root pane cannot be merged');
  }
  final index = parent.children.indexOf(op.paneId);

  if (parent.children.length > 2) {
    final children = removeAt(parent.children, index);
    final sizes = normalizeSizes(removeAt(parent.sizes, index));
    final dropped = withNodes(state, {
      op.paneId: null,
      parent.id: parent.copyWith(children: children, sizes: sizes),
    });
    return ApplyResult(_reseatFocus(dropped, op.paneId), [
      InsertPaneOp(
        pane: pane,
        tabs: const [],
        attach: ChildAttachment(
          parentId: parent.splitId,
          index: index,
          sizes: parent.sizes,
        ),
      ),
      focus,
    ]);
  }

  final siblingId = parent.children[1 - index];
  final collapsed = withNodes(replaceInParent(state, parent.id, siblingId), {
    op.paneId: null,
    parent.id: null,
  });
  return ApplyResult(_reseatFocus(collapsed, op.paneId), [
    InsertPaneOp(
      pane: pane,
      tabs: const [],
      attach: WrapAttachment(targetId: siblingId, split: parent),
    ),
    focus,
  ]);
}

/// Add a new tab to a docked pane and focus it.
ApplyResult _applyOpenTab(LayoutState state, OpenTabOp op) {
  final pane = getPane(state, op.paneId);
  if (pane.host != PaneHost.dock) {
    throw DockLayoutError('openTab requires a docked pane');
  }
  _assertFreeTab(state, op.tab.id);
  final focus = _focusSnapshot(state, [pane.paneId]);
  final seated = withNodes(withTabs(state, {op.tab.id: op.tab}), {
    pane.id: pane.withTabs(insertAt(pane.tabs, op.index, op.tab.id), op.tab.id),
  });
  return ApplyResult(seated.copyWith(activePaneId: pane.paneId), [
    CloseTabOp(op.tab.id),
    focus,
  ]);
}

/// Put one tab record back where it was, without stealing focus.
ApplyResult _applyInsertTab(LayoutState state, InsertTabOp op) {
  final pane = getPane(state, op.paneId);
  if (pane.host != PaneHost.dock) {
    throw DockLayoutError('insertTab requires a docked pane');
  }
  _assertFreeTab(state, op.tab.id);
  final focus = _focusSnapshot(state, [pane.paneId]);
  final tabs = insertAt(pane.tabs, op.index, op.tab.id);
  return ApplyResult(
    withNodes(withTabs(state, {op.tab.id: op.tab}), {
      pane.id: pane.withTabs(tabs, pane.activeTabId ?? op.tab.id),
    }),
    [CloseTabOp(op.tab.id), focus],
  );
}

/// Destroy a tab and its content state; a floating host pane goes with its only tab.
ApplyResult _applyCloseTab(LayoutState state, CloseTabOp op) {
  final tab = getTab(state, op.tabId);
  final pane = findTabPane(state, op.tabId);
  final index = pane.tabs.indexOf(op.tabId);
  final focus = _focusSnapshot(state, [pane.paneId]);

  if (pane.host == PaneHost.float) {
    final floatAt = floatIndex(state, pane.paneId);
    final dropped = withTabs(
      withNodes(state.copyWith(floats: removeAt(state.floats, floatAt)), {
        pane.id: null,
      }),
      {op.tabId: null},
    );
    return ApplyResult(_reseatFocus(dropped, pane.paneId), [
      InsertPaneOp(pane: pane, tabs: [tab], attach: FloatAttachment(floatAt)),
      focus,
    ]);
  }

  final activeTabId = pane.activeTabId == op.tabId
      ? neighbourTabId(pane.tabs, index)
      : pane.activeTabId;
  return ApplyResult(
    withTabs(
      withNodes(state, {
        pane.id: pane.withTabs(removeAt(pane.tabs, index), activeTabId),
      }),
      {op.tabId: null},
    ),
    [InsertTabOp(paneId: pane.paneId, tab: tab, index: index), focus],
  );
}

/// Put a pane back, with the tab records it owned. A docked pane returns empty
/// (its tabs return through `insertTab`, as `closeTab` records them); a floating
/// pane returns with its one tab, or empty.
ApplyResult _applyInsertPane(LayoutState state, InsertPaneOp op) {
  _assertFreeNode(state, op.pane.id);
  if (op.pane.tabs.length != op.tabs.length) {
    throw DockLayoutError('insertPane tab records do not match the pane');
  }
  if (op.pane.host == PaneHost.dock && op.tabs.isNotEmpty) {
    throw DockLayoutError('insertPane returns a docked pane empty');
  }
  final tabUpdates = <String, TabRecord?>{};
  for (final tab in op.tabs) {
    _assertFreeTab(state, tab.id);
    tabUpdates[tab.id] = tab;
  }
  final restoredTab = op.tabs.isEmpty ? null : op.tabs.first;
  final inverse = <LayoutOp>[
    if (restoredTab == null)
      MergeOp(op.pane.paneId)
    else ...[
      CloseTabOp(restoredTab.id),
      _focusSnapshot(state, const []),
    ],
  ];

  switch (op.attach) {
    case ChildAttachment attach:
      final parent = getSplit(state, attach.parentId);
      final children = insertAt<String>(
        parent.children,
        attach.index,
        op.pane.id,
      );
      if (attach.sizes.length != children.length) {
        throw DockLayoutError('insertPane sizes do not match the split');
      }
      inverse.add(ResizeOp(splitId: parent.splitId, sizes: parent.sizes));
      return ApplyResult(
        withNodes(withTabs(state, tabUpdates), {
          op.pane.id: op.pane,
          parent.id: parent.copyWith(children: children, sizes: attach.sizes),
        }),
        inverse,
      );
    case WrapAttachment attach:
      if (!attach.split.children.contains(op.pane.id)) {
        throw DockLayoutError('insertPane wrap split does not list the pane');
      }
      final rehomed = replaceInParent(state, attach.targetId, attach.split.id);
      return ApplyResult(
        withNodes(withTabs(rehomed, tabUpdates), {
          op.pane.id: op.pane,
          attach.split.id: attach.split,
        }),
        inverse,
      );
    case FloatAttachment attach:
      if (op.pane.host != PaneHost.float) {
        throw DockLayoutError('float attachment requires a floating pane');
      }
      final floats = insertAt<PaneId>(
        state.floats,
        attach.index,
        op.pane.paneId,
      );
      return ApplyResult(
        withNodes(withTabs(state.copyWith(floats: floats), tabUpdates), {
          op.pane.id: op.pane,
        }),
        inverse,
      );
  }
}

/// Move a tab to a different docked pane and focus it there.
ApplyResult _applyMoveTab(LayoutState state, MoveTabOp op) {
  final from = findTabPane(state, op.tabId);
  if (from.host != PaneHost.dock) {
    throw DockLayoutError('moveTab source must be docked; use unfloat');
  }
  final to = getPane(state, op.toPaneId);
  if (to.host != PaneHost.dock) {
    throw DockLayoutError('moveTab target must be docked');
  }
  if (to.id == from.id) {
    throw DockLayoutError('moveTab across one pane; use reorderTab');
  }
  final index = from.tabs.indexOf(op.tabId);
  final focus = _focusSnapshot(state, [from.paneId, to.paneId]);
  final activeTabId = from.activeTabId == op.tabId
      ? neighbourTabId(from.tabs, index)
      : from.activeTabId;
  final moved = withNodes(state, {
    from.id: from.withTabs(removeAt(from.tabs, index), activeTabId),
    to.id: to.withTabs(insertAt(to.tabs, op.index, op.tabId), op.tabId),
  });
  return ApplyResult(moved.copyWith(activePaneId: to.paneId), [
    MoveTabOp(tabId: op.tabId, toPaneId: from.paneId, index: index),
    focus,
  ]);
}

/// Move a tab within its own pane.
ApplyResult _applyReorderTab(LayoutState state, ReorderTabOp op) {
  final pane = findTabPane(state, op.tabId);
  final from = pane.tabs.indexOf(op.tabId);
  final tabs = insertAt(removeAt(pane.tabs, from), op.index, op.tabId);
  return ApplyResult(
    withNodes(state, {pane.id: pane.withTabs(tabs, pane.activeTabId)}),
    [ReorderTabOp(tabId: op.tabId, index: from)],
  );
}

/// Focus a tab, its pane, and raise that pane when floating.
ApplyResult _applyFocusTab(LayoutState state, FocusTabOp op) {
  final pane = findTabPane(state, op.tabId);
  final focus = _focusSnapshot(state, [pane.paneId]);
  final focused = withNodes(state, {pane.id: pane.withActive(op.tabId)});
  final floats = pane.host == PaneHost.float
      ? _raise(focused.floats, pane.paneId)
      : focused.floats;
  return ApplyResult(
    focused.copyWith(activePaneId: pane.paneId, floats: floats),
    [focus],
  );
}

/// Focus a pane and raise it when floating.
ApplyResult _applyFocusPane(LayoutState state, FocusPaneOp op) {
  final pane = getPane(state, op.paneId);
  final focus = _focusSnapshot(state, const []);
  final floats = pane.host == PaneHost.float
      ? _raise(state.floats, pane.paneId)
      : state.floats;
  return ApplyResult(
    state.copyWith(activePaneId: pane.paneId, floats: floats),
    [focus],
  );
}

/// Record the net result of a divider drag.
ApplyResult _applyResize(LayoutState state, ResizeOp op) {
  final split = getSplit(state, op.splitId);
  if (op.sizes.length != split.children.length) {
    throw DockLayoutError('resize sizes do not match the split');
  }
  if (op.sizes.any((size) => !(size > 0))) {
    throw DockLayoutError('resize sizes must all be above zero');
  }
  return ApplyResult(
    withNodes(state, {
      split.id: split.copyWith(sizes: normalizeSizes(op.sizes)),
    }),
    [ResizeOp(splitId: split.splitId, sizes: split.sizes)],
  );
}

/// Take a tab out of the docked tree into a new floating pane on top.
ApplyResult _applyFloat(LayoutState state, FloatOp op) {
  getTab(state, op.tabId);
  final from = findTabPane(state, op.tabId);
  if (from.host != PaneHost.dock) {
    throw DockLayoutError('float requires a docked tab');
  }
  _assertFreeNode(state, op.newPaneId);
  final index = from.tabs.indexOf(op.tabId);
  final focus = _focusSnapshot(state, [from.paneId]);
  final activeTabId = from.activeTabId == op.tabId
      ? neighbourTabId(from.tabs, index)
      : from.activeTabId;
  final floated = withNodes(state, {
    from.id: from.withTabs(removeAt(from.tabs, index), activeTabId),
    op.newPaneId: PaneNode(
      paneId: op.newPaneId,
      host: PaneHost.float,
      tabs: [op.tabId],
      activeTabId: op.tabId,
      rect: op.rect,
    ),
  });
  return ApplyResult(
    floated.copyWith(
      floats: [...floated.floats, op.newPaneId],
      activePaneId: op.newPaneId,
    ),
    [
      UnfloatOp(paneId: op.newPaneId, toPaneId: from.paneId, index: index),
      focus,
    ],
  );
}

/// Return a floating pane's only tab to a docked pane and destroy the floating pane.
ApplyResult _applyUnfloat(LayoutState state, UnfloatOp op) {
  final pane = getPane(state, op.paneId);
  final rect = floatRectOf(pane);
  final tabId = onlyTabId(pane);
  final to = getPane(state, op.toPaneId);
  if (to.host != PaneHost.dock) {
    throw DockLayoutError('unfloat target must be docked');
  }
  final focus = _focusSnapshot(state, [to.paneId]);
  final docked = withNodes(
    state.copyWith(
      floats: removeAt(state.floats, floatIndex(state, op.paneId)),
    ),
    {
      op.paneId: null,
      to.id: to.withTabs(insertAt(to.tabs, op.index, tabId), tabId),
    },
  );
  return ApplyResult(docked.copyWith(activePaneId: to.paneId), [
    FloatOp(tabId: tabId, newPaneId: op.paneId, rect: rect),
    focus,
  ]);
}

/// Give a floating pane a new rectangle, focus it, and raise it: the one
/// operation a drag of it records.
LayoutState _reshapeFloat(LayoutState state, PaneNode pane, FloatRect rect) {
  final reshaped = withNodes(state, {pane.id: pane.withRect(rect)});
  return reshaped.copyWith(
    activePaneId: pane.paneId,
    floats: _raise(reshaped.floats, pane.paneId),
  );
}

ApplyResult _applyMoveFloat(LayoutState state, MoveFloatOp op) {
  final pane = getPane(state, op.paneId);
  final rect = floatRectOf(pane);
  return ApplyResult(
    _reshapeFloat(state, pane, rect.copyWith(x: op.x, y: op.y)),
    [
      MoveFloatOp(paneId: op.paneId, x: rect.x, y: rect.y),
      _focusSnapshot(state, const []),
    ],
  );
}

ApplyResult _applyResizeFloat(LayoutState state, ResizeFloatOp op) {
  final pane = getPane(state, op.paneId);
  final rect = floatRectOf(pane);
  if (!(op.rect.width > 0) || !(op.rect.height > 0)) {
    throw DockLayoutError('float size must be above zero');
  }
  return ApplyResult(_reshapeFloat(state, pane, op.rect), [
    ResizeFloatOp(paneId: op.paneId, rect: rect),
    _focusSnapshot(state, const []),
  ]);
}

/// Restore focus facts a previous operation displaced.
ApplyResult _applyRestoreFocus(LayoutState state, RestoreFocusOp op) {
  final inverse = _focusSnapshot(state, op.paneActiveTabs.keys.toList());
  for (final paneId in op.floats) {
    final pane = getPane(state, paneId);
    if (pane.host != PaneHost.float) {
      throw DockLayoutError(
        'restoreFocus lists docked pane $paneId as floating',
      );
    }
  }
  var next = state;
  for (final entry in op.paneActiveTabs.entries) {
    final pane = getPane(next, entry.key);
    next = withNodes(next, {entry.key: pane.withActive(entry.value)});
  }
  getPane(next, op.activePaneId);
  return ApplyResult(
    next.copyWith(activePaneId: op.activePaneId, floats: op.floats),
    [inverse],
  );
}

/// Apply one operation. [state] is never mutated; the result carries the next
/// state and the operations that undo it, applied in order. Throws
/// [DockLayoutError] when the operation addresses missing nodes or breaks a
/// model rule.
ApplyResult applyOp(LayoutState state, LayoutOp op) => switch (op) {
  SplitOp() => _applySplit(state, op),
  MergeOp() => _applyMerge(state, op),
  OpenTabOp() => _applyOpenTab(state, op),
  InsertTabOp() => _applyInsertTab(state, op),
  CloseTabOp() => _applyCloseTab(state, op),
  InsertPaneOp() => _applyInsertPane(state, op),
  MoveTabOp() => _applyMoveTab(state, op),
  ReorderTabOp() => _applyReorderTab(state, op),
  FocusTabOp() => _applyFocusTab(state, op),
  FocusPaneOp() => _applyFocusPane(state, op),
  ResizeOp() => _applyResize(state, op),
  FloatOp() => _applyFloat(state, op),
  UnfloatOp() => _applyUnfloat(state, op),
  MoveFloatOp() => _applyMoveFloat(state, op),
  ResizeFloatOp() => _applyResizeFloat(state, op),
  SetExpandedOp() => ApplyResult(state.copyWith(expanded: op.expanded), [
    SetExpandedOp(state.expanded),
  ]),
  SetModeOp() => ApplyResult(state.copyWith(mode: op.mode), [
    SetModeOp(state.mode),
  ]),
  RestoreFocusOp() => _applyRestoreFocus(state, op),
};

/// Fold operations forward, discarding inverses.
LayoutState replay(LayoutState state, List<LayoutOp> ops) =>
    ops.fold(state, (current, op) => applyOp(current, op).state);
