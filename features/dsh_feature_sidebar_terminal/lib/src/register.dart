import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'terminal_body.dart';
import 'terminal_guide.dart';
import 'terminal_title.dart';

/// The tab kind this feature owns.
const String terminalTabKind = 'terminal';

/// Declare the `terminal` tab type (independent instances, a card on the guide,
/// background cleanup on close) and occupy `sidebar.right.pane.tab[terminal]`,
/// its title and its guide card.
void registerSidebarTerminalFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  required ClientTerminals terminals,
}) {
  slots.sidebarTabs.register(
    SidebarTabType(
      kind: terminalTabKind,
      multiple: true,
      restorable: true,
      persistParams: (params) {
        final id = params['terminalId'];
        return id is String && id.isNotEmpty ? {'terminalId': id} : null;
      },
      guideOrder: 20,
      keepMounted: true,
      onClose: (sessionId, tabId, contentId) =>
          terminals.close(sessionId, tabId),
    ),
  );
  slots.register<SidebarTabOwner, Widget>(
    DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
    (owner) => TerminalBody(owner: owner, terminals: terminals, i18n: i18n()),
    key: terminalTabKind,
  );
  slots.register<SidebarTabOwner, Widget>(
    DshSlots.sidebarRightPaneTabTitle.typed<SidebarTabOwner, Widget>(),
    (owner) => TerminalTitle(owner: owner, terminals: terminals, i18n: i18n()),
    key: terminalTabKind,
  );
  slots.register<SidebarGuideOwner, Widget>(
    DshSlots.sidebarRightTabGuideEntry.typed<SidebarGuideOwner, Widget>(),
    (owner) =>
        TerminalGuideCard(owner: owner, terminals: terminals, i18n: i18n()),
    key: terminalTabKind,
  );
}
