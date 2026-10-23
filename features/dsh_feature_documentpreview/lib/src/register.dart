import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'document_view.dart';

/// The tab kind this feature owns: a file preview.
const String textTabKind = 'text';

/// Occupy `sidebar.right.pane.tab[text]` with the file preview.
void registerDocumentPreviewFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
}) {
  slots.register<SidebarTabOwner, Widget>(
    DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
    (owner) => DocumentView(owner: owner, i18n: i18n()),
    key: textTabKind,
  );
}
