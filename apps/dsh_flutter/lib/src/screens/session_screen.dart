import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import '../app_controller.dart';
import '../session_controller.dart';

/// One open session inside the frame: the `conversation.header` slot over the
/// `conversation.session` slot. The header carries its own padding, rule and
/// controls (`DesktopSessionHeader`, or the phone top bar); the connection state
/// lives in the sidebar.
class SessionView extends StatelessWidget {
  const SessionView({
    super.key,
    required this.controller,
    required this.session,
  });

  final AppController controller;
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final owner = session.owner;
    final slots = controller.slots;
    final header = slots.renderSingle(
      DshSlots.conversationHeader.typed<SessionOwner, Widget>(),
      owner,
    );
    final body = slots.renderSingle(
      DshSlots.conversationSession.typed<SessionOwner, Widget>(),
      owner,
    );
    return Column(
      children: [
        header ?? const SizedBox.shrink(),
        Expanded(child: body ?? const SizedBox.shrink()),
      ],
    );
  }
}
