import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'files_view.dart';

/// The tab kind this feature owns.
const String filesTabKind = 'files';

/// Declare the `files` tab type, occupy `sidebar.right.pane.tab[files]` with the
/// workspace file tree and `sidebar.right.tab.guide.entry[files]` with its card
/// on the guide page.
void registerFilesFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
}) {
  slots.sidebarTabs.register(
    const SidebarTabType(kind: filesTabKind, guideOrder: 10),
  );
  slots.register<SidebarTabOwner, Widget>(
    DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
    (owner) => FilesView(owner: owner, i18n: i18n()),
    key: filesTabKind,
  );
  slots.register<SidebarGuideOwner, Widget>(
    DshSlots.sidebarRightTabGuideEntry.typed<SidebarGuideOwner, Widget>(),
    (owner) => DshGuideCard(
      icon: const DshFilesArtwork(size: 26),
      title: i18n().t('sidebarFiles', 'guide.title'),
      description: i18n().t('sidebarFiles', 'guide.description'),
      onTap: () =>
          owner.actions.openTab(filesTabKind, replaceTabId: owner.tabId),
    ),
    key: filesTabKind,
  );
}
