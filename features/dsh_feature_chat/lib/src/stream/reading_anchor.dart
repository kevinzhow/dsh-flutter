import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// Ported from raft-flutter `apps/raft_flutter/lib/features/history_reading_anchor.dart`
// (rows are found by a typed key instead of a key-name prefix), plus the
// per-session memory dsh keeps as `chatScroll`.

/// A row of the timeline: the key a reader's position is remembered by.
class RowKey extends ValueKey<String> {
  const RowKey(super.value);
}

/// The reader's place in a session: the topmost visible row and how far below
/// the viewport top its top edge sits (negative when it starts above).
class ReadingAnchor {
  const ReadingAnchor(this.rowId, this.top);
  final String rowId;
  final double top;

  @override
  bool operator ==(Object other) =>
      other is ReadingAnchor && other.rowId == rowId && other.top == top;

  @override
  int get hashCode => Object.hash(rowId, top);
}

/// Where each session's reader stopped (dsh's per-session `chatScroll`
/// store). A session at its latest end has no entry. In memory only.
class ChatReadingMemory {
  final _anchors = <String, ReadingAnchor>{};

  ReadingAnchor? read(String sessionId) => _anchors[sessionId];

  void save(String sessionId, ReadingAnchor? anchor) {
    if (anchor == null) {
      _anchors.remove(sessionId);
    } else {
      _anchors[sessionId] = anchor;
    }
  }
}

/// A prepend preserves the center's distances; an interior insertion does not.
bool insertsBetweenRetainedRows(
  Iterable<String> before,
  Iterable<String> after,
) {
  final retained = before.toSet();
  var seen = false, inserted = false;
  for (final id in after) {
    if (retained.contains(id)) {
      if (inserted) return true;
      seen = true;
    } else if (seen) {
      inserted = true;
    }
  }
  return false;
}

bool _painted(RenderObject row) {
  RenderObject? node = row;
  while (node != null) {
    if (node is RenderSliver && node.geometry?.visible != true) return false;
    final parent = node.parent;
    if (parent != null && !parent.paintsChild(node)) return false;
    final data = node.parentData;
    if (parent is RenderSliverMultiBoxAdaptor &&
        data is SliverMultiBoxAdaptorParentData) {
      final offset = data.layoutOffset;
      final extent = parent.constraints.axis == Axis.vertical
          ? node.paintBounds.height
          : node.paintBounds.width;
      final scroll = parent.constraints.scrollOffset;
      if (offset == null ||
          offset + extent <= scroll ||
          offset >= scroll + parent.constraints.remainingPaintExtent) {
        return false;
      }
    }
    node = parent;
  }
  return true;
}

/// Captures the topmost visible row (by [RowKey]) and its distance below the
/// timeline top.
ReadingAnchor? captureReadingAnchor(BuildContext context) {
  ReadingAnchor? best;
  var bestTop = double.infinity;
  void visit(Element element) {
    final key = element.widget.key;
    if (key is RowKey) {
      final row = element.renderObject;
      final Object? clip = row == null
          ? null
          : RenderAbstractViewport.maybeOf(row);
      if (row is RenderBox &&
          clip is RenderBox &&
          row.attached &&
          _painted(row) &&
          row.hasSize &&
          clip.hasSize) {
        final top =
            row.localToGlobal(Offset.zero).dy -
            clip.localToGlobal(Offset.zero).dy;
        if (top + row.size.height > 1 &&
            top < clip.size.height &&
            top < bestTop) {
          bestTop = top;
          best = ReadingAnchor(key.value, top);
        }
      }
      return;
    }
    element.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  return best;
}
