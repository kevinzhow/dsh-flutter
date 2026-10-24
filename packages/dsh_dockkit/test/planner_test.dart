// The two properties the intent layer must not lose in refactoring (dsh
// `planner.client.spec.ts`): determinism, and one undo behaviour across both
// embeddings (the stateful `DockController` and the pure history functions).
import 'dart:convert';

import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// A deep snapshot, for proving a planner left its input alone.
String frozen(LayoutState state) => jsonEncode(_json(state));

Object? _json(Object? value) => switch (value) {
  LayoutState() => {
    'nodes': {for (final e in value.nodes.entries) e.key: _json(e.value)},
    'tabs': {for (final e in value.tabs.entries) e.key: _json(e.value)},
    'rootId': value.rootId,
    'floats': value.floats.map((e) => e.value).toList(),
    'active': value.activePaneId.value,
    'expanded': value.expanded,
    'mode': value.mode.name,
  },
  SplitNode() => {
    'split': value.id,
    'axis': value.axis.name,
    'children': value.children,
    'sizes': value.sizes,
  },
  PaneNode() => {
    'pane': value.id,
    'host': value.host.name,
    'tabs': value.tabs.map((e) => e.value).toList(),
    'active': value.activeTabId?.value,
    'rect': value.rect?.props,
  },
  TabRecord() =>
    value.props.map((e) => e is String ? e : e.toString()).toList(),
  _ => value,
};

List<String> types(List<LayoutOp> ops) => [
  for (final op in ops) op.runtimeType.toString(),
];

