// Sequence behaviour (dsh `sequence.client.spec.ts`): linear history, exact
// inverses, the focus-run undo step, and the redo branch a new operation
// discards.
import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class Fixture {
  Fixture._(
    this.initial,
    this.sequencer,
    this.minter,
    this.paneId,
    this.guideTabId,
  );

  factory Fixture() {
    final minter = IdMinter();
    final initial = createInitialState(minter, seedTab);
    final pane = getPane(initial, initial.rootId);
    return Fixture._(
      initial,
      Sequencer(initial),
      minter,
      pane.paneId,
      pane.tabs.first,
    );
  }

  final LayoutState initial;
  final Sequencer sequencer;
  final IdMinter minter;
  final PaneId paneId;
  final TabId guideTabId;

  SplitOp splitOp({PaneId? newPane}) => SplitOp(
    paneId: paneId,
    axis: SplitAxis.row,
    direction: SplitDirection.after,
    newPaneId: newPane ?? minter.pane(),
    newSplitId: minter.split(),
  );
}

List<String> types(List<LayoutOp> ops) => [
  for (final op in ops) op.runtimeType.toString(),
];

void main() {
  group('isFocusOp', () {
    test('names the operations that only move focus', () {
      expect(isFocusOp(const FocusPaneOp(PaneId('p'))), isTrue);
      expect(isFocusOp(const FocusTabOp(TabId('t'))), isTrue);
      expect(
        isFocusOp(
          const RestoreFocusOp(
            activePaneId: PaneId('p'),
            floats: [],
            paneActiveTabs: {},
          ),
        ),
        isTrue,
      );
      expect(isFocusOp(const SetExpandedOp(true)), isFalse);
    });
  });

  group('recording', () {
    test('starts with nothing to step through', () {
      final f = Fixture();
      expect(identical(f.sequencer.state, f.initial), isTrue);
      expect(f.sequencer.canUndo, isFalse);
      expect(f.sequencer.canRedo, isFalse);
      expect(f.sequencer.undo(), isFalse);
      expect(f.sequencer.redo(), isFalse);
    });

    test('records every operation, focus moves included', () {
      final f = Fixture();
      final tab = fileTab(f.minter.tab(), fileA, 'a.txt');
      f.sequencer.dispatch(OpenTabOp(paneId: f.paneId, tab: tab, index: 1));
      f.sequencer.dispatch(FocusTabOp(f.guideTabId));
      f.sequencer.dispatch(FocusTabOp(tab.id));
      expect(types(f.sequencer.ops), ['OpenTabOp', 'FocusTabOp', 'FocusTabOp']);
      expect(f.sequencer.cursor, 3);
    });

    test('exposes the recorded sequence as plain history, and records nothing for an empty intent', () {
      final f = Fixture();
      expect(identical(f.sequencer.history, emptyHistory), isTrue);
      f.sequencer.dispatch(FocusPaneOp(f.paneId));
      expect(f.sequencer.history.entries, hasLength(1));
      expect(f.sequencer.history.cursor, 1);
      final unchanged = record(emptyHistory, f.initial, const []);
      expect(identical(unchanged.history, emptyHistory), isTrue);
      expect(identical(unchanged.state, f.initial), isTrue);
      expect(
        identical(f.sequencer.dispatchAll(const []), f.sequencer.state),
        isTrue,
      );
      expect(f.sequencer.history.entries, hasLength(1));
    });

    test('leaves the sequence untouched when an operation is invalid', () {
      final f = Fixture();
      expect(
        () => f.sequencer.dispatch(const FocusPaneOp(PaneId('nope'))),
        throwsLayout('unknown node'),
      );
      expect(f.sequencer.ops, isEmpty);
      expect(f.sequencer.canUndo, isFalse);
    });
  });

  group('stepping back and forward', () {
    test('returns to the exact previous state', () {
      final f = Fixture();
      f.sequencer.dispatch(f.splitOp());
      expect(dockPaneIds(f.sequencer.state), hasLength(2));
      expect(f.sequencer.undo(), isTrue);
      expect(f.sequencer.state, equals(f.initial));
      expect(f.sequencer.canUndo, isFalse);
      expect(f.sequencer.canRedo, isTrue);
      expect(f.sequencer.redo(), isTrue);
      expect(dockPaneIds(f.sequencer.state), hasLength(2));
    });

    test('collapses a run of consecutive focus moves into one step', () {
      final f = Fixture();
      final tab = fileTab(f.minter.tab(), fileA, 'a.txt');
      f.sequencer.dispatch(OpenTabOp(paneId: f.paneId, tab: tab, index: 1));
      final afterOpen = f.sequencer.state;
      f.sequencer.dispatch(FocusTabOp(f.guideTabId));
      f.sequencer.dispatch(FocusTabOp(tab.id));
      f.sequencer.dispatch(FocusTabOp(f.guideTabId));
      expect(f.sequencer.cursor, 4);

      expect(f.sequencer.undo(), isTrue);
      expect(f.sequencer.cursor, 1);
      expect(f.sequencer.state, equals(afterOpen));

      expect(f.sequencer.redo(), isTrue);
      expect(f.sequencer.cursor, 4);
      expect(getPane(f.sequencer.state, f.paneId).activeTabId, f.guideTabId);
    });

    test('steps one structural operation even when focus moves precede it', () {
      final f = Fixture();
      f.sequencer.dispatch(FocusPaneOp(f.paneId));
      f.sequencer.dispatch(FocusTabOp(f.guideTabId));
      f.sequencer.dispatch(const SetExpandedOp(true));
      expect(f.sequencer.undo(), isTrue);
      expect(f.sequencer.cursor, 2);
      expect(f.sequencer.state.expanded, isFalse);
      expect(f.sequencer.undo(), isTrue);
      expect(f.sequencer.cursor, 0);
    });

    test('undoes a whole session back to the initial state', () {
      final f = Fixture();
      final newPaneId = f.minter.pane();
      final floatId = f.minter.float();
      f.sequencer.dispatch(const SetExpandedOp(true));
      f.sequencer.dispatch(f.splitOp(newPane: newPaneId));
      f.sequencer.dispatch(
        MoveTabOp(tabId: f.guideTabId, toPaneId: newPaneId, index: 0),
      );
      f.sequencer.dispatch(
        FloatOp(
          tabId: f.guideTabId,
          newPaneId: floatId,
          rect: const FloatRect(5, 6, 200, 100),
        ),
      );
      f.sequencer.dispatch(MoveFloatOp(paneId: floatId, x: 50, y: 60));
      while (f.sequencer.undo()) {}
      expect(f.sequencer.state, equals(f.initial));
      expect(f.sequencer.cursor, 0);
    });
  });

  group("a floating panel's drag as one step", () {
    test('raises and focuses the panel with the move, and steps both back and forward together', () {
      final f = Fixture();
      final tab = fileTab(f.minter.tab(), fileA, 'a.txt');
      final lower = f.minter.float();
      final upper = f.minter.float();
      f.sequencer.dispatch(OpenTabOp(paneId: f.paneId, tab: tab, index: 1));
      f.sequencer.dispatch(
        FloatOp(
          tabId: f.guideTabId,
          newPaneId: lower,
          rect: const FloatRect(0, 0, 200, 100),
        ),
      );
      f.sequencer.dispatch(
        FloatOp(
          tabId: tab.id,
          newPaneId: upper,
          rect: const FloatRect(20, 20, 200, 100),
        ),
      );
      f.sequencer.dispatch(FocusPaneOp(f.paneId));
      final before = f.sequencer.state;
      expect(before.floats, [lower, upper]);

      f.sequencer.dispatch(MoveFloatOp(paneId: lower, x: 50, y: 60));
      expect(f.sequencer.state.floats, [upper, lower]);
      expect(f.sequencer.state.activePaneId, lower);

      // One step back restores the rectangle, the z order, and the focus; the
      // preceding focus-only entry is its own step.
      expect(f.sequencer.undo(), isTrue);
      expect(f.sequencer.state, equals(before));
      expect(f.sequencer.redo(), isTrue);
      expect(f.sequencer.state.floats, [upper, lower]);
      expect(
        getPane(f.sequencer.state, lower).rect,
        const FloatRect(50, 60, 200, 100),
      );
      expect(f.sequencer.state.activePaneId, lower);
    });
  });

  group('linear history', () {
    test('drops the redo branch when a new operation lands after an undo', () {
      final f = Fixture();
      f.sequencer.dispatch(const SetExpandedOp(true));
      f.sequencer.dispatch(f.splitOp());
      expect(f.sequencer.undo(), isTrue);
      expect(f.sequencer.canRedo, isTrue);
      f.sequencer.dispatch(FocusPaneOp(f.paneId));
      expect(f.sequencer.canRedo, isFalse);
      expect(types(f.sequencer.ops), ['SetExpandedOp', 'FocusPaneOp']);
      expect(dockPaneIds(f.sequencer.state), hasLength(1));
    });

    test('keeps the applied prefix replayable at any cursor', () {
      final f = Fixture();
      final newPaneId = f.minter.pane();
      f.sequencer.dispatch(const SetExpandedOp(true));
      f.sequencer.dispatch(f.splitOp(newPane: newPaneId));
      f.sequencer.dispatch(
        MoveTabOp(tabId: f.guideTabId, toPaneId: newPaneId, index: 0),
      );
      f.sequencer.dispatch(
        ResizeOp(
          splitId: getSplit(
            f.sequencer.state,
            f.sequencer.state.rootId,
          ).splitId,
          sizes: const [0.7, 0.3],
        ),
      );
      f.sequencer.undo();
      f.sequencer.undo();
      expect(
        replay(f.initial, f.sequencer.ops.sublist(0, f.sequencer.cursor)),
        equals(f.sequencer.state),
      );
      f.sequencer.redo();
      expect(
        replay(f.initial, f.sequencer.ops.sublist(0, f.sequencer.cursor)),
        equals(f.sequencer.state),
      );
    });
  });
}
