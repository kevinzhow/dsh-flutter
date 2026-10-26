/// Initial state and the identity mint every operation draws its new ids from
/// (dsh `engine/initial.ts`). Ids are minted outside `applyOp` so a recorded
/// sequence replays to the exact same tree.
library;

import 'types.dart';

/// Monotonic id source; one instance belongs to one surface's sequence. The
/// counter is shared across kinds, as in dsh: `pane1`, `tab2`, `split3`, ...
class IdMinter {
  IdMinter([int seed = 0]) : _counter = seed;

  int _counter;

  int get minted => _counter;

  String _next(String prefix) {
    _counter += 1;
    return '$prefix$_counter';
  }

  PaneId pane() => PaneId(_next('pane'));
  PaneId float() => PaneId(_next('float'));
  SplitId split() => SplitId(_next('split'));
  TabId tab() => TabId(_next('tab'));
}

/// Builds the tab record a newly seeded pane should hold.
typedef TabFactory = TabRecord Function(TabId id);

/// The state a surface starts in: collapsed, one docked pane, and whatever tab
/// [makeInitialTab] supplies. The first tab belongs to the initial state rather
/// than to an operation, so expanding and collapsing never accumulates copies.
LayoutState createInitialState(
  IdMinter minter, [
  TabFactory? makeInitialTab,
  DockMode mode = DockMode.push,
]) {
  final paneId = minter.pane();
  final initial = makeInitialTab?.call(minter.tab());
  return LayoutState(
    nodes: {
      paneId: PaneNode(
        paneId: paneId,
        host: PaneHost.dock,
        tabs: initial == null ? const [] : [initial.id],
        activeTabId: initial?.id,
        rect: null,
      ),
    },
    tabs: initial == null ? const {} : {initial.id: initial},
    rootId: paneId,
    floats: const [],
    activePaneId: paneId,
    expanded: false,
    mode: mode,
  );
}
