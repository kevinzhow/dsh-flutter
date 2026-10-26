import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'document_view.dart';
import 'document_controller.dart';

/// The tab kind this feature owns: a file preview.
const String textTabKind = 'text';

/// Occupy `sidebar.right.pane.tab[text]` with the file preview.
void registerDocumentPreviewFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  OfficePreviewReader? renderOffice,
  Observable<bool>? interactivePreview,
}) {
  slots.register<SidebarTabOwner, Widget>(
    DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
    (owner) => StreamBuilder<bool>(
      stream: interactivePreview?.changes,
      initialData: interactivePreview?.value ?? false,
      builder: (context, snapshot) => DocumentView(
        owner: owner,
        i18n: i18n(),
        renderOffice: renderOffice,
        interactiveHtml: snapshot.data ?? false,
      ),
    ),
    key: textTabKind,
  );
}
