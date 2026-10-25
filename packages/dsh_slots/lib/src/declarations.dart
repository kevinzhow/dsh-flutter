import 'shell_slots.dart';
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

  /// Controls after the actions in the Session header's title row (dsh
  /// `ui-conversation`; open-in-app, the Session overflow menu).
  static const conversationSessionHeaderUtilities = Slot<Object?, Object?>(
    'conversation.session.header.utilities',
    SlotCardinality.list,
    SlotScope.session,
  );

  /// The header's corner seat, past the utilities (dsh: the right sidebar's
  /// way back in).
  static const conversationSessionHeaderCorner = Slot<Object?, Object?>(
    'conversation.session.header.corner',
    SlotCardinality.single,
    SlotScope.session,
  );

  /// The pills under the composer card (dsh `conversation.composer.dock`;
  /// `ui-chat` fills it with the session statistics).
  static const conversationComposerDock = Slot<Object?, Object?>(
    'conversation.composer.dock',
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
  static const conversationChatCommandview = Slot<Object?, Object?>(
    'conversation.chat.commandview',
    SlotCardinality.keyed,
    SlotScope.session,
  );

  static const conversationInputDock = Slot<Object?, Object?>(
    'conversation.input.dock',
    SlotCardinality.list,
    SlotScope.session,
  );
  static const conversationChatTurnTail = Slot<Object?, Object?>(
    'conversation.chat.turnTail',
    SlotCardinality.list,
    SlotScope.session,
  );

  /// The draft-attachment rail above the composer (dsh `ui-attachment`).
  static const conversationInputAttachments = Slot<Object?, Object?>(
    'conversation.input.attachments',
    SlotCardinality.single,
    SlotScope.sessionMaybe,
  );

  /// Image groups of a user message, an assistant message and a tool result
  /// (dsh `ui-chat`, `ui-tool`; filled by the attachment feature).
  static const conversationChatUserImages = Slot<Object?, Object?>(
    'conversation.chat.user.images',
    SlotCardinality.single,
    SlotScope.session,
  );
  static const conversationChatMessageImages = Slot<Object?, Object?>(
    'conversation.chat.message.images',
    SlotCardinality.single,
    SlotScope.session,
  );
  static const toolCallImages = Slot<Object?, Object?>(
    'tool.call.images',
    SlotCardinality.single,
    SlotScope.session,
  );

  /// The right sidebar of a session (dsh `ui-sidebar-right`): its content as a
  /// panel, and one tab's body keyed by tab kind.
  static const rightbarSession = Slot<Object?, Object?>(
    'rightbar.session',
    SlotCardinality.single,
    SlotScope.session,
  );
  static const sidebarRightPaneTab = Slot<Object?, Object?>(
    'sidebar.right.pane.tab',
    SlotCardinality.keyed,
    SlotScope.session,
  );

  /// A tab's title as its chip shows it (dsh `ui-sidebar-right`), keyed by tab
  /// kind like the body; a type without one shows the chip's captured text.
  static const sidebarRightPaneTabTitle = Slot<Object?, Object?>(
    'sidebar.right.pane.tab.title',
    SlotCardinality.keyed,
    SlotScope.session,
  );

  /// One provider's card on the guide page (dsh `ui-sidebar-right`), keyed by
  /// tab kind; the sidebar draws the standard card when none occupies it.
  static const sidebarRightTabGuideEntry = Slot<Object?, Object?>(
    'sidebar.right.tab.guide.entry',
    SlotCardinality.keyed,
    SlotScope.session,
  );

  /// One settings page (dsh `ui-settings`): `id` keys the page, `order` and
  /// `label` its place and name in the navigation. The shell is
  /// `dsh_feature_settings` (dsh `ui-settings-general`).
  static const settingsSection = Slot<Object?, Object?>(
    'settings.section',
    SlotCardinality.list,
    SlotScope.root,
  );

  /// One preference row of the General section (dsh `ui-settings`): the
  /// owner passes nothing, a row draws its own label and write path.
  static const settingsGeneralItem = Slot<Object?, Object?>(
    'settings.general.item',
    SlotCardinality.list,
    SlotScope.root,
  );

  /// One official plugin's configuration card on the plugins page (dsh
  /// `ui-plugin-manager`); filled by the `ui-settings-*` plugin pages.
  static const pluginsItem = Slot<Object?, Object?>(
    'plugins.item',
    SlotCardinality.list,
    SlotScope.root,
  );

  /// The composer's current-session permission control and model selector
  /// (dsh `ui-conversation`; filled by `ui-permission-presets` and
  /// `ui-model-selection`).
  static const conversationInputPermission = Slot<Object?, Object?>(
    'conversation.input.permission',
    SlotCardinality.single,
    SlotScope.session,
  );
  static const conversationInputModel = Slot<Object?, Object?>(
    'conversation.input.model',
    SlotCardinality.single,
    SlotScope.session,
  );

  /// Floating entries rendered above the composer card (dsh `ui-conversation`;
  /// filled by `ui-input-trigger` (the candidate menu) and `ui-commands` (the
  /// command popup)).
  static const conversationInputOverlay = Slot<Object?, Object?>(
    'conversation.input.overlay',
    SlotCardinality.list,
    SlotScope.session,
  );

  /// The workspace picker of the blank-session hero (dsh `ui-conversation`;
  /// filled by `ui-workspace`), and the hole under it that a directory picker
  /// fills (`ui-directory-picker-browse`).
  static const conversationHeroWorkspace = Slot<Object?, Object?>(
    'conversation.hero.workspace',
    SlotCardinality.single,
    SlotScope.root,
  );
  static const conversationHeroWorkspaceDirectoryFlow = Slot<Object?, Object?>(
    'conversation.hero.workspace.directoryFlow',
    SlotCardinality.single,
    SlotScope.root,
  );

  /// The workspace region of the session list (dsh `ui-sidebar` hole filled by
  /// `ui-workspace`) and the directory-flow hole of its add action.
  static const sidebarWorkspaces = Slot<Object?, Object?>(
    'sidebar.workspaces',
    SlotCardinality.single,
    SlotScope.root,
  );
  static const sidebarWorkspacesDirectoryFlow = Slot<Object?, Object?>(
    'sidebar.workspaces.directoryFlow',
    SlotCardinality.single,
    SlotScope.root,
  );

  static const all = <Slot<Object?, Object?>>[
    root,
    conversationHeader,
    conversationSession,
    conversationView,
    conversationComposer,
    conversationSessionHeaderActions,
    conversationSessionHeaderUtilities,
    conversationSessionHeaderCorner,
    conversationComposerDock,
    conversationChatNode,
    conversationChatCommandview,
    toolCallToolview,
    conversationInputDock,
    conversationChatTurnTail,
    conversationInputAttachments,
    conversationChatUserImages,
    conversationChatMessageImages,
    toolCallImages,
    rightbarSession,
    sidebarRightPaneTab,
    sidebarRightPaneTabTitle,
    sidebarRightTabGuideEntry,
    settingsSection,
    settingsGeneralItem,
    pluginsItem,
    conversationInputPermission,
    conversationInputModel,
    conversationInputOverlay,
    conversationHeroWorkspace,
    conversationHeroWorkspaceDirectoryFlow,
    sidebarWorkspaces,
    sidebarWorkspacesDirectoryFlow,
    ...DshShellSlots.all,
  ];
}
