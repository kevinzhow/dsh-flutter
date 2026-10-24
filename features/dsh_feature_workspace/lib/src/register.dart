import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'add_action.dart';
import 'workspace_picker.dart';

final Slot<HeroWorkspaceOwner, Widget> _hero = DshSlots
    .conversationHeroWorkspace
    .typed<HeroWorkspaceOwner, Widget>();
final Slot<DirectoryFlowOwner, Widget> _heroFlow = DshSlots
    .conversationHeroWorkspaceDirectoryFlow
    .typed<DirectoryFlowOwner, Widget>();
final Slot<SidebarWorkspacesOwner, Widget> _sidebar = DshSlots.sidebarWorkspaces
    .typed<SidebarWorkspacesOwner, Widget>();

/// Fill `conversation.hero.workspace` with the workspace picker and
/// `sidebar.workspaces` with the add-workspace action (dsh `ui-workspace`'s two
/// registrations; its session tree stays with the app's own list). Each owns a
/// directory-flow hole that a directory picker fills. Returns the disposer.
void Function() registerWorkspaceFeature(
  SlotRegistry slots, {
  required WorkspaceServices services,
  required DshI18n Function() i18n,
}) {
  final offs = <void Function()>[
    slots.register<HeroWorkspaceOwner, Widget>(
      _hero,
      (owner) => WorkspacePickFlow(
        key: const ValueKey('hero-workspace-flow'),
        services: services,
        slots: slots,
        flowSlot: _heroFlow,
        i18n: i18n(),
        open: owner.open,
        anchor: owner.anchor is LayerLink ? owner.anchor! as LayerLink : null,
        selectedId: owner.selectedId,
        onPick: owner.onPick,
        onClose: owner.onClose,
      ),
    ),
    slots.register<SidebarWorkspacesOwner, Widget>(
      _sidebar,
      (owner) => WorkspaceAddAction(
        key: const ValueKey('sidebar-workspace-add'),
        owner: owner,
        services: services,
        slots: slots,
        i18n: i18n(),
      ),
    ),
  ];
  return () {
    for (final off in offs) {
      off();
    }
  };
}
