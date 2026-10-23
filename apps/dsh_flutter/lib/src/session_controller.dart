import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';

/// One open session: the model [Session], its conversation binding, and the
/// operations features may call. The app keeps one per session id while it is
/// resident, like dsh's `SessionManager` keeps its sessions.
class SessionController implements SessionActions {
  SessionController(
    this.session, {
    FlushScheduler? scheduler,
    String? Function()? cwdReader,
    String hostHome = '',
    this.readOnly = false,
  }) : conversation = ConversationBinding.chat(
         session.eventSource,
         scheduler: scheduler,
       ) {
    owner = SessionOwner(
      session: session,
      conversation: conversation,
      actions: this,
      cwdReader: cwdReader,
      hostHome: hostHome,
    );
  }

  /// A subagent transcript: nothing can be sent or cancelled.
  final bool readOnly;

  final Session session;
  final ConversationBinding conversation;
  late final SessionOwner owner;

  String get sessionId => session.sessionId;

  /// Start following the session (single flight).
  Future<void> open() => session.open();

  @override
  Future<void> send(String text) =>
      readOnly ? Future.value() : session.prompt(text.trim());

  @override
  Future<void> cancel() => readOnly ? Future.value() : session.cancel();

  @override
  Future<void> loadOlder() => session.loadOlder();

  Future<void> dispose() async {
    await conversation.dispose();
  }
}
