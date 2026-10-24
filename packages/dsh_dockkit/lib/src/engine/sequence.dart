/// Linear operation history over [applyOp] (dsh `engine/sequence.ts`). Recording
/// is total, and grouped by intent: the operations one gesture or command
/// produced form one entry, so stepping lands on a point the user actually
/// stopped at. Stepping is coarser still across focus: a run of consecutive
/// focus-only entries undoes and redoes as one step.
///
/// Redoing re-applies the recorded operations; undoing applies the inverses that
/// were captured when they ran, so both directions stay exact. A new entry after
/// an undo drops the redo branch.
///
/// Two shapes, one implementation: [record]/[stepBack]/[stepForward] are pure
/// functions over a plain [History]; [Sequencer] is a thin mutable wrapper over
/// exactly those functions.
library;

import 'operations.dart';
import 'types.dart';

/// One recorded intent: its operations, and the operations that undo them all.
class HistoryEntry {
  const HistoryEntry(this.ops, this.inverse);

  final List<LayoutOp> ops;

  /// Already ordered for application: the last operation's inverse comes first.
  final List<LayoutOp> inverse;
}

/// A recorded sequence and how much of it is applied. Plain data.
class History {
  const History(this.entries, this.cursor);

  final List<HistoryEntry> entries;

  /// How many entries are applied; entries beyond it are the redo branch.
  final int cursor;
}

/// A sequence that has recorded nothing.
const History emptyHistory = History([], 0);

/// A history and the state it produced, returned together so neither can drift.
class HistoryStep {
  const HistoryStep(this.history, this.state);

  final History history;
  final LayoutState state;
}

/// Whether an operation only moves focus, and so merges into its neighbours'
/// undo step.
bool isFocusOp(LayoutOp op) =>
    op is FocusTabOp || op is FocusPaneOp || op is RestoreFocusOp;

bool _isFocusEntry(History history, int index) {
  if (index < 0 || index >= history.entries.length) return false;
  return history.entries[index].ops.every(isFocusOp);
}

/// Whether a step back exists.
bool canStepBack(History history) => history.cursor > 0;

/// Whether a step forward exists.
bool canStepForward(History history) => history.cursor < history.entries.length;

/// The operations a sequence has recorded, redo branch included.
List<LayoutOp> recordedOps(History history) => [
  for (final entry in history.entries) ...entry.ops,
];

/// Apply one intent's operations and record them as one entry, dropping any
/// redo branch first. An intent with no operations records nothing. Throws when
/// an operation is invalid against the state it reaches; nothing is recorded.
HistoryStep record(History history, LayoutState state, List<LayoutOp> ops) {
  if (ops.isEmpty) return HistoryStep(history, state);
  var next = state;
  final inverse = <LayoutOp>[];
  for (final op in ops) {
    final result = applyOp(next, op);
    next = result.state;
    // Undo runs the inverses in reverse operation order.
    inverse.insertAll(0, result.inverse);
  }
  final kept = history.cursor == history.entries.length
      ? history.entries
      : history.entries.sublist(0, history.cursor);
  return HistoryStep(
    History([...kept, HistoryEntry(ops, inverse)], history.cursor + 1),
    next,
  );
}

/// Step back one intent, or one whole run of consecutive focus-only intents.
/// Null when nothing can be undone.
HistoryStep? stepBack(History history, LayoutState state) {
  if (!canStepBack(history)) return null;
  var count = 1;
  if (_isFocusEntry(history, history.cursor - 1)) {
    while (_isFocusEntry(history, history.cursor - 1 - count)) {
      count += 1;
    }
  }
  var next = state;
  for (final entry
      in history.entries
          .sublist(history.cursor - count, history.cursor)
          .reversed) {
    for (final op in entry.inverse) {
      next = applyOp(next, op).state;
    }
  }
  return HistoryStep(History(history.entries, history.cursor - count), next);
}

/// Step forward over the intents the matching step back undid. Null when
/// nothing can be redone.
HistoryStep? stepForward(History history, LayoutState state) {
  if (!canStepForward(history)) return null;
  var count = 1;
  if (_isFocusEntry(history, history.cursor)) {
    while (_isFocusEntry(history, history.cursor + count)) {
      count += 1;
    }
  }
  var next = state;
  for (final entry in history.entries.sublist(
    history.cursor,
    history.cursor + count,
  )) {
    for (final op in entry.ops) {
      next = applyOp(next, op).state;
    }
  }
  return HistoryStep(History(history.entries, history.cursor + count), next);
}

/// Layout state plus its history cursor, held here instead of by the embedder.
class Sequencer {
  Sequencer(LayoutState initial) : _current = initial;

  LayoutState _current;
  History _recorded = emptyHistory;

  LayoutState get state => _current;

  /// The recorded sequence as plain data.
  History get history => _recorded;

  /// The whole recorded sequence, including a redo branch that is not applied.
  List<LayoutOp> get ops => recordedOps(_recorded);

  /// How many recorded entries are currently applied.
  int get cursor => _recorded.cursor;

  bool get canUndo => canStepBack(_recorded);
  bool get canRedo => canStepForward(_recorded);

  /// Apply and record one operation as its own entry.
  LayoutState dispatch(LayoutOp op) => dispatchAll([op]);

  /// Apply and record one intent's operations as one entry; the sequence is
  /// left untouched when an operation is invalid.
  LayoutState dispatchAll(List<LayoutOp> ops) {
    final stepped = record(_recorded, _current, ops);
    _recorded = stepped.history;
    _current = stepped.state;
    return _current;
  }

  /// Step back one intent, or one whole run of focus-only intents.
  bool undo() {
    final stepped = stepBack(_recorded, _current);
    if (stepped == null) return false;
    _recorded = stepped.history;
    _current = stepped.state;
    return true;
  }

  /// Step forward over the intents the matching undo stepped back.
  bool redo() {
    final stepped = stepForward(_recorded, _current);
    if (stepped == null) return false;
    _recorded = stepped.history;
    _current = stepped.state;
    return true;
  }
}
