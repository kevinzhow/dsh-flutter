import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'files_view.dart';

/// The tab kind this feature owns.
const String filesTabKind = 'files';

/// Occupy `sidebar.right.pane.tab[files]` with the workspace file tree.
void registerFilesFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
}) {
  slots.register<SidebarTabOwner, Widget>(
    DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
    (owner) => FilesView(owner: owner, i18n: i18n()),
    key: filesTabKind,
  );
}
