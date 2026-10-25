import '../contract.dart';
import '../registry.dart';
import '../plan/submitted_plan.dart';
import '../tool/todo_history.dart';
import 'definitions.dart';
import 'commands.dart';
import 'nodes.dart';
import 'retry.dart';
import 'system_prompt.dart';

/// The immutable chat target snapshot (dsh `ChatSnapshot`, without the legacy
/// slice, navigation rail and process-group presentation, which are deferred).
class ChatSnapshot {
  const ChatSnapshot({
    required this.order,
    required this.nodes,
    required this.timeline,
  });

  static const empty = ChatSnapshot(
    order: [],
    nodes: {},
    timeline: ConversationTimeline.empty,
  );

  /// Visible node keys in presentation order.
  final List<String> order;

  /// Every materialized node by key, including hidden ones.
  final Map<String, ViewNode> nodes;
  final ConversationTimeline timeline;

  ViewNode? node(String key) => nodes[key];

  /// Visible nodes in presentation order.
  List<ViewNode> get visibleNodes => [for (final k in order) nodes[k]!];

  /// Visible nodes of one turn, in order.
  List<ViewNode> nodesOfTurn(int turn) => [
    for (final n in visibleNodes)
      if (locationTurn(n.location) == turn) n,
  ];

  /// The data of every node of [kind] in one turn (hidden nodes included), in
  /// anchor order: dsh's `turnDataSource(turn, kind)` read.
  List<T> turnData<T>(int turn, String kind) {
    final found = [
      for (final n in nodes.values)
        if (n.kind == kind && locationTurn(n.location) == turn) n,
    ]..sort((a, b) => a.anchorSeq.compareTo(b.anchorSeq));
    return [for (final n in found) n.data as T];
  }

  /// The submitted plans of one turn, in invocation order.
  List<SubmittedPlan> plansOfTurn(int turn) =>
      turnData<SubmittedPlan>(turn, submittedPlanKind);

  /// Whether any visible row exists (dsh `chatViewDefinition.isActive`).
  bool get isActive => order.isNotEmpty;
}

/// dsh `isVisibleChatNode`: system prompts and ordinary context are not rows.
bool isVisibleChatNode(ViewNode n) {
  if (!n.visible || n.kind == 'system-prompt') return false;
  if (n.kind == 'context') {
    final data = n.data as MessageData;
    return data.content.any(
      (b) =>
          b is Map &&
          (b['type'] == 'tool-addition' || b['type'] == 'tool-removal'),
    );
  }
  return true;
}

/// Order visible chat nodes by anchor, then by key (dsh
/// `orderedVisibleChatNodes` without turn-process controls).
List<ViewNode> orderedVisibleChatNodes(Iterable<ViewNode> nodes) {
  final visible = nodes.where(isVisibleChatNode).toList();
  visible.sort((a, b) {
    final byAnchor = a.anchorSeq.compareTo(b.anchorSeq);
    if (byAnchor != 0) return byAnchor;
    return localeCompare(a.key, b.key);
  });
  return visible;
}

const _punctuationOrder = "_-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~\$";

(int, int) _primary(String ch) {
  final lower = ch.toLowerCase();
  final code = lower.codeUnitAt(0);
  if (code >= 0x30 && code <= 0x39) return (2, code);
  if ((code >= 0x61 && code <= 0x7a) || code > 0x7f) return (3, code);
  final p = _punctuationOrder.indexOf(ch);
  return (1, p < 0 ? 100 + code : p);
}

/// ICU-root-like `String.prototype.localeCompare` for the ASCII keys the
/// engine builds: punctuation, then digits, then letters (case-insensitive,
/// lowercase first on ties).
int localeCompare(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final pa = _primary(a[i]);
    final pb = _primary(b[i]);
    if (pa.$1 != pb.$1) return pa.$1.compareTo(pb.$1);
    if (pa.$2 != pb.$2) return pa.$2.compareTo(pb.$2);
  }
  if (a.length != b.length) return a.length.compareTo(b.length);
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) {
      final aLower = a[i] == a[i].toLowerCase();
      return aLower ? -1 : 1;
    }
  }
  return 0;
}

class ChatSnapshotBuilder extends ConversationViewBuilder {
  final Map<String, ViewNode> _byKey = {};
  ChatSnapshot _snapshot = ChatSnapshot.empty;

  @override
  ChatSnapshot replace(List<ViewNode> nodes, ConversationTimeline timeline) {
    _byKey
      ..clear()
      ..addEntries(nodes.map((n) => MapEntry(n.key, n)));
    return _publish(timeline);
  }

  @override
  ChatSnapshot apply(List<ViewNode> upserts, ConversationTimeline timeline) {
    for (final n in upserts) {
      _byKey[n.key] = n;
    }
    return _publish(timeline);
  }

  ChatSnapshot _publish(ConversationTimeline timeline) {
    final order = [
      for (final n in orderedVisibleChatNodes(_byKey.values)) n.key,
    ];
    return _snapshot = ChatSnapshot(
      order: order,
      nodes: Map.unmodifiable(_byKey),
      timeline: timeline,
    );
  }

  ChatSnapshot get current => _snapshot;
}

/// The Chat target factory contributed to the view registry (dsh
/// `chatViewDefinition`).
class ChatViewDefinition extends ConversationViewDefinition {
  @override
  String get target => chatTarget;
  @override
  ConversationViewBuilder create() => ChatSnapshotBuilder();
  @override
  bool isActive(Object snapshot) => (snapshot as ChatSnapshot).isActive;
}

/// The event and view registries with the ported chat Definitions installed
/// (the subset of dsh `registerConversationNodes` that 1a ports).
({ConversationEventRegistry events, ConversationViewRegistry views})
defaultChatRegistries() {
  final events = ConversationEventRegistry()
    ..register(InboxDefinition('next-step'))
    ..register(InboxDefinition('next-turn'))
    ..register(const MessageDefinition())
    ..register(const MessageDefinition(developer: true))
    ..register(const SystemMessageDefinition())
    ..register(const RequestPromptDefinition())
    ..register(const AssistantDefinition())
    ..register(const ToolDefinition())
    ..register(const CommandDefinition())
    ..register(const CompactionDefinition())
    ..register(const ModelRetryDefinition())
    ..register(const TurnErrorDefinition())
    ..register(const TurnMaxTokensDefinition())
    ..register(const TurnTailDefinition())
    ..register(const SubmittedPlanDefinition())
    ..register(const TodoWriteDefinition())
    ..register(const TodoCallDefinition())
    ..registerFallback(const UnknownSurfaceDefinition());
  final views = ConversationViewRegistry()
    ..register(ChatViewDefinition())
    ..register(TodoHistoryViewDefinition());
  return (events: events, views: views);
}
