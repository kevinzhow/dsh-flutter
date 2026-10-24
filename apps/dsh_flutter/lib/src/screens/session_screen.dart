import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../app_controller.dart';
import '../session_controller.dart';
import 'connection_bar.dart';

/// One open session: the header slot with a back control (phones), and the
/// `conversation.session` slot below it.
class SessionView extends StatelessWidget {
  const SessionView({
    super.key,
    required this.controller,
    required this.session,
    this.onBack,
  });

  final AppController controller;
  final SessionController session;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
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
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DshSpace.xs,
              DshSpace.xs,
              DshSpace.lg,
              DshSpace.xs,
            ),
            child: Row(
              children: [
                if (onBack != null)
                  DshIconButton(
                    key: const ValueKey('session-back'),
                    icon: Icons.arrow_back,
                    plain: true,
                    semanticLabel: controller.i18n.t('common', 'back'),
                    onPressed: onBack,
                  )
                else
                  const SizedBox(width: DshSpace.md),
                Expanded(child: header ?? const SizedBox.shrink()),
              ],
            ),
          ),
        ),
        DshDecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.color('--dsw-alias-border-l4'),
                width: dshHairlineOf(context),
              ),
            ),
          ),
          child: const SizedBox(width: double.infinity),
        ),
        ConnectionBar(controller: controller),
        Expanded(
          child: SafeArea(top: false, child: body ?? const SizedBox.shrink()),
        ),
      ],
    );
  }
}
