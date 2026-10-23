/// One file change in the form the diff card draws (dsh `DiffHunk`).
class DshDiffHunk {
  const DshDiffHunk({
    required this.path,
    required this.oldText,
    required this.newText,
  });

  final String path;

  /// Prior content, or null when none is available (a create).
  final String? oldText;
  final String newText;
}

/// Kind of one body row of the diff card.
enum DshDiffRowKind { path, del, add, context, gap }

class DshDiffRow {
  const DshDiffRow(this.kind, this.text);
  final DshDiffRowKind kind;
  final String text;
}

/// Bound synchronous edit-graph search; one replacement consumes two edits
/// (dsh `MAX_DIFF_EDIT_LENGTH`).
const int maxDiffEditLength = 256;

/// The content lines of one side: empty text is zero lines, a single trailing
/// newline is a terminator, an interior blank line survives (dsh
/// `contentLines`).
List<String> contentLines(String text) {
  if (text.isEmpty) return const [];
  final body = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  return body.split('\n');
}

class _Component {
  _Component(this.count, this.added, this.removed, this.previous);
  int count;
  final bool added;
  final bool removed;
  final _Component? previous;
}

class _Path {
  _Path(this.oldPos, this.last);
  int oldPos;
  _Component? last;
}

_Component? _addToPath(
  _Component? last,
  bool added,
  bool removed,
  int oldPosInc,
) {
  if (last != null && last.added == added && last.removed == removed) {
    return _Component(last.count + 1, added, removed, last.previous);
  }
  return _Component(1, added, removed, last);
}

/// Line diff with the semantics of jsdiff's Myers `diffLines` (the algorithm
/// dsh's `structuredPatch` runs): returns the change components in order, or
/// null when the edit distance exceeds [maxEdit].
List<({int count, bool added, bool removed})>? _diffLines(
  List<String> oldLines,
  List<String> newLines,
  int maxEdit,
) {
  final newLen = newLines.length;
  final oldLen = oldLines.length;
  var editLength = 1;
  var maxEditLength = newLen + oldLen;
  if (maxEdit < maxEditLength) maxEditLength = maxEdit;
  final bestPath = <int, _Path?>{0: _Path(-1, null)};

  int extractCommon(_Path base, int diagonal) {
    var oldPos = base.oldPos;
    var newPos = oldPos - diagonal;
    var common = 0;
    while (newPos + 1 < newLen &&
        oldPos + 1 < oldLen &&
        newLines[newPos + 1] == oldLines[oldPos + 1]) {
      newPos++;
      oldPos++;
      common++;
    }
    if (common > 0) {
      base.last = _Component(common, false, false, base.last);
    }
    base.oldPos = oldPos;
    return newPos;
  }

  final first = bestPath[0]!;
  final firstNew = extractCommon(first, 0);
  if (first.oldPos + 1 >= oldLen && firstNew + 1 >= newLen) {
    return _flatten(first.last);
  }

  var minDiagonal = -1 << 30;
  var maxDiagonal = 1 << 30;

  _Path? execEditLength() {
    for (
      var diagonal = (minDiagonal > -editLength ? minDiagonal : -editLength);
      diagonal <= (maxDiagonal < editLength ? maxDiagonal : editLength);
      diagonal += 2
    ) {
      _Path? basePath;
      final addPath = bestPath[diagonal + 1];
      final removePath = bestPath[diagonal - 1];
      if (removePath != null) bestPath[diagonal - 1] = null;
      final canAdd =
          addPath != null &&
          0 <= addPath.oldPos - diagonal &&
          addPath.oldPos - diagonal < newLen;
      final canRemove = removePath != null && removePath.oldPos + 1 < oldLen;
      if (!canAdd && !canRemove) {
        bestPath[diagonal] = null;
        continue;
      }
      if (!canRemove || (canAdd && removePath.oldPos < addPath.oldPos)) {
        basePath = _Path(
          addPath!.oldPos,
          _addToPath(addPath.last, true, false, 0),
        );
      } else {
        basePath = _Path(
          removePath.oldPos + 1,
          _addToPath(removePath.last, false, true, 1),
        );
      }
      final newPos = extractCommon(basePath, diagonal);
      if (basePath.oldPos + 1 >= oldLen && newPos + 1 >= newLen) {
        return basePath;
      }
      bestPath[diagonal] = basePath;
      if (basePath.oldPos + 1 >= oldLen) {
        maxDiagonal = maxDiagonal < diagonal - 1 ? maxDiagonal : diagonal - 1;
      }
      if (newPos + 1 >= newLen) {
        minDiagonal = minDiagonal > diagonal + 1 ? minDiagonal : diagonal + 1;
      }
    }
    editLength++;
    return null;
  }

  while (editLength <= maxEditLength) {
    final done = execEditLength();
    if (done != null) return _flatten(done.last);
  }
  return null;
}

