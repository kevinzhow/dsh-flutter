/// Test support for features: a [SessionOwner] over an in-memory session.
/// Import only from tests.
library;

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';

import 'dsh_slots.dart';

export 'package:dsh_models/testing.dart' show FakeTransport;

/// Recording [SessionActions] for tests.
class FakeActions implements SessionActions {
  final List<String> sent = [];
  int cancels = 0;
  int olderLoads = 0;
  Object? failSend;

  @override
  Future<void> send(String text) async {
    if (failSend != null) throw failSend!;
    sent.add(text);
  }

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<void> loadOlder() async => olderLoads++;
}

/// An owner over a Session that never talks to a host. Feed it events through
/// `owner.session.eventSource` (replace/append/...); the chat snapshot follows
/// synchronously.
SessionOwner testSessionOwner(
  String sessionId, {
  SessionActions? actions,
  Session? session,
}) {
  final s = session ?? Session(sessionId, FakeTransport());
  return SessionOwner(
    session: s,
    conversation: ConversationBinding.chat(
      s.eventSource,
      scheduler: FlushScheduler.immediate(),
    ),
    actions: actions ?? FakeActions(),
  );
}