void main() {
  group('planner determinism', () {
    test(
      'plans the same operations from the same state and a fresh minter',
      () {
        final first = seededState();
        final second = seededState();
        final planOne = planSplitPane(
          first.state,
          first.minter,
          makePaneTab: seedTab,
        );
        final planTwo = planSplitPane(
          second.state,
          second.minter,
          makePaneTab: seedTab,
        );
        expect(planOne, equals(planTwo));
        expect(planOne, isNotEmpty);
      },
    );

    test('leaves the state it was handed untouched', () {
      final s = seededState();
      final before = frozen(s.state);
      planSetExpanded(s.state, true);
      planSplitPane(s.state, s.minter, makePaneTab: seedTab);
      planOpenContent(
        s.state,
        s.minter,
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      planFloatTab(
        s.state,
        s.minter,
        getPane(s.state, s.state.rootId).tabs.first,
      );
      expect(frozen(s.state), before);
    });

    test('plans nothing for an intent that changes nothing', () {
      final s = seededState();
      final pane = getPane(s.state, s.state.rootId);
      final tabId = pane.tabs.first;
      // Already collapsed; already in that mode; already in that slot; centre
      // release on its own pane.
      expect(planSetExpanded(s.state, false), isEmpty);
      expect(planSetMode(s.state, DockMode.push), isEmpty);
      expect(planSetMode(s.state, DockMode.fullscreen), [
        const SetModeOp(DockMode.fullscreen),
      ]);
      expect(planPlaceTab(s.state, tabId, pane.paneId, 0), isEmpty);
      expect(
        planDropTab(s.state, s.minter, tabId, pane.paneId, DockZone.center),
        isEmpty,
      );
    });

    test('refuses to plan past the pane budget', () {
      final s = seededState();
      var state = s.state;
      for (var i = 0; i < 3; i++) {
        state = applyAll(
          state,
          planSplitPane(
            state,
            s.minter,
            paneId: state.activePaneId,
            makePaneTab: seedTab,
          ),
        );
      }
      expect(
        planSplitPane(
          state,
          s.minter,
          paneId: state.activePaneId,
          makePaneTab: seedTab,
        ),
        isEmpty,
      );
      final firstPane = dockPaneIds(state).first;
      final tabId = getPane(state, firstPane).tabs.first;
      expect(
        planDropTab(state, s.minter, tabId, firstPane, DockZone.right),
        isEmpty,
      );
    });
  });

  group('planPlaceTab', () {
    ({LayoutState state, PaneId paneId, TabId a, TabId b, TabId c})
    threeTabs() {
      final s = seededState();
      final paneId = getPane(s.state, s.state.rootId).paneId;
      final b = planOpenContent(
        s.state,
        s.minter,
        const OpenContentInput(contentId: fileB, title: 'b', kind: 'file'),
      );
      final withB = applyAll(s.state, b.ops);
      final c = planOpenContent(
        withB,
        s.minter,
        const OpenContentInput(contentId: fileC, title: 'c', kind: 'file'),
      );
      final withC = applyAll(withB, c.ops);
      return (
        state: withC,
        paneId: paneId,
        a: getPane(withC, paneId).tabs.first,
        b: b.tabId,
        c: c.tabId,
      );
    }

    List<TabId> after(TabId Function(dynamic) pick, int index) {
      final t = threeTabs();
      final tabId = pick(t);
      return getPane(
        applyAll(t.state, planPlaceTab(t.state, tabId, t.paneId, index)),
        t.paneId,
      ).tabs;
    }

    test('reads the slot as the caret over the strip as drawn, the dragged chip included', () {
      final t = threeTabs();
      // Rightward: the caret between b and c is slot 2, and a lands between them.
      expect(after((x) => x.a as TabId, 2), [t.b, t.a, t.c]);
      expect(after((x) => x.a as TabId, 3), [t.b, t.c, t.a]);
      // Leftward: the chip sits after the caret, so the slot is the final index.
      expect(after((x) => x.c as TabId, 0), [t.c, t.a, t.b]);
      expect(after((x) => x.c as TabId, 1), [t.a, t.c, t.b]);
    });

    test('plans nothing for the slot on either side of the dragged chip', () {
      final t = threeTabs();
      for (final (tab, index) in [
        (t.a, 0),
        (t.a, 1),
        (t.b, 1),
        (t.b, 2),
        (t.c, 2),
        (t.c, 3),
      ]) {
        expect(planPlaceTab(t.state, tab, t.paneId, index), isEmpty);
      }
    });
  });

  group("planDropTab on the tab's own pane", () {
    test("plans nothing for a pane's only tab released on any of its own edges without a factory", () {
      final s = seededState();
      final pane = getPane(s.state, s.state.rootId);
      for (final zone in [
        DockZone.left,
        DockZone.right,
        DockZone.top,
        DockZone.bottom,
      ]) {
        expect(
          planDropTab(s.state, s.minter, pane.tabs.first, pane.paneId, zone),
          isEmpty,
        );
      }
    });

    test("splits on a sole tab's own edge when a factory backfills the pane it vacates", () {
      final s = seededState();
      final pane = getPane(s.state, s.state.rootId);
      final tabId = pane.tabs.first;
      final ops = planDropTab(
        s.state,
        s.minter,
        tabId,
        pane.paneId,
        DockZone.right,
        seedTab,
      );
      expect(types(ops), ['SplitOp', 'OpenTabOp', 'MoveTabOp']);
      final result = applyAll(s.state, ops);
      final [home, destination] = dockPaneIds(result);
      expect(getPane(result, home).tabs, hasLength(1));
      expect(getPane(result, home).tabs.first, isNot(tabId));
      expect(getPane(result, destination).tabs, [tabId]);
      // The backfill seats first, so the moved tab ends focused.
      expect(result.activePaneId, destination);
    });

    test('splits without a backfill when the pane keeps another tab, factory or not', () {
      final s = seededState();
      final opened = planOpenContent(
        s.state,
        s.minter,
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      final two = applyAll(s.state, opened.ops);
      final target = getPane(two, two.rootId).paneId;
      expect(
        types(planDropTab(two, s.minter, opened.tabId, target, DockZone.right)),
        ['SplitOp', 'MoveTabOp'],
      );
      final ops = planDropTab(
        two,
        s.minter,
        opened.tabId,
        target,
        DockZone.right,
        seedTab,
      );
      expect(types(ops), ['SplitOp', 'MoveTabOp']);
      final result = applyAll(two, ops);
      expect(dockPaneIds(result), hasLength(2));
      expect(getPane(result, two.rootId).tabs, hasLength(1));
    });
  });

  group('floating panes as planner arguments', () {
    ({LayoutState state, IdMinter mint, PaneId floatId, TabId tabId})
    withFloat() {
      final s = seededState();
      final opened = planOpenContent(
        s.state,
        s.minter,
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      final docked = applyAll(s.state, opened.ops);
      final floated = planFloatTab(docked, s.minter, opened.tabId);
      return (
        state: applyAll(docked, floated.ops),
        mint: s.minter,
        floatId: floated.paneId,
        tabId: opened.tabId,
      );
    }

    test(
      'plans nothing into a floating pane: no split, no seeded tab, no drop',
      () {
        final w = withFloat();
        expect(
          planSplitPane(
            w.state,
            w.mint,
            paneId: w.floatId,
            makePaneTab: seedTab,
          ),
          isEmpty,
        );
        expect(planAddTab(w.state, w.mint, w.floatId, seedTab), isEmpty);
        final seeded = getPane(w.state, w.state.rootId).tabs.first;
        expect(
          planDropTab(w.state, w.mint, seeded, w.floatId, DockZone.center),
          isEmpty,
        );
      },
    );

    test('copies a floating tab into the active docked pane, at its end', () {
      final w = withFloat();
      expect(w.state.activePaneId, isNot(w.state.rootId));
      expect(activeDockPaneId(w.state), w.state.rootId);
      final copy = planDuplicateTab(w.state, w.mint, w.tabId);
      final op = copy.ops.first as OpenTabOp;
      expect(op.paneId, w.state.rootId);
      expect(op.index, 1);
      expect(
        getPane(applyAll(w.state, copy.ops), w.state.rootId).tabs.last,
        copy.tabId,
      );
    });
  });

  group('planSettle', () {
    ({LayoutState state, IdMinter mint, PaneId left, PaneId right}) twoPanes() {
      final s = seededState();
      final split = applyAll(
        s.state,
        planSplitPane(s.state, s.minter, makePaneTab: seedTab),
      );
      final [left, right] = dockPaneIds(split);
      return (state: split, mint: s.minter, left: left, right: right);
    }

    test('plans nothing while every docked pane holds a tab', () {
      final t = twoPanes();
      expect(planSettle(t.state, t.mint, seedTab), isEmpty);
    });

    test('merges away each pane an intent emptied, one after another', () {
      final t = twoPanes();
      final third = applyAll(
        t.state,
        planSplitPane(t.state, t.mint, paneId: t.right, makePaneTab: seedTab),
      );
      final toClose = [
        for (final id in dockPaneIds(third)) ...getPane(third, id).tabs,
      ].where((tabId) => findTabPane(third, tabId).paneId != t.left);
      final emptied = toClose.fold(
        third,
        (current, tabId) => applyAll(current, [CloseTabOp(tabId)]),
      );
      final ops = planSettle(emptied, t.mint, seedTab);
      expect(types(ops), ['MergeOp', 'MergeOp']);
      expect(dockPaneIds(applyAll(emptied, ops)), [t.left]);
    });

    test('reseeds an emptied root pane through the factory, and leaves it empty without one', () {
      final s = seededState();
      final tabId = getPane(s.state, s.state.rootId).tabs.first;
      final emptied = applyAll(s.state, [CloseTabOp(tabId)]);
      final reseeded = planSettle(emptied, s.minter, seedTab);
      expect(types(reseeded), ['OpenTabOp']);
      expect(
        getPane(applyAll(emptied, reseeded), emptied.rootId).tabs,
        hasLength(1),
      );
      expect(planSettle(emptied, s.minter), isEmpty);
    });
  });

  group('planOpenContent placement and identity', () {
    test('identifies content by (kind, contentId): the same address under another kind opens another tab', () {
      final s = seededState();
      final first = planOpenContent(
        s.state,
        s.minter,
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      final opened = applyAll(s.state, first.ops);
      expect(findContentTab(opened, fileA), first.tabId);
      expect(findContentTab(opened, fileA, 'file'), first.tabId);
      expect(findContentTab(opened, fileA, 'hex'), isNull);
      // The pane-level lookup answers for one pane only.
      final pane = dockPaneIds(opened).first;
      expect(findPaneContentTab(opened, pane, fileA), first.tabId);
      expect(findPaneContentTab(opened, pane, fileA, 'hex'), isNull);
      expect(
        findPaneContentTab(
          opened,
          pane,
          'dsh-resource://file/session/s/nowhere.txt',
        ),
        isNull,
      );
      final again = planOpenContent(
        opened,
        s.minter,
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      expect(types(again.ops), ['FocusTabOp']);
      final other = planOpenContent(
        opened,
        s.minter,
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'hex'),
      );
      expect(types(other.ops), ['OpenTabOp']);
    });

    test('opens another tab when told not to reveal the existing one', () {
      final s = seededState();
      final opened = applyAll(
        s.state,
        planOpenContent(
          s.state,
          s.minter,
          const OpenContentInput(
            contentId: fileA,
            title: 'a.txt',
            kind: 'file',
          ),
        ).ops,
      );
      final copy = planOpenContent(
        opened,
        s.minter,
        const OpenContentInput(
          contentId: fileA,
          title: 'a.txt',
          kind: 'file',
          revealIfOpened: false,
        ),
      );
      expect(types(copy.ops), ['OpenTabOp']);
      final both = applyAll(opened, copy.ops);
      expect(
        both.tabs.values.where((tab) => tab.contentId == fileA),
        hasLength(2),
      );
    });

    test('seats a new tab at an explicit strip slot', () {
      final s = seededState();
      final paneId = getPane(s.state, s.state.rootId).paneId;
      final planned = planOpenContent(
        s.state,
        s.minter,
        OpenContentInput(
          contentId: fileA,
          title: 'a.txt',
          kind: 'file',
          paneId: paneId,
          index: 0,
        ),
      );
      final op = planned.ops.first as OpenTabOp;
      expect((op.paneId, op.index), (paneId, 0));
      expect(
        getPane(applyAll(s.state, planned.ops), paneId).tabs.first,
        planned.tabId,
      );
    });
  });

  group('planAddTab', () {
    test("seats the factory's tab at the end of the pane, and plans nothing without a factory", () {
      final s = seededState();
      final paneId = getPane(s.state, s.state.rootId).paneId;
      final ops = planAddTab(s.state, s.minter, paneId, seedTab);
      expect(types(ops), ['OpenTabOp']);
      final op = ops.first as OpenTabOp;
      expect(op.paneId, paneId);
      expect(op.index, getPane(s.state, paneId).tabs.length);
      expect(planAddTab(s.state, s.minter, paneId), isEmpty);
    });
  });

  group('one undo behaviour across both embeddings', () {
    ({History history, LayoutState state}) driveByHand() {
      final minter = IdMinter();
      var state = createInitialState(minter, seedTab);
      var history = emptyHistory;
      void run(List<LayoutOp> ops) {
        final stepped = record(history, state, ops);
        history = stepped.history;
        state = stepped.state;
      }

      run(planSetExpanded(state, true));
      run(planSplitPane(state, minter, makePaneTab: seedTab));
      final opened = planOpenContent(
        state,
        minter,
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      run(opened.ops);
      final copy = planDuplicateTab(state, minter, opened.tabId);
      run(copy.ops);
      run([FocusTabOp(opened.tabId)]);
      run([FocusTabOp(copy.tabId)]);
      run([FocusTabOp(opened.tabId)]);
      return (history: history, state: state);
    }

    DockController driveByController() {
      final controller = seededController();
      controller.setExpanded(true);
      controller.splitPane();
      final opened = controller.openContent(
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      final copy = controller.duplicateTab(opened);
      controller.focusTab(opened);
      controller.focusTab(copy);
      controller.focusTab(opened);
      return controller;
    }

    test('records the same sequence either way', () {
      final byHand = driveByHand();
      final controller = driveByController();
      expect(recordedOps(byHand.history), equals(controller.ops));
      expect(byHand.state, equals(controller.snapshot.state));
    });

    test('merges a focus run into one step in both embeddings', () {
      final byHand = driveByHand();
      final controller = driveByController();

      final stepped = stepBack(byHand.history, byHand.state)!;
      expect(controller.undo(), isTrue);
      // Three consecutive focus moves collapse to one step on both paths.
      expect(byHand.history.cursor - stepped.history.cursor, 3);
      expect(stepped.history.cursor, controller.snapshot.cursor);
      expect(stepped.state, equals(controller.snapshot.state));

      final forward = stepForward(stepped.history, stepped.state)!;
      expect(controller.redo(), isTrue);
      expect(forward.history.cursor, controller.snapshot.cursor);
      expect(forward.state, equals(controller.snapshot.state));
    });

    test(
      'discards the redo branch on both paths when a new operation lands',
      () {
        final byHand = driveByHand();
        final controller = driveByController();
        final stepped = stepBack(byHand.history, byHand.state)!;
        expect(controller.undo(), isTrue);

        final reopened = record(stepped.history, stepped.state, const [
          SetExpandedOp(false),
        ]);
        controller.setExpanded(false);
        expect(recordedOps(reopened.history), equals(controller.ops));
        expect(stepForward(reopened.history, reopened.state), isNull);
        expect(controller.snapshot.canRedo, isFalse);
      },
    );
  });

  group('planned intents survive replay', () {
    test('rebuilds the same tree from the operations a planner produced', () {
      final s = seededState();
      final ops = <LayoutOp>[];
      var current = s.state;
      void push(List<LayoutOp> planned) {
        ops.addAll(planned);
        current = applyAll(current, planned);
      }

      push(planSetExpanded(current, true));
      push(planSplitPane(current, s.minter, makePaneTab: seedTab));
      final opened = planOpenContent(
        current,
        s.minter,
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      push(opened.ops);
      final second = getSplit(current, current.rootId).children[1];
      push(
        planPlaceTab(current, opened.tabId, getPane(current, second).paneId, 0),
      );
      final floated = planFloatTab(current, s.minter, opened.tabId);
      push(floated.ops);
      push(planUnfloatPane(current, floated.paneId));

      expect(applyAll(s.state, ops), equals(current));
    });
  });
}
