/// The intent layer's stateful embedding (dsh `engine/controller.ts`): one
/// controller per docking surface, Flutter-free, and itself the observable the
/// UI listens to (`addListener`, with a [DockSnapshot] whose reference only
/// changes when the layout does).
///
/// Every method is a planner call plus recording plus one notification. A
/// planner that returns no operations records nothing and notifies nobody.
library;

import 'constraints.dart';
import 'initial.dart';
import 'planner.dart';
import 'planner.dart' as planner show activeDockPaneId;
import 'sequence.dart';
import 'types.dart';

export 'planner.dart' show OpenContentInput;

/// Everything the rendering layer reads, in one immutable value.
class DockSnapshot {
  const DockSnapshot({
    required this.state,
    required this.canUndo,
    required this.canRedo,
    required this.canSplit,
    required this.opCount,
    required this.cursor,
  });

  final LayoutState state;
  final bool canUndo;
  final bool canRedo;

  /// Whether the docked grid still has room for another pane.
  final bool canSplit;

  /// Recorded operation count, redo branch included.
  final int opCount;

  /// How many recorded intents are applied.
  final int cursor;
}

/// What the embedder seeds new panes with.
class DockControllerOptions {
  const DockControllerOptions({
    this.makeInitialTab,
    this.makePaneTab,
    this.mode = DockMode.push,
    this.maxPanes = maxDockPanes,
  });

  /// Builds the tab the starting pane holds; omit to start empty.
  final TabFactory? makeInitialTab;

  /// Builds the tab a pane created by `splitPane` holds; omit to leave it empty.
  final TabFactory? makePaneTab;

  /// Starting presentation.
  final DockMode mode;

  /// How many docked panes the surface allows (dsh's embedder store enforces
  /// its own limit; the right sidebar allows two).
  final int maxPanes;
}

/// The net gesture results a rendering layer reports. [DockController]
/// satisfies it as written; an embedder that routes through its own store
/// implements the same names. Each call is one settled intent, never a drag
/// frame.
abstract interface class DockIntents {
  void focusTab(TabId tabId);
  void focusPane(PaneId paneId);
  bool splitPane([PaneId? paneId]);
  bool addTab(PaneId paneId);
  void closeTab(TabId tabId);
  TabId duplicateTab(TabId tabId);
  PaneId floatTab(TabId tabId, [FloatRect? rect]);
  void unfloatPane(PaneId paneId, [PaneId? toPaneId]);
  bool placeTab(TabId tabId, PaneId toPaneId, int index);
  bool dropTab(TabId tabId, PaneId targetPaneId, DockZone zone);
  void moveFloat(PaneId paneId, double x, double y);
  void resizeFloat(PaneId paneId, FloatRect rect);
  void resizeSplit(SplitId splitId, List<double> sizes);
}

/// One docking surface: history, interaction limits, and change notification.
class DockController implements DockIntents {
  DockController([
    DockControllerOptions options = const DockControllerOptions(),
  ]) : _makePaneTab = options.makePaneTab,
       _maxPanes = options.maxPanes {
    _sequencer = Sequencer(
      createInitialState(_minter, options.makeInitialTab, options.mode),
    );
    _snapshot = _buildSnapshot();
  }

  final IdMinter _minter = IdMinter();
  late final Sequencer _sequencer;
  final Set<void Function()> _listeners = {};
  final TabFactory? _makePaneTab;
  final int _maxPanes;
  late DockSnapshot _snapshot;

  /// Observe layout changes; returns the disposer.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Current snapshot; the same reference until the layout changes.
  DockSnapshot get snapshot => _snapshot;

  /// Recorded sequence, for tests and an operation readout.
  List<LayoutOp> get ops => _sequencer.ops;

  DockSnapshot _buildSnapshot() {
    final state = _sequencer.state;
    return DockSnapshot(
      state: state,
      canUndo: _sequencer.canUndo,
      canRedo: _sequencer.canRedo,
      canSplit: canSplit(state, _maxPanes),
      opCount: _sequencer.ops.length,
      cursor: _sequencer.cursor,
    );
  }

  void _commit() {
    _snapshot = _buildSnapshot();
    for (final listener in [..._listeners]) {
      listener();
    }
  }

  LayoutState get _state => _sequencer.state;

  /// Record a planned intent as one history entry; false when it planned nothing.
  bool _run(List<LayoutOp> ops) {
    if (ops.isEmpty) return false;
    _sequencer.dispatchAll(ops);
    _commit();
    return true;
  }

