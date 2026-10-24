// Model and operation-engine behaviour (dsh `apply.client.spec.ts`): what each
// operation does to the tree, and that applying its inverse returns the exact
// state it started from.
import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class Fixture {
  Fixture(this.state, this.minter, this.paneId, this.guideTabId);

  final LayoutState state;
  final IdMinter minter;
  final PaneId paneId;
  final TabId guideTabId;
}

Fixture fixture() {
  final minter = IdMinter();
  final state = createInitialState(minter, seedTab);
  final pane = getPane(state, state.rootId);
  return Fixture(state, minter, pane.paneId, pane.tabs.first);
}

/// Apply [op], then its inverse, and require the original state back.
LayoutState expectRoundTrip(LayoutState state, LayoutOp op) {
  final result = applyOp(state, op);
  final back = result.inverse.fold(
    result.state,
    (current, inverse) => applyOp(current, inverse).state,
  );
  expect(back, equals(state));
  return result.state;
}

({LayoutState state, PaneId newPaneId}) split(
  LayoutState state,
  IdMinter minter,
  PaneId paneId, [
  SplitAxis axis = SplitAxis.row,
  SplitDirection direction = SplitDirection.after,
]) {
  final newPaneId = minter.pane();
  final op = SplitOp(
    paneId: paneId,
    axis: axis,
    direction: direction,
    newPaneId: newPaneId,
    newSplitId: minter.split(),
  );
  return (state: expectRoundTrip(state, op), newPaneId: newPaneId);
}

const rect100 = FloatRect(0, 0, 100, 100);

