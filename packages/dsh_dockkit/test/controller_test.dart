// Controller behaviour (dsh `controller.client.spec.ts`): the interaction
// vocabulary the UI calls, including tab identity, the seeded tab a split
// seats, drop resolution, floating, and the notification contract.
import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

List<String> titles(LayoutState state, PaneId paneId) => [
  for (final id in getPane(state, paneId).tabs) state.tabs[id]?.title ?? '?',
];

({DockController controller, PaneId paneId}) expanded() {
  final controller = seededController();
  controller.setExpanded(true);
  final state = controller.snapshot.state;
  return (controller: controller, paneId: getPane(state, state.rootId).paneId);
}

OpenContentInput textA() => const OpenContentInput(
  contentId: fileA,
  title: 'a.txt',
  kind: 'text-preview',
);
OpenContentInput textB() => const OpenContentInput(
  contentId: fileB,
  title: 'b.txt',
  kind: 'text-preview',
);

List<String> types(List<LayoutOp> ops) => [
  for (final op in ops) op.runtimeType.toString(),
];

void main() {
  group('expand', () {
    test('starts collapsed with a seeded tab already seated', () {
      final controller = seededController();
      final snapshot = controller.snapshot;
      expect(snapshot.state.expanded, isFalse);
      expect(snapshot.canUndo, isFalse);
      expect(snapshot.canSplit, isTrue);
      expect(
        titles(
          snapshot.state,
          getPane(snapshot.state, snapshot.state.rootId).paneId,
        ),
        hasLength(1),
      );
      expect(snapshot.state.tabs.values.first.contentId, seedContentId);
    });

    test('records a toggle and ignores a redundant set', () {
      final controller = seededController();
      controller.toggleExpanded();
      expect(controller.snapshot.state.expanded, isTrue);
      expect(controller.ops, hasLength(1));
      controller.setExpanded(true);
      expect(controller.ops, hasLength(1));
      controller.toggleExpanded();
      expect(controller.snapshot.state.expanded, isFalse);
      expect(controller.ops, hasLength(2));
    });
  });

  group('presentation', () {
    test('records a mode switch once and ignores a redundant one', () {
      final controller = seededController();
      controller.setMode(DockMode.fullscreen);
      expect(controller.snapshot.state.mode, DockMode.fullscreen);
      controller.setMode(DockMode.fullscreen);
      expect(types(controller.ops), ['SetModeOp']);
    });
  });

  group('splitting', () {
    test(
      'splits the active pane to the right and seats a seeded tab there',
      () {
        final e = expanded();
        expect(e.controller.splitPane(), isTrue);
        final state = e.controller.snapshot.state;
        final root = getSplit(state, state.rootId);
        expect(root.axis, SplitAxis.row);
        final newPaneId = getPane(state, root.children[1]).paneId;
        expect(newPaneId, isNot(e.paneId));
        expect(titles(state, newPaneId), hasLength(1));
        expect(
          state.tabs[getPane(state, newPaneId).tabs.first]?.contentId,
          seedContentId,
        );
        expect(types(e.controller.ops), [
          'SetExpandedOp',
          'SplitOp',
          'OpenTabOp',
        ]);
      },
    );

    test("seats the pane factory's tab at the end of a strip from the add control, and nothing without one", () {
      final e = expanded();
      expect(e.controller.addTab(e.paneId), isTrue);
      expect(titles(e.controller.snapshot.state, e.paneId), ['Start', 'Start']);
      final bare = DockController(
        DockControllerOptions(
          makeInitialTab: (id) => TabRecord(
            id: id,
            kind: 'seed',
            contentId: seedContentId,
            title: 'Start',
          ),
        ),
      );
      final s = bare.snapshot.state;
      expect(bare.addTab(getPane(s, s.rootId).paneId), isFalse);
    });

    test('names the pane a new tab lands in: the active pane, or the first docked one while a panel floats', () {
      final e = expanded();
      expect(e.controller.activeDockPaneId(), e.paneId);
      final tabId = e.controller.openContent(textA());
      final floatId = e.controller.floatTab(tabId);
      expect(e.controller.snapshot.state.activePaneId, floatId);
      expect(e.controller.activeDockPaneId(), e.paneId);
    });

    test('stops at four panes without recording anything', () {
      final e = expanded();
      expect(e.controller.splitPane(), isTrue);
      expect(e.controller.splitPane(), isTrue);
      expect(e.controller.splitPane(), isTrue);
      expect(dockPaneCount(e.controller.snapshot.state), 4);
      final before = e.controller.ops.length;
      expect(e.controller.splitPane(), isFalse);
      expect(e.controller.ops, hasLength(before));
      expect(e.controller.snapshot.canSplit, isFalse);
    });
  });

  group('tab identity', () {
    test('focuses the existing tab when the same content is opened twice', () {
      final e = expanded();
      final first = e.controller.openContent(textA());
      e.controller.splitPane();
      final again = e.controller.openContent(textA());
      expect(again, first);
      final state = e.controller.snapshot.state;
      expect(getPane(state, e.paneId).activeTabId, first);
      expect(state.activePaneId, e.paneId);
      expect(
        state.tabs.values.where((t) => t.contentId == fileA),
        hasLength(1),
      );
    });

    test('opens an explicit second copy beside the original', () {
      final e = expanded();
      final first = e.controller.openContent(textA());
      final copy = e.controller.duplicateTab(first);
      expect(copy, isNot(first));
      final state = e.controller.snapshot.state;
      expect(state.tabs[copy]?.contentId, fileA);
      final tabs = getPane(state, e.paneId).tabs;
      expect(tabs.indexOf(copy), tabs.indexOf(first) + 1);
    });

    test('closes a tab and leaves the pane in place', () {
      final e = expanded();
      final tabId = e.controller.openContent(textA());
      e.controller.closeTab(tabId);
      final state = e.controller.snapshot.state;
      expect(state.tabs[tabId], isNull);
      expect(dockPaneIds(state), [e.paneId]);
    });
  });

  group('drops', () {
    PaneId secondPane(DockController c) {
      final state = c.snapshot.state;
      return getPane(state, getSplit(state, state.rootId).children[1]).paneId;
    }

    test('moves a tab into the pane under the pointer', () {
      final e = expanded();
      final tabId = e.controller.openContent(textA());
      e.controller.splitPane();
      final target = secondPane(e.controller);
      expect(e.controller.dropTab(tabId, target, DockZone.center), isTrue);
      final state = e.controller.snapshot.state;
      expect(getPane(state, target).tabs, contains(tabId));
      expect(getPane(state, e.paneId).tabs, isNot(contains(tabId)));
      expect(state.activePaneId, target);
    });

    test('rejects a centre drop on the tab own pane', () {
      final e = expanded();
      final tabId = e.controller.openContent(textA());
      final before = e.controller.ops.length;
      expect(e.controller.dropTab(tabId, e.paneId, DockZone.center), isFalse);
      expect(e.controller.ops, hasLength(before));
    });

    test('splits on an edge drop and lands the tab in the new pane', () {
      final e = expanded();
      final tabId = e.controller.openContent(textA());
      expect(e.controller.dropTab(tabId, e.paneId, DockZone.bottom), isTrue);
      final state = e.controller.snapshot.state;
      final root = getSplit(state, state.rootId);
      expect(root.axis, SplitAxis.column);
      expect(getPane(state, root.children[1]).tabs, [tabId]);
      expect(dockPaneCount(state), 2);
    });

    test('refuses an edge drop once the grid is full', () {
      final e = expanded();
      final tabId = e.controller.openContent(textA());
      e.controller.splitPane();
      e.controller.splitPane();
      e.controller.splitPane();
      final before = e.controller.ops.length;
      expect(e.controller.dropTab(tabId, e.paneId, DockZone.right), isFalse);
      expect(e.controller.ops, hasLength(before));
    });

    test('reorders inside one pane', () {
      final e = expanded();
      final first = e.controller.openContent(textA());
      e.controller.reorderTab(first, 0);
      expect(getPane(e.controller.snapshot.state, e.paneId).tabs.first, first);
    });
  });

  group('explicit tab placement', () {
    test('reorders when the slot is in the tab own pane', () {
      final e = expanded();
      final first = e.controller.openContent(textA());
      expect(e.controller.placeTab(first, e.paneId, 0), isTrue);
      expect(getPane(e.controller.snapshot.state, e.paneId).tabs.first, first);
      expect(e.controller.ops.last, isA<ReorderTabOp>());
    });

    test('reports no change when the slot is where the tab already sits', () {
      final e = expanded();
      final tabId = e.controller.openContent(textA());
      final index = getPane(
        e.controller.snapshot.state,
        e.paneId,
      ).tabs.indexOf(tabId);
      final before = e.controller.ops.length;
      expect(e.controller.placeTab(tabId, e.paneId, index), isFalse);
      expect(e.controller.ops, hasLength(before));
    });

    test('moves across panes into the requested slot', () {
      final e = expanded();
      final tabId = e.controller.openContent(textA());
      e.controller.splitPane();
      final state0 = e.controller.snapshot.state;
      final target = getPane(
        state0,
        getSplit(state0, state0.rootId).children[1],
      ).paneId;
      expect(e.controller.placeTab(tabId, target, 0), isTrue);
      final state = e.controller.snapshot.state;
      expect(getPane(state, target).tabs.first, tabId);
      expect(getPane(state, e.paneId).tabs, isNot(contains(tabId)));
    });

    test('returns a floating tab when placed into a docked strip', () {
      final e = expanded();
      final tabId = e.controller.openContent(textA());
      final floatId = e.controller.floatTab(tabId);
      expect(e.controller.placeTab(tabId, e.paneId, 0), isTrue);
      final state = e.controller.snapshot.state;
      expect(state.floats, isEmpty);
      expect(state.nodes[floatId], isNull);
      expect(getPane(state, e.paneId).tabs.first, tabId);
    });

    test('refuses a floating pane as the destination', () {
      final e = expanded();
      final first = e.controller.openContent(textA());
      final second = e.controller.openContent(textB());
      final floatId = e.controller.floatTab(first);
      final before = e.controller.ops.length;
      expect(e.controller.placeTab(second, floatId, 0), isFalse);
      expect(e.controller.ops, hasLength(before));
    });
  });

  group('floating', () {
    test('takes a tab out and cascades each new panel', () {
      final e = expanded();
      final first = e.controller.openContent(textA());
      final second = e.controller.openContent(textB());
      final firstFloat = e.controller.floatTab(first);
      final secondFloat = e.controller.floatTab(second);
      final state = e.controller.snapshot.state;
      expect(state.floats, [firstFloat, secondFloat]);
      final one = getPane(state, firstFloat);
      final two = getPane(state, secondFloat);
      expect(one.rect?.width, floatDefaultWidth);
      expect(two.rect!.x, greaterThan(one.rect!.x));
      expect(getPane(state, e.paneId).tabs, hasLength(1));
    });

    test('is unaffected by collapsing the column', () {
      final e = expanded();
      final tabId = e.controller.openContent(textA());
      final floatId = e.controller.floatTab(tabId);
      e.controller.setExpanded(false);
      final state = e.controller.snapshot.state;
      expect(state.expanded, isFalse);
      expect(state.floats, [floatId]);
      expect(getPane(state, floatId).tabs, [tabId]);
    });

    test('sends a floating panel back into the grid', () {
      final e = expanded();
      final tabId = e.controller.openContent(textA());
      final floatId = e.controller.floatTab(tabId);
      e.controller.unfloatPane(floatId);
      final state = e.controller.snapshot.state;
      expect(state.floats, isEmpty);
      expect(findTabPane(state, tabId).paneId, e.paneId);
    });

    test('treats a centre drop from a floating panel as a return', () {
      final e = expanded();
      final tabId = e.controller.openContent(textA());
      final floatId = e.controller.floatTab(tabId);
      expect(e.controller.dropTab(tabId, e.paneId, DockZone.center), isTrue);
      final state = e.controller.snapshot.state;
      expect(state.floats, isEmpty);
      expect(state.nodes[floatId], isNull);
      expect(findTabPane(state, tabId).paneId, e.paneId);
    });

    test('records net drag and resize results', () {
      final e = expanded();
      final tabId = e.controller.openContent(textA());
      final floatId = e.controller.floatTab(tabId);
      e.controller.moveFloat(floatId, 300, 210);
      e.controller.resizeFloat(floatId, const FloatRect(300, 210, 500, 400));
      expect(
        getPane(e.controller.snapshot.state, floatId).rect,
        const FloatRect(300, 210, 500, 400),
      );
      expect(types(e.controller.ops).sublist(e.controller.ops.length - 2), [
        'MoveFloatOp',
        'ResizeFloatOp',
      ]);
    });

    test('raises a panel to the top when focused', () {
      final e = expanded();
      final first = e.controller.openContent(textA());
      final second = e.controller.openContent(textB());
      final firstFloat = e.controller.floatTab(first);
      final secondFloat = e.controller.floatTab(second);
      e.controller.focusPane(firstFloat);
      expect(e.controller.snapshot.state.floats, [secondFloat, firstFloat]);
    });
  });

  group('dividers', () {
    test('clamps a drag that would starve a pane', () {
      final e = expanded();
      e.controller.splitPane();
      final state0 = e.controller.snapshot.state;
      final splitId = getSplit(state0, state0.rootId).splitId;
      e.controller.resizeSplit(splitId, const [0.01, 0.99]);
      final sizes = getSplit(e.controller.snapshot.state, splitId).sizes;
      expect(sizes[0], greaterThan(0.05));
      expect(sizes.reduce((a, b) => a + b), closeTo(1, 1e-9));
    });
  });

  group('notification', () {
    test(
      'notifies subscribers and keeps the snapshot stable between changes',
      () {
        final controller = seededController();
        var notifications = 0;
        final dispose = controller.subscribe(() => notifications += 1);
        final before = controller.snapshot;
        expect(identical(controller.snapshot, before), isTrue);

        controller.setExpanded(true);
        expect(notifications, 1);
        expect(identical(controller.snapshot, before), isFalse);

        controller.setExpanded(true);
        expect(notifications, 1);

        dispose();
        controller.setExpanded(false);
        expect(notifications, 1);
      },
    );

    test('steps one compound command as one entry, however many operations it recorded', () {
      expect(seededController().undo(), isFalse);
      final e = expanded();
      final before = e.controller.ops.length;
      e.controller.splitPane();
      // The split and the seeded tab are two operations of one intent.
      expect(e.controller.ops.length - before, 2);
      expect(e.controller.snapshot.canUndo, isTrue);
      expect(e.controller.undo(), isTrue);
      expect(dockPaneCount(e.controller.snapshot.state), 1);
      expect(e.controller.redo(), isTrue);
      expect(dockPaneCount(e.controller.snapshot.state), 2);
      expect(e.controller.redo(), isFalse);
    });
  });

  group('the pane limit and settling', () {
    test('an embedder limit of two stops the third pane and the edge drop', () {
      final c = DockController(
        DockControllerOptions(
          makeInitialTab: seedTab,
          makePaneTab: seedTab,
          maxPanes: 2,
        ),
      );
      c.setExpanded(true);
      expect(c.splitPane(), isTrue);
      expect(c.snapshot.canSplit, isFalse);
      final before = c.ops.length;
      expect(c.splitPane(), isFalse);
      final tab = c.openContent(
        const OpenContentInput(contentId: fileA, title: 'a.txt', kind: 'file'),
      );
      final first = dockPaneIds(c.snapshot.state).first;
      expect(c.dropTab(tab, first, DockZone.bottom), isFalse);
      expect(dockPaneCount(c.snapshot.state), 2);
      expect(c.ops.length, before + 1, reason: 'only the open recorded');
    });

    test(
      'settle merges the pane an intent emptied and reseeds an emptied root',
      () {
        final c = DockController(
          DockControllerOptions(makeInitialTab: seedTab, makePaneTab: seedTab),
        );
        c.setExpanded(true);
        c.splitPane();
        final second = dockPaneIds(c.snapshot.state)[1];
        for (final tab in [...getPane(c.snapshot.state, second).tabs]) {
          c.closeTab(tab);
        }
        expect(dockPaneCount(c.snapshot.state), 2);
        expect(c.settle(), isTrue);
        expect(dockPaneCount(c.snapshot.state), 1);
        expect(c.settle(), isFalse, reason: 'nothing left to settle');
        final root = c.snapshot.state.rootId;
        c.closeTab(getPane(c.snapshot.state, root).tabs.first);
        expect(c.settle(), isTrue);
        expect(getPane(c.snapshot.state, root).tabs, hasLength(1));
      },
    );
  });
}
