import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// Standard menu and hover actions are ordinary ordered contributions.
/// [shortcutOf] supplies current effective bindings; null means unbound.
void registerSessionRowFeatures(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  DshMenuShortcut? Function(String commandId)? shortcutOf,
}) {
  for (final (id, order) in [
    ('pin', 100),
    ('rename', 200),
    ('fork', 300),
    ('archive', 400),
    ('copy', 1000),
  ]) {
    slots.register<SessionRowOwner, DshMenuEntry?>(
      DshSlots.sidebarWorkspacesSessionMenuItem
          .typed<SessionRowOwner, DshMenuEntry?>(),
      (owner) {
        if (id == 'pin' && owner.archived) return null;
        final key = switch (id) {
          'pin' => owner.pinned ? 'menu.unpinSession' : 'menu.pinSession',
          'rename' => 'rename',
          'fork' => 'menu.fork',
          'archive' =>
            owner.archived ? 'menu.unarchiveSession' : 'menu.archiveSession',
          _ => 'menu.sessionId',
        };
        final icon = switch (id) {
          'pin' =>
            owner.pinned ? DshShellIcons.pinFill : DshShellIcons.pinOutline,
          'rename' => DshShellIcons.editOutline,
          'fork' => DshIcons.branch,
          'archive' =>
            owner.archived ? DshShellIcons.unarchive : DshShellIcons.archive,
          _ => DshShellIcons.copyOutline,
        };
        final command = switch (id) {
          'rename' => 'session.rename',
          'fork' => 'session.fork',
          'archive' when !owner.archived => 'session.archive',
          _ => null,
        };
        return DshMenuItem(
          id,
          i18n().t('workspace', key),
          icon: icon,
          shortcut: command == null ? null : shortcutOf?.call(command),
          onSelect: () => owner.onAction(id),
        );
      },
      id: id,
      order: order,
    );
  }
  for (final (id, order) in [('archive', 100), ('pin', 200)]) {
    slots.register<SessionRowOwner, Widget?>(
      DshSlots.sidebarWorkspacesSessionRowAction
          .typed<SessionRowOwner, Widget?>(),
      (owner) {
        if (id == 'pin' && owner.archived) return null;
        final key = id == 'pin'
            ? (owner.pinned ? 'menu.unpinSession' : 'menu.pinSession')
            : (owner.archived
                  ? 'menu.unarchiveSession'
                  : 'menu.archiveSession');
        return Builder(
          builder: (context) => DshTooltip(
            label: i18n().t('workspace', key),
            side: DshTooltipSide.bottom,
            delay: const Duration(milliseconds: 500),
            child: Semantics(
              button: true,
              label: i18n().t('workspace', key),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => owner.onAction(id),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: Center(
                    child: DshIcon(
                      id == 'pin'
                          ? (owner.pinned
                                ? DshShellIcons.pinFill
                                : DshShellIcons.pinOutline)
                          : (owner.archived
                                ? DshShellIcons.unarchive
                                : DshShellIcons.archive),
                      size: 14,
                      color: context.dsh.color('--dsw-alias-label-tertiary'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      id: id,
      order: order,
    );
  }
}
