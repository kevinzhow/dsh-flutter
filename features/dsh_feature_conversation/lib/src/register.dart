import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart' show DshRightbarHost;
import 'package:flutter/widgets.dart';

import 'desktop_header.dart';
import 'session_header.dart';
import 'shell.dart';
import 'todo_panel.dart';
import 'queue_dock.dart';
import 'submission_policy.dart';
import 'enter_settings.dart';
import 'user_text.dart';

/// Resolves a session id to its composer model (the app keeps them).
typedef ComposerInputLookup = ComposerInput? Function(String sessionId);

/// `conversation.session` as this feature uses it.
final Slot<SessionOwner, Widget> sessionSlot = DshSlots.conversationSession
    .typed<SessionOwner, Widget>();

/// `conversation.header` as this feature uses it.
final Slot<SessionOwner, Widget> headerSlot = DshSlots.conversationHeader
    .typed<SessionOwner, Widget>();

final Slot<SessionOwner, Widget> _viewSlot = DshSlots.conversationView
    .typed<SessionOwner, Widget>();
final Slot<SessionOwner, Widget> _composerSlot = DshSlots.conversationComposer
    .typed<SessionOwner, Widget>();

/// Occupy `conversation.session` (the shell) and `conversation.header` (title
/// and model indicator). The shell composes the view list and the composer
/// chain that other features fill.
///
/// With a [commandUi] registry the composer's `File` command joins the `/`
/// menu (dsh registers it through the same contribution API): a bare
/// invocation opens the attach picker of the mounted composer.
void registerConversationFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  CommandUiRegistry? commandUi,
  ComposerInputLookup? inputOf,
  WorkspaceServices? workspaces,
  ConversationPreferences? preferences,
  UserTextRegistry? userText,
  Map<String, Object?> Function(UserTextOwner)? userTextFacts,
  Stream<Object?>? userTextFactsChanges,
}) {
  if (userText != null) {
    registerUserTextFactory(
      slots,
      userText,
      additionalFacts: userTextFacts,
      factsChanges: userTextFactsChanges,
    );
  }
  if (commandUi != null && inputOf != null) {
    commandUi.register(
      CommandContribution(
        name: 'file',
        label: () => i18n().t('conversation', 'input.file'),
        icon: 'paperclip',
        available: (sessionId) => inputOf(sessionId)?.canPickFiles ?? false,
        ui: ActionSpec((sessionId) => inputOf(sessionId)?.pickFiles()),
      ),
    );
  }
  slots.register<SessionOwner, Widget>(
    sessionSlot,
    (owner) => ConversationShell(
      owner: owner,
      slots: slots,
      i18n: i18n(),
      viewSlot: _viewSlot,
      composerSlot: _composerSlot,
      dockSlot: DshSlots.conversationInputDock.typed<SessionOwner, Widget>(),
      workspaces: workspaces,
      preferences: preferences,
    ),
  );
  slots.register<SessionOwner, Widget>(
    DshSlots.conversationInputDock.typed<SessionOwner, Widget>(),
    (owner) => TodoDock(owner: owner, i18n: i18n()),
    id: 'todo',
    order: 0,
  );
  slots.register<SessionOwner, Widget>(
    DshSlots.conversationInputDock.typed<SessionOwner, Widget>(),
    (owner) => QueueDock(owner: owner, i18n: i18n(), slots: slots),
    id: 'queue',
    order: 20,
  );
  if (preferences != null) {
    slots.register<SettingsOwner, Widget>(
      DshSlots.settingsGeneralItem.typed<SettingsOwner, Widget>(),
      (_) => EnterBehaviorSettings(preferences: preferences, i18n: i18n()),
      id: 'composer-enter',
      order: 40,
    );
  }
  slots.register<SessionOwner, Widget>(
    headerSlot,
    // Inside the desktop frame the header is dsh's: crumb, utilities, corner
    // and view tabs; elsewhere it is the phone's title and model line.
    (owner) => Builder(
      builder: (context) => DshRightbarHost.owned(context)
          ? DesktopSessionHeader(owner: owner, i18n: i18n(), slots: slots)
          : SessionHeader(owner: owner, i18n: i18n(), slots: slots),
    ),
  );
}
