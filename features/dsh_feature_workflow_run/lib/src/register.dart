import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'workflow_run_panel.dart';

abstract interface class WorkflowRunServices {
  Stream<Object?> get changes;

  /// Current list facts must prove a running direct child with subagent identity.
  bool canOpen(SessionOwner parent, String childId);
  void open(SessionOwner parent, WorkflowRunMember member);
}

void registerWorkflowRunFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  required WorkflowRunServices services,
}) {
  slots.register<ChatNodeOwner, Widget>(
    DshSlots.conversationChatNode.typed<ChatNodeOwner, Widget>(),
    (owner) => StreamBuilder<Object?>(
      stream: services.changes,
      builder: (context, _) => WorkflowRunPanel(
        data: owner.node.data as WorkflowRunData,
        i18n: i18n(),
        canOpen: (member) =>
            member.status == WorkflowRunStatus.running &&
            services.canOpen(owner.session, member.childId),
        onOpen: (member) {
          if (services.canOpen(owner.session, member.childId)) {
            services.open(owner.session, member);
          }
        },
      ),
    ),
    key: 'workflow-run',
  );
}
