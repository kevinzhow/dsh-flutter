// The workspace picker menu and its adoption error dialog (dsh ui-workspace WorkspacePickFlow) over the same fixture state the
// React host mounts.
import 'package:dsh_feature_workspace/dsh_feature_workspace.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart' show workspaceDisplayTitle;
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> workspaceCases = {
  'workspace.picker': ParityCase(
    widgets: const ['dsh_feature_workspace:PickerMenu'],
    // The menu material is translucent: it sits on the page fill, which is the page's here.
    framed: false,
    build: (ctx) {
      final props = ctx.props;
      final i18n = DshI18n(DshLocale.fromTag(ctx.locale));
      final workspaces = (props['workspaces'] as List)
          .cast<Map<String, dynamic>>();
      final add = PickerRow(
        id: '::add-workspace',
        label: i18n.t('workspace', 'menu.addWorkspace'),
        icon: DshIcons.plus,
      );
      final pinAdd = workspaces.isNotEmpty;
      final rows = pinAdd
          ? [
              for (final w in workspaces)
                PickerRow(
                  id: w['id'] as String,
                  label: workspaceDisplayTitle(
                    w['title'] as String,
                    i18n.t('conversation', 'workspace.defaultName'),
                  ),
                  icon: DshIcons.folderClose,
                ),
            ]
          : [add];
      final link = LayerLink();
      return ColoredBox(
        color: ctx.theme.bgBase,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformTarget(
                link: link,
                child: const SizedBox(width: 160, height: 28),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: PickerMenu(
                link: link,
                rows: rows,
                footer: pinAdd ? [add] : const [],
                selectedId: props['selectedId'] as String?,
                onSelect: (_) {},
                onClose: () {},
              ),
            ),
          ],
        ),
      );
    },
  ),
  'workspace.error': ParityCase(
    widgets: const ['dsh_feature_workspace:FolderErrorForm'],
    framed: false,
    build: (ctx) {
      final i18n = DshI18n(DshLocale.fromTag(ctx.locale));
      // The modal's mask sits over the page: it shows in the card's rounded corners.
      return ColoredBox(
        color: ctx.theme.bgBase,
        child: ColoredBox(
          color: ctx.theme.color('--dsw-alias-bg-mask-1'),
          child: Padding(
            // Modal's root keeps 24px of air on every side.
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.topLeft,
              child: DshDialogFrame(
                key: const ValueKey('folder-error-dialog'),
                width: 380,
                child: FolderErrorForm(
                  message: ctx.props['message'] as String,
                  title: i18n.t('workspace', 'folderError.title'),
                  cancelLabel: i18n.t('common', 'cancel'),
                  closeLabel: i18n.t('common', 'close'),
                  retryLabel: i18n.t('workspace', 'folderError.retry'),
                  retryEnabled: true,
                ),
              ),
            ),
          ),
        ),
      );
    },
  ),
};
