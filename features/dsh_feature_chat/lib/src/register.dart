import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'chat_nodes.dart';
import 'chat_view.dart';
import 'stats_pills.dart';
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
void registerChatFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  ToolHostActions? host,
}) {
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
      turnTailSlot: DshSlots.conversationChatTurnTail
          .typed<TurnTailOwner, Widget?>(),
    ),
    id: 'chat',
    order: 0,
    label: () => i18n().t('chat', 'view.chat'),
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
    ),
  );
  node(
    'turn-tail',
    (o, t) => TurnTailView(
      data: o.node.data as TurnTailData,
      i18n: t,
      latest: newest(o, const {'turn-tail'}),
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
}
