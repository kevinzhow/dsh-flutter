import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../app_controller.dart';
import 'connection_bar.dart';

/// The New session screen before a workspace is chosen (dsh's sessionless
/// conversation area): the headline, the "Choose workspace" chip and an inert
/// composer. Picking a workspace opens its blank session and the screen gives
/// way to it. A phone reaches it from "+" when there is no workspace to
/// default to; a wide window shows it in the detail pane.
class NewSessionView extends StatelessWidget {
  const NewSessionView({super.key, required this.controller, this.onBack});

  final AppController controller;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final i18n = controller.i18n;
    return Column(
      key: const ValueKey('new-session'),
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
                    semanticLabel: i18n.t('common', 'back'),
                    onPressed: onBack,
                  )
                else
                  const SizedBox(width: DshSpace.md, height: DshSpace.touch),
              ],
            ),
          ),
        ),
        ConnectionBar(controller: controller),
        Expanded(
          child: SafeArea(
            top: false,
            child: ConversationHero(
              owner: null,
              slots: controller.slots,
              i18n: i18n,
              workspaces: controller.workspaceServices,
            ),
          ),
        ),
      ],
    );
  }
}
