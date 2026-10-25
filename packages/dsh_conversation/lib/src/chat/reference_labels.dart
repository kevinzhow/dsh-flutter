import '../contract.dart';
import 'nodes.dart';
import 'projection.dart';

/// Associate only a direct message with the sourced context at exactly seq+1.
/// Recall and message may arrive in either incremental batch order.
class ReferenceLabelProjector {
  final _messages = <num, String>{};
  final _labels = <num, List<String>>{};
  num? _messageSeq(ViewNode node) =>
      const {'user', 'steering'}.contains(node.kind)
      ? (node.data as MessageData).seq
      : null;
  (num, List<String>)? _recall(ViewNode node) => node.kind == 'context'
      ? (
          (node.data as MessageData).seq - 1,
          sessionRecallLabels((node.data as MessageData).source),
        )
      : null;
  List<ViewNode> replace(List<ViewNode> nodes) {
    _messages.clear();
    _labels.clear();
    for (final node in nodes) {
      final seq = _messageSeq(node);
      if (seq != null) _messages[seq] = node.key;
      final recall = _recall(node);
      if (recall != null && recall.$2.isNotEmpty) {
        _labels[recall.$1] = recall.$2;
      }
    }
    return [
      for (final node in nodes)
        if (_messageSeq(node) case final seq?)
          _withLabels(node, _labels[seq] ?? const [])
        else
          node,
    ];
  }

  List<ViewNode> apply(List<ViewNode> upserts, Map<String, ViewNode> store) {
    final byKey = {for (final node in upserts) node.key: node},
        affected = <num>{};
    for (final node in upserts) {
      final seq = _messageSeq(node);
      if (seq != null) {
        _messages[seq] = node.key;
        affected.add(seq);
      }
      final recall = _recall(node);
      if (recall == null) continue;
      final (messageSeq, labels) = recall;
      if (labels.isEmpty) {
        _labels.remove(messageSeq);
      } else {
        final old = _labels[messageSeq];
        _labels[messageSeq] = old != null && _same(old, labels) ? old : labels;
      }
      affected.add(messageSeq);
    }
    for (final seq in affected) {
      final key = _messages[seq];
      if (key == null) continue;
      final node = byKey[key] ?? store[key];
      if (node == null) continue;
      byKey[key] = _withLabels(node, _labels[seq] ?? const []);
    }
    return byKey.values.toList();
  }
}

ViewNode _withLabels(ViewNode node, List<String> labels) {
  final data = node.data as MessageData;
  if (_same(data.referenceLabels, labels)) return node;
  return ViewNode(
    key: node.key,
    kind: node.kind,
    id: node.id,
    target: node.target,
    anchorSeq: node.anchorSeq,
    location: node.location,
    visible: node.visible,
    groupTree: node.groupTree,
    data: data.withReferenceLabels(labels),
  );
}

bool _same(List<String> a, List<String> b) =>
    identical(a, b) ||
    a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
