import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'chat_nodes.dart';
import 'chat_view.dart';
import 'chat_preferences.dart';
import 'work_details_view.dart';
import 'work_details_settings.dart';
import 'command_view.dart';
import 'command_input_view.dart';
import 'context_view.dart';
import 'compaction_view.dart';
import 'model_retry_view.dart';
import 'stats_pills.dart';
import 'system_prompt_view.dart';
import 'stream/reading_anchor.dart';

/// `conversation.view` as this feature uses it (owner: the open session).
final Slot<SessionOwner, Widget> viewSlot = DshSlots.conversationView
    .typed<SessionOwner, Widget>();

/// `conversation.chat.node` as this feature uses it.
final Slot<ChatNodeOwner, Widget> chatNodeSlot = DshSlots.conversationChatNode
    .typed<ChatNodeOwner, Widget>();

/// Occupy `conversation.view` with the chat and `conversation.chat.node` with
/// the node renderers this feature owns. `tool-call` is the tool feature's.
///
/// [host] is what a tapped link may open (the browser for http(s), the
/// workspace file preview for local paths); without it links stay inert.
ChatPreferences registerChatFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  ToolHostActions? host,
  ChatPreferences? preferences,
  WorkspaceManagement? management,
}) {
  final prefs = preferences ?? ChatPreferences();
  // Where each session's reader stopped, for as long as the app runs.
  final memory = ChatReadingMemory();
  slots.register<SessionOwner, Widget>(
    viewSlot,
    (owner) => ChatView(
      owner: owner,
      slots: slots,
      i18n: i18n(),
      memory: memory,
      nodeSlot: chatNodeSlot,
      preferences: prefs,
      turnTailSlot: DshSlots.conversationChatTurnTail
          .typed<TurnTailOwner, Widget?>(),
    ),
    id: 'chat',
    order: 0,
    label: () => i18n().t('chat', 'view.chat'),
  );

  slots.register<SettingsOwner, Widget>(
    DshSlots.settingsGeneralItem.typed<SettingsOwner, Widget>(),
    (_) => WorkDetailsSettings(preferences: prefs, i18n: i18n()),
    id: 'transcript-view',
    order: 30,
  );

  // The statistics pills under the composer (dsh `StatsPills`).
  for (final (id, order, activity) in [
    ('activity', 0, true),
    ('usage', 10, false),
  ]) {
    slots.register<SessionOwner, Widget>(
      DshSlots.conversationComposerDock.typed<SessionOwner, Widget>(),
      (owner) => StatsPill(owner: owner, i18n: i18n(), activity: activity),
      id: id,
      order: order,
    );
  }

  void node(
    String kind,
    Widget Function(ChatNodeOwner owner, DshI18n i18n) build,
  ) => slots.register<ChatNodeOwner, Widget>(
    chatNodeSlot,
    (owner) => build(owner, i18n()),
    key: kind,
  );

  /// Whether [o]'s node is the newest of [kinds] in the snapshot: those rows
  /// keep their actions visible, earlier ones reveal them on hover.
  bool newest(ChatNodeOwner o, Set<String> kinds) {
    final order = o.snapshot.order;
    for (var i = order.length - 1; i >= 0; i--) {
      final n = o.snapshot.nodes[order[i]];
      if (n != null && kinds.contains(n.kind)) return n.key == o.node.key;
    }
    return false;
  }

  node('system-prompt', (o, t) {
    final d = o.node.data as SystemPromptData;
    return SystemPromptView(text: d.text, update: d.update, i18n: t);
  });
  node(
    'turn-process',
    (o, t) => TurnProcessView(node: o.node, controls: o.turnProcess, i18n: t),
  );
  node(
    'command-input',
    (o, t) =>
        GoalCommandInputView(data: o.node.data as CommandInputData, i18n: t),
  );
  node(
    'context',
    (o, t) => ContextInjectionView(data: o.node.data as MessageData, i18n: t),
  );
  node('command', (o, t) {
    final data = o.node.data as CommandData;
    return slots.renderKeyed(
          DshSlots.conversationChatCommandview
              .typed<CommandViewOwner, Widget>(),
          data.name ?? '',
          CommandViewOwner(session: o.session, command: data),
        ) ??
        CommandView(data: data, i18n: t);
  });
  node(
    'compaction',
    (o, t) => CompactionView(
      data: o.node.data as CompactionData,
      i18n: t,
      host: host,
    ),
  );
  node(
    'manual-compaction',
    (o, t) => ManualCompactionView(
      data: o.node.data as ManualCompactionData,
      i18n: t,
      host: host,
    ),
  );
  const userKinds = {'user', 'steering'};
  node('user', (o, t) {
    final d = o.node.data as MessageData;
    final parts = d.parts;
    return UserBubble(
      text: parts.text,
      i18n: t,
      time: d.time,
      latest: newest(o, userKinds),
      attachments: attachmentViews(parts.attachments),
      referenceLabels: d.referenceLabels,
      owner: o.session,
      slots: slots,
    );
  });
  node('steering', (o, t) {
    final d = o.node.data as MessageData;
    final parts = d.parts;
    return UserBubble(
      text: parts.text,
      i18n: t,
      steering: true,
      time: d.time,
      latest: newest(o, userKinds),
      attachments: attachmentViews(parts.attachments),
      referenceLabels: d.referenceLabels,
      owner: o.session,
      slots: slots,
    );
  });
  node('turn-trigger', (o, t) {
    final d = o.node.data as MessageData;
    final kind = d.source?['kind'] as String?;
    final key = kind == null ? null : 'message.trigger.$kind';
    final text = key != null && t.has('chat', key)
        ? t.t('chat', key)
        : (d.producerLabel ?? t.t('chat', 'message.contextInjection'));
    return NoticeRow(text: text);
  });
  node(
    'assistant-step',
    (o, t) => AssistantStepView(
      data: o.node.data as AssistantData,
      nodeKey: o.node.key,
      i18n: t,
      owner: o.session,
      slots: slots,
      host: host,
      groupPart: o.groupPart,
      reasoningPreview: o.reasoningPreview,
    ),
  );
  node(
    'turn-tail',
    (o, t) => TurnTailView(
      data: o.node.data as TurnTailData,
      i18n: t,
      latest: newest(o, const {'turn-tail'}),
      branchUnavailable: o.snapshot
          .nodesOfTurn((o.node.data as TurnTailData).turn)
          .where(
            (n) => !const {
              'turn-tail',
              'turn-process',
              'turn-max-tokens',
            }.contains(n.kind),
          )
          .any(
            (n) =>
                n.anchorSeq >
                ((o.node.data as TurnTailData).closing?.finalNode?.seq ??
                    (o.node.data as TurnTailData).seq),
          ),
      onBranch: management == null || !o.session.queueMutable
          ? null
          : () async {
              await management.forkSession(
                o.session.sessionId,
                atSeq: (o.node.data as TurnTailData).seq.toInt(),
                open: true,
              );
            },
    ),
  );
  node(
    'model-retry',
    (o, t) => ModelRetryView(
      attempt: (o.node.data as ModelRetryData).current,
      i18n: t,
    ),
  );
  node(
    'turn-error',
    (o, t) => TurnErrorView(data: o.node.data as TurnErrorData, i18n: t),
  );
  node(
    'turn-max-tokens',
    (o, t) => NoticeRow(
      text: t.t(appNamespace, 'session.turn.maxTokens'),
      status: DshStatus.warn,
    ),
  );
  node('unknown', (o, t) {
    final d = o.node.data as UnknownData;
    return NoticeRow(text: '${t.t('common', 'unknown')}: ${d.type}');
  });
  return prefs;
}
