/// A conversation target: one registered way of materializing a session event
/// window into display nodes (dsh `chat`, `trajectory`, ...).
typedef ConversationTarget = String;

const ConversationTarget chatTarget = 'chat';
const ConversationTarget trajectoryTarget = 'trajectory';

/// A display node of a target snapshot, keyed like dsh's
/// `ConversationNodeDefinition` keys (`user`, `assistant-step`, `tool-call`,
/// `command`, ...) so a slot (`conversation.chat.node`, keyed) can dispatch to
/// the renderer registered for that key.
class ConversationNode {
  const ConversationNode({
    required this.key,
    required this.id,
    required this.firstSeq,
    required this.lastSeq,
    this.data = const {},
    this.streaming = false,
  });

  /// Dispatch key, e.g. `user`, `assistant-step`, `tool-call`.
  final String key;

  /// Stable identity within the snapshot (correlation by `(kind, id)`).
  final String id;
  final num firstSeq;
  final num lastSeq;

  /// Target-owned payload (kept as JSON for the skeleton).
  final Map<String, Object?> data;

  /// Built from transient `assistant/live-chunk` rows, not yet settled.
  final bool streaming;
}

/// A target's materialized view of one window.
class ConversationSnapshot {
  const ConversationSnapshot(this.target, this.nodes);
  final ConversationTarget target;
  final List<ConversationNode> nodes;
}