List<({int count, bool added, bool removed})> _flatten(_Component? last) {
  final reversed = <_Component>[];
  for (var c = last; c != null; c = c.previous) {
    reversed.add(c);
  }
  final list = [
    for (final c in reversed.reversed)
      (count: c.count, added: c.added, removed: c.removed),
  ];
  // jsdiff outputs removals before additions inside one change block.
  for (var i = 1; i < list.length; i++) {
    if (list[i - 1].added && list[i].removed) {
      final tmp = list[i - 1];
      list[i - 1] = list[i];
      list[i] = tmp;
    }
  }
  return list;
}

/// Patch lines (` `, `-`, `+` prefixed) of one hunk-list, with [context]
/// unchanged lines around each change (jsdiff `structuredPatch`, lines only).
List<List<String>>? _structuredPatchLines(
  List<String> oldLines,
  List<String> newLines,
  int context,
  int maxEdit,
) {
  final diff = _diffLines(oldLines, newLines, maxEdit);
  if (diff == null) return null;
  // Materialise the lines of each component in order.
  final parts = <({bool added, bool removed, List<String> lines})>[];
  var oi = 0;
  var ni = 0;
  for (final c in diff) {
    if (c.added) {
      parts.add((
        added: true,
        removed: false,
        lines: newLines.sublist(ni, ni + c.count),
      ));
      ni += c.count;
    } else if (c.removed) {
      parts.add((
        added: false,
        removed: true,
        lines: oldLines.sublist(oi, oi + c.count),
      ));
      oi += c.count;
    } else {
      parts.add((
        added: false,
        removed: false,
        lines: newLines.sublist(ni, ni + c.count),
      ));
      oi += c.count;
      ni += c.count;
    }
  }
  parts.add((added: false, removed: false, lines: const <String>[]));

  List<String> ctx(List<String> lines) => [for (final l in lines) ' $l'];
  final hunks = <List<String>>[];
  var inRange = false;
  var cur = <String>[];
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part.added || part.removed) {
      if (!inRange) {
        inRange = true;
        if (i > 0) {
          final prev = parts[i - 1].lines;
          cur = ctx(
            context > 0
                ? prev.sublist(
                    prev.length > context ? prev.length - context : 0,
                  )
                : const [],
          );
        }
      }
      final sign = part.added ? '+' : '-';
      cur.addAll([for (final l in part.lines) '$sign$l']);
    } else if (inRange) {
      if (part.lines.length <= context * 2 && i < parts.length - 2) {
        cur.addAll(ctx(part.lines));
      } else {
        final size = part.lines.length < context ? part.lines.length : context;
        cur.addAll(ctx(part.lines.sublist(0, size)));
        hunks.add(cur);
        inRange = false;
        cur = <String>[];
      }
    }
  }
  return hunks;
}

List<List<String>> _localHunks(DshDiffHunk diff) {
  final oldLines = contentLines(diff.oldText ?? '');
  final newLines = contentLines(diff.newText);
  final hunks = _structuredPatchLines(oldLines, newLines, 3, maxDiffEditLength);
  return hunks ??
      [
        [for (final l in oldLines) '-$l', for (final l in newLines) '+$l'],
      ];
}

/// Count displayed additions and deletions (dsh `diffTotals`).
({int added, int removed}) diffTotals(List<DshDiffHunk> diffs) {
  var added = 0;
  var removed = 0;
  for (final diff in diffs) {
    for (final hunk in _localHunks(diff)) {
      for (final line in hunk) {
        if (line.startsWith('+')) added++;
        if (line.startsWith('-')) removed++;
      }
    }
  }
  return (added: added, removed: removed);
}

/// Flatten local patches into body rows: a path header opens each new file, a
/// `⋯` gap separates same-file fragments and distant patches (dsh `buildRows`).
List<DshDiffRow> buildDiffRows(List<DshDiffHunk> diffs) {
  final rows = <DshDiffRow>[];
  String? prevPath;
  for (final diff in diffs) {
    if (diff.path != prevPath) {
      rows.add(DshDiffRow(DshDiffRowKind.path, diff.path));
    } else {
      rows.add(const DshDiffRow(DshDiffRowKind.gap, '⋯'));
    }
    prevPath = diff.path;
    final hunks = _localHunks(diff);
    for (var index = 0; index < hunks.length; index++) {
      if (index > 0) rows.add(const DshDiffRow(DshDiffRowKind.gap, '⋯'));
      for (final line in hunks[index]) {
        final kind = line.startsWith('-')
            ? DshDiffRowKind.del
            : line.startsWith('+')
            ? DshDiffRowKind.add
            : DshDiffRowKind.context;
        rows.add(DshDiffRow(kind, line.substring(1)));
      }
    }
  }
  return rows;
}

/// The diff as plain text for the clipboard (dsh `copyText`).
String diffCopyText(List<DshDiffRow> rows) => rows
    .map(
      (row) => switch (row.kind) {
        DshDiffRowKind.del => '- ${row.text}',
        DshDiffRowKind.add => '+ ${row.text}',
        DshDiffRowKind.context => '  ${row.text}',
        _ => row.text,
      },
    )
    .join('\n');