  /// Expand or collapse the docked area. Floating panels are unaffected.
  void setExpanded(bool expanded) => _run(planSetExpanded(_state, expanded));

  /// Flip the docked area between expanded and collapsed.
  void toggleExpanded() => setExpanded(!_state.expanded);

  /// Switch how the docked area is presented.
  void setMode(DockMode mode) => _run(planSetMode(_state, mode));

  /// Split a pane to its right and seat the embedder's pane tab in the new
  /// pane. False when the docked grid is already at [maxDockPanes].
  @override
  bool splitPane([PaneId? paneId]) => _run(
    planSplitPane(
      _state,
      _minter,
      paneId: paneId,
      makePaneTab: _makePaneTab,
      maxPanes: _maxPanes,
    ),
  );

  /// Seat the pane-tab factory's tab at the end of a pane's strip. False when
  /// there is no factory or the pane is not docked.
  @override
  bool addTab(PaneId paneId) =>
      _run(planAddTab(_state, _minter, paneId, _makePaneTab));

  /// Open content, or focus the tab already showing it.
  TabId openContent(OpenContentInput input) {
    final planned = planOpenContent(_state, _minter, input);
    _run(planned.ops);
    return planned.tabId;
  }

  /// Open a second, independent tab on the same content.
  @override
  TabId duplicateTab(TabId tabId) {
    final planned = planDuplicateTab(_state, _minter, tabId);
    _run(planned.ops);
    return planned.tabId;
  }

  /// Destroy a tab and its content state. A floating host panel goes with it.
  @override
  void closeTab(TabId tabId) => _run([CloseTabOp(tabId)]);

  /// Focus a tab, its pane, and raise that pane when it floats.
  @override
  void focusTab(TabId tabId) => _run([FocusTabOp(tabId)]);

  /// Focus a pane, raising it when it floats.
  @override
  void focusPane(PaneId paneId) => _run([FocusPaneOp(paneId)]);

  /// Move a tab inside its own pane ([index] counts the strip without it).
  void reorderTab(TabId tabId, int index) =>
      _run([ReorderTabOp(tabId: tabId, index: index)]);

  /// Put a tab at an explicit slot. False when the placement changes nothing.
  @override
  bool placeTab(TabId tabId, PaneId toPaneId, int index) =>
      _run(planPlaceTab(_state, tabId, toPaneId, index));

  /// Resolve a tab drop inside the docked area. False when the drop changes
  /// nothing or the grid is full.
  @override
  bool dropTab(TabId tabId, PaneId targetPaneId, DockZone zone) => _run(
    planDropTab(_state, _minter, tabId, targetPaneId, zone, null, _maxPanes),
  );

  /// Take a tab out into a floating panel.
  @override
  PaneId floatTab(TabId tabId, [FloatRect? rect]) {
    final planned = planFloatTab(_state, _minter, tabId, rect);
    _run(planned.ops);
    return planned.paneId;
  }

  /// Send a floating panel's tab back into the docked tree.
  @override
  void unfloatPane(PaneId paneId, [PaneId? toPaneId]) =>
      _run(planUnfloatPane(_state, paneId, toPaneId));

  /// Record the net position of a floating-panel drag.
  @override
  void moveFloat(PaneId paneId, double x, double y) =>
      _run([MoveFloatOp(paneId: paneId, x: x, y: y)]);

  /// Record the net rectangle of a floating-panel resize.
  @override
  void resizeFloat(PaneId paneId, FloatRect rect) =>
      _run([ResizeFloatOp(paneId: paneId, rect: rect)]);

  /// Record the net sizes of a divider drag, clamped to the pane minimum.
  @override
  void resizeSplit(SplitId splitId, List<double> sizes) =>
      _run(planResizeSplit(splitId, sizes));

  /// Keep the docked area populated after an intent (dsh's embedder calls the
  /// settle planner after the intents that can empty a pane): merge away every
  /// docked pane that is empty and, when [reseed] is true, seed an emptied root
  /// pane with the pane-tab factory. False when nothing needed doing.
  bool settle({bool reseed = true}) =>
      _run(planSettle(_state, _minter, reseed ? _makePaneTab : null));

  /// Step back one intent, or one run of consecutive focus-only intents.
  bool undo() {
    if (!_sequencer.undo()) return false;
    _commit();
    return true;
  }

  /// Step forward over what the matching undo stepped back.
  bool redo() {
    if (!_sequencer.redo()) return false;
    _commit();
    return true;
  }

  /// The pane a new tab lands in: the active pane when docked, else the first
  /// docked pane.
  PaneId activeDockPaneId() => planner.activeDockPaneId(_state);
}
