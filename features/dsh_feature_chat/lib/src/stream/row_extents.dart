import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// Ported from raft-flutter `apps/raft_flutter/lib/features/row_extents.dart`
// (measured-height cache feeding the timeline's total-extent estimate, and
// the recorder that fills it). The content guess is rewritten for dsh chat
// nodes instead of Raft message JSON.

/// Last measured (width, height) of chat rows by row id. The timeline seeds
/// its extent index from these, so the scroll range (and the scrollbar thumb)
/// is stable when a session is reopened or the list is rebuilt.
class RowExtents {
  RowExtents({this.limit = 4000});

  final int limit;
  final _measured = <String, (double, double)>{};

  int get length => _measured.length;

  void record(String id, double width, double height) {
    if (_measured.length >= limit && !_measured.containsKey(id)) {
      _measured.remove(_measured.keys.first);
    }
    _measured[id] = (width, height);
  }

  /// The measured height at (about) [width], else null.
  double? measured(String id, double width) {
    final m = _measured[id];
    return m != null && (m.$1 - width).abs() < 1 ? m.$2 : null;
  }
}

/// Rough rendered height of a row before it is laid out; only a first guess
/// for the total extent, measured heights replace it.
double guessNodeExtent(ViewNode node, double width) {
  final text = switch (node.data) {
    MessageData(:final content) => _contentText(content),
    AssistantData(:final blocks) => [
      for (final b in blocks)
        if (b is TextBlock) b.text,
    ].join('\n'),
    _ => null,
  };
  final textWidth = (width - 64).clamp(120.0, 2000.0);
  double lines(String value, double unit) {
    var total = 0.0;
    for (final line in value.split('\n')) {
      var w = 0.0;
      for (final rune in line.runes) {
        w += rune > 0x2e80 ? unit * 1.9 : unit;
      }
      total += (w / textWidth).ceil().clamp(1, 1000);
    }
    return total;
  }

  return switch (node.kind) {
    'user' || 'steering' => 40 + 24 * lines(text ?? '', 8),
    'assistant-step' => 8 + 24 * lines(text ?? '', 8),
    'tool-call' => 44,
    'turn-tail' => 36,
    'turn-error' => 72,
    _ => 28,
  };
}

String _contentText(List<Object?> content) => [
  for (final part in content)
    if (part is Map && part['type'] == 'text') '${part['text'] ?? ''}',
].join('\n');

/// Records its child's laid-out size without rebuilding anything.
class RowExtentRecorder extends SingleChildRenderObjectWidget {
  const RowExtentRecorder({
    super.key,
    required this.extents,
    required this.id,
    required super.child,
  });

  final RowExtents extents;
  final String id;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRowExtentRecorder(extents, id);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderRowExtentRecorder)
        ..extents = extents
        ..id = id;
}

class _RenderRowExtentRecorder extends RenderProxyBox {
  _RenderRowExtentRecorder(this.extents, this.id);
  RowExtents extents;
  String id;

  @override
  void performLayout() {
    super.performLayout();
    extents.record(id, size.width, size.height);
  }
}
