/// A durable inbox occurrence. Identity is the message id, never its text.
class InboxItem {
  const InboxItem(this.id, this.content, this.source);
  final String id;
  final List<Map<String, Object?>> content;
  final Map<String, Object?> source;

  String? get requestId =>
      source['kind'] == 'user' ? source['rpcId'] as String? : null;
  String get text => content
      .where((block) => block['type'] == 'text')
      .map((block) => block['text'] as String? ?? '')
      .join();
  bool get editable => content.every((block) => block['type'] == 'text');

  static InboxItem? tryParse(Object? value) {
    if (value is! Map<String, Object?> ||
        value['id'] is! String ||
        value['content'] is! List ||
        value['source'] is! Map<String, Object?>) {
      return null;
    }
    final source = value['source']! as Map<String, Object?>;
    if (source['rpcId'] != null && source['rpcId'] is! String) return null;
    final blocks = value['content']! as List;
    if (blocks.any(
      (b) =>
          b is! Map<String, Object?> ||
          (b['type'] == 'text' && b['text'] is! String),
    )) {
      return null;
    }
    return InboxItem(
      value['id']! as String,
      blocks.cast<Map<String, Object?>>(),
      source,
    );
  }
}

List<InboxItem> inboxItems(Object? projection, String target) => [
  if (projection is Map && projection[target] is List)
    for (final item in projection[target] as List)
      if (InboxItem.tryParse(item) case final row?) row,
];
