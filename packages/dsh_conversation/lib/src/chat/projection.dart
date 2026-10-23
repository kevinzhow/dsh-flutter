import '../contract.dart';
import '../event.dart';
import 'nodes.dart';

/// Chat-owned conversion from durable Session events to chat view data (dsh
/// `ui-chat/conversation-nodes/event-projection.ts`).

Map<String, Object?>? asRecord(Object? v) =>
    v is Map<String, Object?> ? v : null;

String? _readString(Map<String, Object?> r, String key) {
  final v = r[key];
  return v is String && v.isNotEmpty ? v : null;
}

List<String> _collect(
  Map<String, Object?> source,
  String member,
  String field,
) {
  final list = source[member];
  if (list is! List) return const [];
  final seen = <String>[];
  for (final entry in list) {
    final rec = asRecord(entry);
    final value = rec == null ? null : _readString(rec, field);
    if (value != null && !seen.contains(value)) seen.add(value);
  }
  return seen;
}

String? _joined(List<String> names) => names.isEmpty ? null : names.join(', ');

const _knownForms = {
  'instructions',
  'catalog',
  'snapshot',
  'notice',
  'relay',
  'recall',
};

/// The presentation form of a durable message source, null when opaque.
String? contextForm(Object? source) {
  final rec = asRecord(source);
  final form = rec == null ? null : _readString(rec, 'form');
  return form != null && _knownForms.contains(form) ? form : null;
}

/// Role and label of a context row's producer.
({String role, String? label}) contextProducer(Object? source) {
  final rec = asRecord(source);
  final kind = rec == null ? null : _readString(rec, 'kind');
  if (rec == null || kind == null) return (role: 'inject', label: null);
  switch (kind) {
    case 'session-reference':
      return (
        role: 'recall',
        label: _joined(_collect(rec, 'references', 'label')) ?? kind,
      );
    case 'agent-instructions':
      return (
        role: 'inject',
        label: _joined(_collect(rec, 'changes', 'path')) ?? kind,
      );
    case 'skill-invocation':
      return (role: 'inject', label: _readString(rec, 'name') ?? kind);
    default:
      return (role: 'inject', label: kind);
  }
}

List<AssistantBlock> toAssistantBlocks(Object? content) => [
  if (content is List)
    for (final b in content) toAssistantBlock(b),
];

AssistantBlock toAssistantBlock(Object? block) {
  final b = asRecord(block);
  switch (b?['type']) {
    case 'text':
      return TextBlock('${b!['text']}');
    case 'reasoning':
      return ReasoningBlock('${b!['text']}');
    case 'image':
      return ImageBlock(b!['attachment']);
    case 'tool-call':
      return ToolCallRefBlock(
        callId: '${b!['id']}',
        name: '${b['name']}',
        argsRaw: '${b['arguments']}',
      );
    default:
      return OtherBlock(block);
  }
}

AssistantBlock emptyAssistantBlock(Object? blockType) => switch (blockType) {
  'text' => const TextBlock(''),
  'reasoning' => const ReasoningBlock(''),
  'tool-call' => const ToolCallRefBlock(callId: '', name: '', argsRaw: ''),
  _ => const OtherBlock(null),
};

/// Locale-independent failure fields safe for chat (dsh `displayFailure`).
({String? code, String message}) displayFailure(Object? failure) {
  final rec = asRecord(failure);
  if (rec == null) return (code: null, message: '$failure');
  final code = rec['code'] is String ? rec['code'] as String : null;
  if (code == 'AUTH') return (code: code, message: '');
  final message = rec['message'];
  return (code: code, message: message is String ? message : _jsonish(failure));
}

String _jsonish(Object? v) => '$v';

/// Whether a stream chunk carries visible model output (dsh `isTokenDelta`).
bool isTokenDelta(Map<String, Object?> chunk) => switch (chunk['type']) {
  'text-delta' || 'reasoning-delta' => chunk['text'] != '',
  'tool-call-delta' =>
    (chunk['argumentsDelta'] ?? '') != '' || chunk['name'] != null,
  _ => false,
};

/// JavaScript `String(value)` of a payload field: a missing field reads
/// "undefined", an integral number prints without a fraction.
String jsString(Map<String, Object?> data, String key) {
  if (!data.containsKey(key)) return 'undefined';
  final v = data[key];
  if (v == null) return 'null';
  if (v is num) return seqText(v);
  return '$v';
}

/// The `{seq, time}` of the closing boundary of a location, if its step or
/// turn is closed (dsh `closedBoundary`).
({num seq, num time})? closedBoundary(ConversationLocation location) {
  if (location is StepScopedLocation &&
      location.step.status == BoundaryStatus.closed &&
      location.step.end != null) {
    final e = location.step.end!;
    return (seq: e.seq, time: e.time);
  }
  final turn = switch (location) {
    StepScopedLocation(:final turn) => turn,
    TurnScopedLocation(:final turn) => turn,
    _ => null,
  };
  if (turn != null &&
      turn.status == BoundaryStatus.closed &&
      turn.end != null) {
    return (seq: turn.end!.seq, time: turn.end!.time);
  }
  return null;
}