void main() {
  group('initial state', () {
    test(
      'starts collapsed with one docked pane holding an active seeded tab',
      () {
        final f = fixture();
        expect(f.state.expanded, isFalse);
        expect(dockPaneIds(f.state), [f.paneId]);
        expect(f.state.floats, isEmpty);
        expect(f.state.activePaneId, f.paneId);
        final pane = getPane(f.state, f.paneId);
        expect(pane.tabs, [f.guideTabId]);
        expect(pane.activeTabId, f.guideTabId);
        expect(f.state.tabs[f.guideTabId]?.kind, 'seed');
      },
    );
  });

  group('split', () {
    test(
      'wraps the reference pane in a new split and adds an empty sibling',
      () {
        final f = fixture();
        final after = split(f.state, f.minter, f.paneId).state;
        final root = getSplit(after, after.rootId);
        expect(root.axis, SplitAxis.row);
        expect(root.children, hasLength(2));
        expect(root.children[0], f.paneId);
        expect(root.sizes, [0.5, 0.5]);
        expect(dockPaneIds(after), hasLength(2));
        final sibling = getPane(after, root.children[1]);
        expect(sibling.tabs, isEmpty);
        expect(sibling.activeTabId, isNull);
      },
    );

    test('puts the new pane before the reference pane when asked', () {
      final f = fixture();
      final after = split(
        f.state,
        f.minter,
        f.paneId,
        SplitAxis.row,
        SplitDirection.before,
      ).state;
      expect(getSplit(after, after.rootId).children[1], f.paneId);
    });

    test('joins an existing split of the same axis instead of nesting', () {
      final f = fixture();
      final first = split(f.state, f.minter, f.paneId);
      final second = split(first.state, f.minter, f.paneId);
      final root = getSplit(second.state, second.state.rootId);
      expect(root.children, hasLength(3));
      expect(root.sizes, [0.25, 0.25, 0.5]);
      expect(dockPaneIds(second.state), hasLength(3));
    });

    test('joins an existing split before the reference pane when asked', () {
      final f = fixture();
      final first = split(f.state, f.minter, f.paneId);
      final second = split(
        first.state,
        f.minter,
        f.paneId,
        SplitAxis.row,
        SplitDirection.before,
      );
      final root = getSplit(second.state, second.state.rootId);
      expect(root.children, [second.newPaneId, f.paneId, first.newPaneId]);
      expect(root.sizes, [0.25, 0.25, 0.5]);
    });

    test('nests when the parent split runs on the other axis', () {
      final f = fixture();
      final first = split(f.state, f.minter, f.paneId);
      final second = split(
        first.state,
        f.minter,
        first.newPaneId,
        SplitAxis.column,
      );
      final root = getSplit(second.state, second.state.rootId);
      expect(root.axis, SplitAxis.row);
      expect(root.children, hasLength(2));
      final nested = getSplit(second.state, root.children[1]);
      expect(nested.axis, SplitAxis.column);
      expect(nested.children, [first.newPaneId, second.newPaneId]);
    });

    test('refuses an unknown pane and a floating pane', () {
      final f = fixture();
      expect(
        () => applyOp(
          f.state,
          SplitOp(
            paneId: const PaneId('nope'),
            axis: SplitAxis.row,
            direction: SplitDirection.after,
            newPaneId: const PaneId('p'),
            newSplitId: const SplitId('s'),
          ),
        ),
        throwsLayout('unknown node'),
      );
      final floatId = f.minter.float();
      final floated = applyOp(
        f.state,
        FloatOp(tabId: f.guideTabId, newPaneId: floatId, rect: rect100),
      ).state;
      expect(
        () => applyOp(
          floated,
          SplitOp(
            paneId: floatId,
            axis: SplitAxis.row,
            direction: SplitDirection.after,
            newPaneId: const PaneId('p'),
            newSplitId: const SplitId('s'),
          ),
        ),
        throwsLayout('docked pane'),
      );
    });
  });

  group('merge', () {
    test('collapses a two-child split back into its surviving pane', () {
      final f = fixture();
      final after = split(f.state, f.minter, f.paneId);
      final merged = expectRoundTrip(after.state, MergeOp(after.newPaneId));
      expect(merged.rootId, f.paneId);
      expect(dockPaneIds(merged), [f.paneId]);
      expect(merged.nodes[after.newPaneId], isNull);
    });

    test('drops one child of a wider split and renormalizes the rest', () {
      final f = fixture();
      final first = split(f.state, f.minter, f.paneId);
      final second = split(first.state, f.minter, f.paneId);
      final merged = expectRoundTrip(second.state, MergeOp(second.newPaneId));
      final root = getSplit(merged, merged.rootId);
      expect(root.children, hasLength(2));
      expect(root.sizes.reduce((a, b) => a + b), closeTo(1, 1e-9));
    });

    test('refuses a non-empty pane and the docked root pane', () {
      final f = fixture();
      expect(
        () => applyOp(f.state, MergeOp(f.paneId)),
        throwsLayout('empty pane'),
      );
      final after = split(f.state, f.minter, f.paneId);
      expect(
        () => applyOp(after.state, MergeOp(PaneId('${after.newPaneId}x'))),
        throwsLayout('unknown node'),
      );
      final emptied = applyOp(
        after.state,
        CloseTabOp(getPane(after.state, f.paneId).tabs.first),
      ).state;
      final collapsed = applyOp(emptied, MergeOp(f.paneId)).state;
      expect(
        () => applyOp(collapsed, MergeOp(after.newPaneId)),
        throwsLayout('root pane'),
      );
    });

    test('reseats focus when the merged pane held it', () {
      final f = fixture();
      final after = split(f.state, f.minter, f.paneId);
      final focused = applyOp(after.state, FocusPaneOp(after.newPaneId)).state;
      expect(focused.activePaneId, after.newPaneId);
      final merged = expectRoundTrip(focused, MergeOp(after.newPaneId));
      expect(merged.activePaneId, f.paneId);
    });
  });

  group('tabs', () {
    test('opens a tab into a pane and focuses it', () {
      final f = fixture();
      final tab = fileTab(f.minter.tab(), fileA, 'a.txt');
      final after = expectRoundTrip(
        f.state,
        OpenTabOp(paneId: f.paneId, tab: tab, index: 0),
      );
      final pane = getPane(after, f.paneId);
      expect(pane.tabs, [tab.id, f.guideTabId]);
      expect(pane.activeTabId, tab.id);
      expect(after.activePaneId, f.paneId);
    });

    test('refuses to reopen a live tab id', () {
      final f = fixture();
      final clash = TabRecord(
        id: f.guideTabId,
        kind: 'guide',
        contentId: 'x',
        title: 'x',
      );
      expect(
        () =>
            applyOp(f.state, OpenTabOp(paneId: f.paneId, tab: clash, index: 0)),
        throwsLayout('already exists'),
      );
    });

    test('closes the active tab onto its previous neighbour', () {
      final f = fixture();
      final first = fileTab(f.minter.tab(), fileA, 'a.txt');
      final second = fileTab(f.minter.tab(), fileB, 'b.txt');
      var current = applyOp(
        f.state,
        OpenTabOp(paneId: f.paneId, tab: first, index: 1),
      ).state;
      current = applyOp(
        current,
        OpenTabOp(paneId: f.paneId, tab: second, index: 2),
      ).state;
      expect(getPane(current, f.paneId).tabs, [
        f.guideTabId,
        first.id,
        second.id,
      ]);
      final after = expectRoundTrip(current, CloseTabOp(second.id));
      final pane = getPane(after, f.paneId);
      expect(pane.tabs, [f.guideTabId, first.id]);
      expect(pane.activeTabId, first.id);
      expect(after.tabs[second.id], isNull);
    });

    test('closes a tab that is not the active one without moving focus', () {
      final f = fixture();
      final tab = fileTab(f.minter.tab(), fileA, 'a.txt');
      final opened = applyOp(
        f.state,
        OpenTabOp(paneId: f.paneId, tab: tab, index: 1),
      ).state;
      final after = expectRoundTrip(opened, CloseTabOp(f.guideTabId));
      expect(getPane(after, f.paneId).tabs, [tab.id]);
      expect(getPane(after, f.paneId).activeTabId, tab.id);
    });

    test('leaves an empty pane with no active tab', () {
      final f = fixture();
      final after = expectRoundTrip(f.state, CloseTabOp(f.guideTabId));
      final pane = getPane(after, f.paneId);
      expect(pane.tabs, isEmpty);
      expect(pane.activeTabId, isNull);
    });

    test('moves a tab across panes and focuses the destination', () {
      final f = fixture();
      final after = split(f.state, f.minter, f.paneId);
      final moved = expectRoundTrip(
        after.state,
        MoveTabOp(tabId: f.guideTabId, toPaneId: after.newPaneId, index: 0),
      );
      expect(getPane(moved, f.paneId).tabs, isEmpty);
      expect(getPane(moved, after.newPaneId).tabs, [f.guideTabId]);
      expect(moved.activePaneId, after.newPaneId);
    });

    test(
      'moves a tab that is not the active one, leaving the source focus alone',
      () {
        final f = fixture();
        final tab = fileTab(f.minter.tab(), fileA, 'a.txt');
        final opened = applyOp(
          f.state,
          OpenTabOp(paneId: f.paneId, tab: tab, index: 1),
        ).state;
        final after = split(opened, f.minter, f.paneId);
        final moved = expectRoundTrip(
          after.state,
          MoveTabOp(tabId: f.guideTabId, toPaneId: after.newPaneId, index: 0),
        );
        expect(getPane(moved, f.paneId).tabs, [tab.id]);
        expect(getPane(moved, f.paneId).activeTabId, tab.id);
        expect(getPane(moved, after.newPaneId).activeTabId, f.guideTabId);
      },
    );

    test('refuses a cross-pane move onto the tab own pane', () {
      final f = fixture();
      expect(
        () => applyOp(
          f.state,
          MoveTabOp(tabId: f.guideTabId, toPaneId: f.paneId, index: 0),
        ),
        throwsLayout('reorderTab'),
      );
    });

    test('reorders inside one pane without changing the active tab', () {
      final f = fixture();
      final tab = fileTab(f.minter.tab(), fileA, 'a.txt');
      final opened = applyOp(
        f.state,
        OpenTabOp(paneId: f.paneId, tab: tab, index: 1),
      ).state;
      final after = expectRoundTrip(
        opened,
        ReorderTabOp(tabId: tab.id, index: 0),
      );
      expect(getPane(after, f.paneId).tabs, [tab.id, f.guideTabId]);
      expect(getPane(after, f.paneId).activeTabId, tab.id);
    });
  });

  group('focus', () {
    test('focuses a tab and its pane', () {
      final f = fixture();
      final tab = fileTab(f.minter.tab(), fileA, 'a.txt');
      final opened = applyOp(
        f.state,
        OpenTabOp(paneId: f.paneId, tab: tab, index: 1),
      ).state;
      final after = expectRoundTrip(opened, FocusTabOp(f.guideTabId));
      expect(getPane(after, f.paneId).activeTabId, f.guideTabId);
    });

    (LayoutState, PaneId, PaneId, Fixture, TabRecord) twoFloats() {
      final f = fixture();
      final tab = fileTab(f.minter.tab(), fileA, 'a.txt');
      var current = applyOp(
        f.state,
        OpenTabOp(paneId: f.paneId, tab: tab, index: 1),
      ).state;
      final firstFloat = f.minter.float();
      final secondFloat = f.minter.float();
      current = applyOp(
        current,
        FloatOp(tabId: f.guideTabId, newPaneId: firstFloat, rect: rect100),
      ).state;
      current = applyOp(
        current,
        FloatOp(
          tabId: tab.id,
          newPaneId: secondFloat,
          rect: const FloatRect(10, 10, 100, 100),
        ),
      ).state;
      return (current, firstFloat, secondFloat, f, tab);
    }

    test('raises a floating pane when its tab takes focus', () {
      final (current, firstFloat, secondFloat, f, _) = twoFloats();
      final after = expectRoundTrip(current, FocusTabOp(f.guideTabId));
      expect(after.floats, [secondFloat, firstFloat]);
      expect(after.activePaneId, firstFloat);
    });

    test('raises a floating pane when it takes focus', () {
      final (current, firstFloat, secondFloat, _, _) = twoFloats();
      expect(current.floats, [firstFloat, secondFloat]);
      final after = expectRoundTrip(current, FocusPaneOp(firstFloat));
      expect(after.floats, [secondFloat, firstFloat]);
      expect(after.activePaneId, firstFloat);
    });
  });

  group('resize', () {
    test('replaces divider sizes', () {
      final f = fixture();
      final after = split(f.state, f.minter, f.paneId);
      final resized = expectRoundTrip(
        after.state,
        ResizeOp(
          splitId: getSplit(after.state, after.state.rootId).splitId,
          sizes: const [0.3, 0.7],
        ),
      );
      expect(getSplit(resized, resized.rootId).sizes, [0.3, 0.7]);
    });

    test('rejects the wrong count and non-positive sizes', () {
      final f = fixture();
      final after = split(f.state, f.minter, f.paneId);
      final splitId = getSplit(after.state, after.state.rootId).splitId;
      expect(
        () =>
            applyOp(after.state, ResizeOp(splitId: splitId, sizes: const [1])),
        throwsLayout('do not match'),
      );
      expect(
        () => applyOp(
          after.state,
          ResizeOp(splitId: splitId, sizes: const [0, 1]),
        ),
        throwsLayout('above zero'),
      );
    });
  });

  group('floating panes', () {
    test('takes a tab out of the docked tree onto the top of the z order', () {
      final f = fixture();
      final floatId = f.minter.float();
      const rect = FloatRect(40, 50, 300, 200);
      final after = expectRoundTrip(
        f.state,
        FloatOp(tabId: f.guideTabId, newPaneId: floatId, rect: rect),
      );
      expect(getPane(after, f.paneId).tabs, isEmpty);
      expect(after.floats, [floatId]);
      expect(after.activePaneId, floatId);
      final pane = getPane(after, floatId);
      expect(pane.host, PaneHost.float);
      expect(pane.tabs, [f.guideTabId]);
      expect(pane.rect, rect);
      expect(findParent(after, floatId), isNull);
    });

    test(
      'returns a floating tab to a docked pane and drops the floating pane',
      () {
        final f = fixture();
        final floatId = f.minter.float();
        final floated = applyOp(
          f.state,
          FloatOp(tabId: f.guideTabId, newPaneId: floatId, rect: rect100),
        ).state;
        final docked = expectRoundTrip(
          floated,
          UnfloatOp(paneId: floatId, toPaneId: f.paneId, index: 0),
        );
        expect(docked.floats, isEmpty);
        expect(docked.nodes[floatId], isNull);
        expect(getPane(docked, f.paneId).tabs, [f.guideTabId]);
        expect(docked.activePaneId, f.paneId);
      },
    );

    test('destroys the floating pane together with its only tab', () {
      final f = fixture();
      final floatId = f.minter.float();
      final floated = applyOp(
        f.state,
        FloatOp(tabId: f.guideTabId, newPaneId: floatId, rect: rect100),
      ).state;
      final closed = expectRoundTrip(floated, CloseTabOp(f.guideTabId));
      expect(closed.floats, isEmpty);
      expect(closed.nodes[floatId], isNull);
      expect(closed.tabs[f.guideTabId], isNull);
      expect(closed.activePaneId, f.paneId);
    });

    test('records net drag and resize results, focusing and raising the pane they reshape', () {
      final f = fixture();
      final tab = fileTab(f.minter.tab(), fileA, 'a.txt');
      final floatId = f.minter.float();
      final topId = f.minter.float();
      var current = applyOp(
        f.state,
        OpenTabOp(paneId: f.paneId, tab: tab, index: 1),
      ).state;
      current = applyOp(
        current,
        FloatOp(tabId: f.guideTabId, newPaneId: floatId, rect: rect100),
      ).state;
      current = applyOp(
        current,
        FloatOp(
          tabId: tab.id,
          newPaneId: topId,
          rect: const FloatRect(10, 10, 100, 100),
        ),
      ).state;
      current = applyOp(current, FocusPaneOp(f.paneId)).state;
      expect(current.floats, [floatId, topId]);
      expect(current.activePaneId, f.paneId);

      // The lower, unfocused panel is dragged: it ends on top and focused; undo
      // puts both facts back.
      final moved = expectRoundTrip(
        current,
        MoveFloatOp(paneId: floatId, x: 25, y: 35),
      );
      expect(getPane(moved, floatId).rect, const FloatRect(25, 35, 100, 100));
      expect(moved.floats, [topId, floatId]);
      expect(moved.activePaneId, floatId);

      final lowered = applyOp(moved, FocusPaneOp(topId)).state;
      final resized = expectRoundTrip(
        lowered,
        ResizeFloatOp(paneId: floatId, rect: const FloatRect(25, 35, 420, 260)),
      );
      expect(getPane(resized, floatId).rect, const FloatRect(25, 35, 420, 260));
      expect(resized.floats, [topId, floatId]);
      expect(resized.activePaneId, floatId);
      expect(
        () => applyOp(
          moved,
          ResizeFloatOp(paneId: floatId, rect: const FloatRect(0, 0, 0, 10)),
        ),
        throwsLayout('above zero'),
      );
    });

    test('refuses to float a tab that already floats', () {
      final f = fixture();
      final floatId = f.minter.float();
      final floated = applyOp(
        f.state,
        FloatOp(tabId: f.guideTabId, newPaneId: floatId, rect: rect100),
      ).state;
      expect(
        () => applyOp(
          floated,
          FloatOp(
            tabId: f.guideTabId,
            newPaneId: f.minter.float(),
            rect: const FloatRect(0, 0, 10, 10),
          ),
        ),
        throwsLayout('docked tab'),
      );
    });
  });

  group('presentation flags', () {
    test('round-trips the collapsed flag', () {
      final f = fixture();
      final after = expectRoundTrip(f.state, const SetExpandedOp(true));
      expect(after.expanded, isTrue);
    });

    test('round-trips the presentation mode', () {
      final f = fixture();
      expect(f.state.mode, DockMode.push);
      final after = expectRoundTrip(
        f.state,
        const SetModeOp(DockMode.fullscreen),
      );
      expect(after.mode, DockMode.fullscreen);
      // The two flags are independent: switching one leaves the other alone.
      expect(after.expanded, f.state.expanded);
    });

    test('starts in the presentation the embedder seeded', () {
      expect(
        createInitialState(IdMinter(), seedTab, DockMode.fullscreen).mode,
        DockMode.fullscreen,
      );
    });
  });

  group('tree readers', () {
    ({LayoutState state, PaneId paneId, PaneId floatId, TabId guideTabId})
    floated() {
      final f = fixture();
      final floatId = f.minter.float();
      final next = applyOp(
        f.state,
        FloatOp(tabId: f.guideTabId, newPaneId: floatId, rect: rect100),
      ).state;
      return (
        state: next,
        paneId: f.paneId,
        floatId: floatId,
        guideTabId: f.guideTabId,
      );
    }

    test('throw on a dangling id or a node of the other kind', () {
      final f = fixture();
      final after = split(f.state, f.minter, f.paneId).state;
      expect(() => getNode(after, 'nope'), throwsLayout('unknown node nope'));
      expect(() => getPane(after, after.rootId), throwsLayout('is not a pane'));
      expect(() => getSplit(after, f.paneId), throwsLayout('is not a split'));
      expect(
        () => getTab(after, const TabId('nope')),
        throwsLayout('unknown tab nope'),
      );
      expect(
        () => findTabPane(after, const TabId('nope')),
        throwsLayout('has no pane'),
      );
      expect(
        () => replaceInParent(after, 'nope', f.paneId),
        throwsLayout('neither rooted nor parented'),
      );
    });

    test("read a floating pane's rectangle, z position, and only tab, and refuse a docked one", () {
      final f = floated();
      final pane = getPane(f.state, f.floatId);
      expect(floatRectOf(pane), rect100);
      expect(floatIndex(f.state, f.floatId), 0);
      expect(onlyTabId(pane), f.guideTabId);
      final docked = getPane(f.state, f.paneId);
      expect(() => floatRectOf(docked), throwsLayout('is not floating'));
      expect(
        () => floatIndex(f.state, f.paneId),
        throwsLayout('not in the z order'),
      );
      expect(() => onlyTabId(docked), throwsLayout('exactly one tab'));
      final two = pane.withTabs([
        f.guideTabId,
        const TabId('other'),
      ], f.guideTabId);
      expect(() => onlyTabId(two), throwsLayout('exactly one tab'));
    });

    test('name the first and the top-right docked pane however the tree is divided', () {
      final f = fixture();
      expect(firstDockPaneId(f.state), f.paneId);
      expect(topRightPaneId(f.state), f.paneId);
      final right = split(f.state, f.minter, f.paneId);
      final below = split(
        right.state,
        f.minter,
        right.newPaneId,
        SplitAxis.column,
      );
      expect(firstDockPaneId(below.state), f.paneId);
      expect(topRightPaneId(below.state), right.newPaneId);
      final above = split(
        below.state,
        f.minter,
        f.paneId,
        SplitAxis.column,
        SplitDirection.before,
      );
      expect(firstDockPaneId(above.state), above.newPaneId);
    });

    test(
      'normalize sizes without drifting an exact sum, and refuse a zero total',
      () {
        final exact = [0.25, 0.75];
        expect(normalizeSizes(exact), exact);
        expect(identical(normalizeSizes(exact), exact), isFalse);
        expect(normalizeSizes([1, 3]), [0.25, 0.75]);
        expect(() => normalizeSizes([0, 0]), throwsLayout('sum above zero'));
      },
    );
  });

  group('operations refuse', () {
    ({
      LayoutState state,
      IdMinter minter,
      PaneId paneId,
      PaneId secondPaneId,
      PaneId floatId,
      TabId guideTabId,
      TabId floatTabId,
    })
    mixed() {
      final f = fixture();
      final second = split(f.state, f.minter, f.paneId);
      final tab = fileTab(f.minter.tab(), fileA, 'a.txt');
      final opened = applyOp(
        second.state,
        OpenTabOp(paneId: f.paneId, tab: tab, index: 1),
      ).state;
      final floatId = f.minter.float();
      final floated = applyOp(
        opened,
        FloatOp(tabId: tab.id, newPaneId: floatId, rect: rect100),
      ).state;
      return (
        state: floated,
        minter: f.minter,
        paneId: f.paneId,
        secondPaneId: second.newPaneId,
        floatId: floatId,
        guideTabId: f.guideTabId,
        floatTabId: tab.id,
      );
    }

    test('opening or inserting a tab into a floating pane', () {
      final m = mixed();
      final tab = fileTab(m.minter.tab(), fileB, 'b.txt');
      expect(
        () =>
            applyOp(m.state, OpenTabOp(paneId: m.floatId, tab: tab, index: 0)),
        throwsLayout('docked pane'),
      );
      expect(
        () => applyOp(
          m.state,
          InsertTabOp(paneId: m.floatId, tab: tab, index: 0),
        ),
        throwsLayout('docked pane'),
      );
    });

    test('moving a tab out of or into a floating pane, which is what unfloat and float are for', () {
      final m = mixed();
      expect(
        () => applyOp(
          m.state,
          MoveTabOp(tabId: m.floatTabId, toPaneId: m.paneId, index: 0),
        ),
        throwsLayout('use unfloat'),
      );
      expect(
        () => applyOp(
          m.state,
          MoveTabOp(tabId: m.guideTabId, toPaneId: m.floatId, index: 0),
        ),
        throwsLayout('target must be docked'),
      );
    });

    test('returning a floating tab anywhere but a docked pane, and treating a docked pane as floating', () {
      final m = mixed();
      final otherFloat = m.minter.float();
      final twoFloats = applyOp(
        m.state,
        FloatOp(
          tabId: m.guideTabId,
          newPaneId: otherFloat,
          rect: const FloatRect(5, 5, 100, 100),
        ),
      ).state;
      expect(
        () => applyOp(
          twoFloats,
          UnfloatOp(paneId: m.floatId, toPaneId: otherFloat, index: 0),
        ),
        throwsLayout('target must be docked'),
      );
      expect(
        () => applyOp(
          m.state,
          UnfloatOp(paneId: m.paneId, toPaneId: m.paneId, index: 0),
        ),
        throwsLayout('is not floating'),
      );
      expect(
        () => applyOp(m.state, MoveFloatOp(paneId: m.paneId, x: 1, y: 1)),
        throwsLayout('is not floating'),
      );
      expect(
        () => applyOp(
          m.state,
          ResizeFloatOp(paneId: m.paneId, rect: const FloatRect(0, 0, 10, 10)),
        ),
        throwsLayout('is not floating'),
      );
    });

    test('creating a node under an id that is already taken', () {
      final m = mixed();
      expect(
        () => applyOp(
          m.state,
          SplitOp(
            paneId: m.paneId,
            axis: SplitAxis.column,
            direction: SplitDirection.after,
            newPaneId: m.secondPaneId,
            newSplitId: m.minter.split(),
          ),
        ),
        throwsLayout('already exists'),
      );
      expect(
        () => applyOp(
          m.state,
          SplitOp(
            paneId: m.paneId,
            axis: SplitAxis.column,
            direction: SplitDirection.after,
            newPaneId: m.minter.pane(),
            newSplitId: SplitId(m.state.rootId),
          ),
        ),
        throwsLayout('already exists'),
      );
    });

    test('putting a pane back with records that do not match the pane or the split', () {
      final m = mixed();
      final pane = getPane(m.state, m.secondPaneId);
      final stray = fileTab(m.minter.tab(), fileC, 'c.txt');
      final fresh = PaneNode.emptyDock(m.minter.pane());
      final parent = getSplit(m.state, m.state.rootId);
      ChildAttachment child() => ChildAttachment(
        parentId: parent.splitId,
        index: 1,
        sizes: parent.sizes,
      );
      expect(
        () => applyOp(
          m.state,
          InsertPaneOp(pane: pane, tabs: const [], attach: child()),
        ),
        throwsLayout('already exists'),
      );
      expect(
        () => applyOp(
          m.state,
          InsertPaneOp(pane: fresh, tabs: [stray], attach: child()),
        ),
        throwsLayout('do not match the pane'),
      );
      expect(
        () => applyOp(
          m.state,
          InsertPaneOp(pane: fresh, tabs: const [], attach: child()),
        ),
        throwsLayout('sizes do not match the split'),
      );
      expect(
        () => applyOp(
          m.state,
          InsertPaneOp(
            pane: fresh,
            tabs: const [],
            attach: WrapAttachment(targetId: m.paneId, split: parent),
          ),
        ),
        throwsLayout('does not list the pane'),
      );
      expect(
        () => applyOp(
          m.state,
          InsertPaneOp(
            pane: fresh,
            tabs: const [],
            attach: const FloatAttachment(0),
          ),
        ),
        throwsLayout('requires a floating pane'),
      );
    });

    test('restoring focus facts that name a docked pane as floating or an unknown pane', () {
      final m = mixed();
      expect(
        () => applyOp(
          m.state,
          RestoreFocusOp(
            activePaneId: m.paneId,
            floats: [m.paneId],
            paneActiveTabs: const {},
          ),
        ),
        throwsLayout('as floating'),
      );
      expect(
        () => applyOp(
          m.state,
          RestoreFocusOp(
            activePaneId: m.paneId,
            floats: const [],
            paneActiveTabs: {const PaneId('nope'): null},
          ),
        ),
        throwsLayout('unknown node'),
      );
    });
  });

  group('inverses the engine itself never records', () {
    test('refuse to return a docked pane with tab records: closeTab records those through insertTab', () {
      final f = fixture();
      final after = split(f.state, f.minter, f.paneId);
      final parent = getSplit(after.state, after.state.rootId);
      final tab = fileTab(f.minter.tab(), fileA, 'a.txt');
      final pane = PaneNode(
        paneId: f.minter.pane(),
        host: PaneHost.dock,
        tabs: [tab.id],
        activeTabId: tab.id,
        rect: null,
      );
      expect(
        () => applyOp(
          after.state,
          InsertPaneOp(
            pane: pane,
            tabs: [tab],
            attach: ChildAttachment(
              parentId: parent.splitId,
              index: 2,
              sizes: const [0.25, 0.25, 0.5],
            ),
          ),
        ),
        throwsLayout('returns a docked pane empty'),
      );
    });

    test(
      'merge away an empty floating pane and restore it at its z position',
      () {
        final f = fixture();
        final pane = PaneNode(
          paneId: f.minter.float(),
          host: PaneHost.float,
          tabs: const [],
          activeTabId: null,
          rect: const FloatRect(1, 2, 50, 40),
        );
        final inserted = expectRoundTrip(
          f.state,
          InsertPaneOp(
            pane: pane,
            tabs: const [],
            attach: const FloatAttachment(0),
          ),
        );
        expect(inserted.floats, [pane.paneId]);
        final merged = expectRoundTrip(inserted, MergeOp(pane.paneId));
        expect(merged.floats, isEmpty);
        expect(merged.nodes[pane.id], isNull);
      },
    );
  });

  group('replay', () {
    test('rebuilds the same tree from the recorded operations', () {
      final f = fixture();
      final preview = fileTab(f.minter.tab(), fileA, 'a.txt');
      final secondPaneId = f.minter.pane();
      final floatId = f.minter.float();
      final ops = <LayoutOp>[
        const SetExpandedOp(true),
        OpenTabOp(paneId: f.paneId, tab: preview, index: 1),
        SplitOp(
          paneId: f.paneId,
          axis: SplitAxis.row,
          direction: SplitDirection.after,
          newPaneId: secondPaneId,
          newSplitId: f.minter.split(),
        ),
        MoveTabOp(tabId: preview.id, toPaneId: secondPaneId, index: 0),
        FocusTabOp(f.guideTabId),
        FloatOp(
          tabId: preview.id,
          newPaneId: floatId,
          rect: const FloatRect(10, 20, 200, 150),
        ),
        MoveFloatOp(paneId: floatId, x: 60, y: 70),
      ];
      final direct = ops.fold(
        f.state,
        (current, op) => applyOp(current, op).state,
      );
      expect(replay(f.state, ops), equals(direct));
      expect(replay(f.state, ops), equals(replay(f.state, ops)));
      expect(findTabPane(direct, preview.id).paneId, floatId);
    });
  });
}
