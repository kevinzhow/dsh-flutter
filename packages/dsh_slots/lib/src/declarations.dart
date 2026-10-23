import 'slot.dart';

/// dsh's own slot names, declared with their shipped cardinality and scope
/// (docs/subsystems/slots.md "Conversation hierarchy" and the `SlotMap`
/// declarations in `packages/client/ui-*`). Only slots a Flutter feature
/// occupies are listed here; add a row when a ported `ui-*` package needs one.
///
/// The owner props type [P] is whatever the owning feature passes at the render
/// site; it is introduced by the feature that owns the slot, so the slot
/// constants here use `Object?` until that feature exists.
abstract final class DshSlots {
  /// The only built-in declaration.
  static const root = Slot<Object?, Object?>(
    'root',
    SlotCardinality.single,
    SlotScope.root,
  );

  static const conversationHeader = Slot<Object?, Object?>(
    'conversation.header',
    SlotCardinality.single,
    SlotScope.sessionMaybe,
  );
  static const conversationSession = Slot<Object?, Object?>(
    'conversation.session',
    SlotCardinality.single,
    SlotScope.session,
  );
  static const conversationView = Slot<Object?, Object?>(
    'conversation.view',
    SlotCardinality.list,
    SlotScope.session,
  );
  static const conversationComposer = Slot<Object?, Object?>(
    'conversation.composer',
    SlotCardinality.chain,
    SlotScope.session,
  );
  static const conversationSessionHeaderActions = Slot<Object?, Object?>(
    'conversation.session.header.actions',
    SlotCardinality.list,
    SlotScope.session,
  );
  static const conversationChatNode = Slot<Object?, Object?>(
    'conversation.chat.node',
    SlotCardinality.keyed,
    SlotScope.session,
  );
  static const toolCallToolview = Slot<Object?, Object?>(
    'tool.call.toolview',
    SlotCardinality.keyed,
    SlotScope.session,
  );

  static const all = <Slot<Object?, Object?>>[
    root,
    conversationHeader,
    conversationSession,
    conversationView,
    conversationComposer,
    conversationSessionHeaderActions,
    conversationChatNode,
    toolCallToolview,
  ];
}
