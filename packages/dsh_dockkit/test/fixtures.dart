import 'package:flutter_test/flutter_test.dart'
    show Matcher, throwsA, isA, contains;
import 'package:dsh_dockkit/dsh_dockkit.dart';

/// Shared test fixtures (dsh `tests/fixtures.client.ts`). The kit has no notion
/// of a guide or a preview tab, so the suites supply their own content families,
/// exactly as an embedder does.
const String seedContentId = 'seed:start';
const String seedTitle = 'Start';

/// The seeded tab an embedder would put in a fresh pane.
TabRecord seedTab(TabId id) =>
    TabRecord(id: id, kind: 'seed', contentId: seedContentId, title: seedTitle);

/// A content tab addressed by a file URL, the shape the first embedder uses.
TabRecord fileTab(TabId id, String contentId, String title) =>
    TabRecord(id: id, kind: 'file', contentId: contentId, title: title);

/// A controller seeded on both the initial pane and every pane a split creates.
DockController seededController() => DockController(
  DockControllerOptions(makeInitialTab: seedTab, makePaneTab: seedTab),
);

/// An initial state holding one seeded tab, plus the minter that produced it.
({LayoutState state, IdMinter minter}) seededState() {
  final minter = IdMinter();
  return (state: createInitialState(minter, seedTab), minter: minter);
}

const String fileA = 'dsh-resource://file/session/s/a.txt';
const String fileB = 'dsh-resource://file/session/s/b.txt';
const String fileC = 'dsh-resource://file/session/s/c.txt';

/// Apply a plan the way any embedder does, and return the resulting state.
LayoutState applyAll(LayoutState state, List<LayoutOp> ops) =>
    ops.fold(state, (current, op) => applyOp(current, op).state);

/// Matches a [DockLayoutError] whose message contains [pattern].
Matcher throwsLayout(Pattern pattern) => throwsA(
  isA<DockLayoutError>().having((e) => e.message, 'message', contains(pattern)),
);
