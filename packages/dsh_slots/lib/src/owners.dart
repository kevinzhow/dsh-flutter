import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';

/// Operations a session view can ask of the composition root. Features never
/// reach the connection themselves; they call these injected services.
abstract interface class SessionActions {
  /// Send a prompt (`session/prompt`); rejects when the host refuses it.
  Future<void> send(String text);

  /// Cancel the active turn (`session/cancel`).
  Future<void> cancel();

  /// Read one older page into the window.
  Future<void> loadOlder();
}

/// Owner props of the session-scoped slots (`conversation.session`,
/// `conversation.header`, `conversation.view`, `conversation.composer`, ...):
/// the one open session and what is derived from it. dsh declares these owner
/// types in the owning `ui-*` packages; here they live below the features so
/// no feature has to import another to fill a slot.
class SessionOwner {
  const SessionOwner({
    required this.session,
    required this.conversation,
    required this.actions,
  });

  final Session session;
  final ConversationBinding conversation;
  final SessionActions actions;

  String get sessionId => session.sessionId;
}

/// Owner props of the keyed `conversation.chat.node` slot: one chat node to
/// render, keyed by its kind (`user`, `assistant-step`, `tool-call`, ...).
class ChatNodeOwner {
  const ChatNodeOwner({
    required this.session,
    required this.node,
    required this.snapshot,
  });

  final SessionOwner session;
  final ViewNode node;
  final ChatSnapshot snapshot;
}

/// Owner props of the keyed `tool.call.toolview` slot: one tool call to render,
/// keyed by its wire tool name. Tool-specific views occupy it; the generic card
/// renders when no entry matches.
class ToolViewOwner {
  const ToolViewOwner({required this.session, required this.call});
  final SessionOwner session;
  final ToolCall call;
}
