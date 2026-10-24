// The command popup (dsh ui-commands PopupSelectView) over the same fixture state the React host mounts.
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_commands/dsh_feature_commands.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> commandPopupCases = {
  'input.popup': ParityCase(
    widgets: const ['dsh_feature_commands:PopupSelectOverlay'],
    // The menu material is translucent: it sits on the page fill, which is the page's here.
    framed: false,
    build: (ctx) {
      final props = ctx.props;
      final controller = PopupSelectController(
        consume: (_) => false,
        focusComposer: () {},
      );
      final labels = props['searchLabels'] as Map<String, dynamic>?;
      controller.state.set(
        PopupState(
          open: true,
          command: props['command'] as String,
          status: (props['status'] ?? 'ready') == 'failed'
              ? PopupStatus.failed
              : PopupStatus.ready,
          options: [
            for (final o
                in (props['options'] as List).cast<Map<String, dynamic>>())
              SelectOption(
                id: o['id'] as String,
                label: o['label'] as String,
                badge: o['badge'] as String?,
                detail: o['detail'] as String?,
                active: o['active'] == true,
                group: o['group'] == null
                    ? null
                    : SelectOptionGroup(
                        name: (o['group'] as Map)['name'] as String,
                        label: (o['group'] as Map)['label'] as String,
                      ),
              ),
          ],
          searchMode: props['searchMode'] == 'fuzzy-label'
              ? PopupSearchMode.fuzzyLabel
              : PopupSearchMode.substring,
          searchLabels: labels == null
              ? null
              : PopupSearchLabels(
                  placeholder: labels['placeholder'] as String,
                  empty: labels['empty'] as String,
                  noResults: labels['noResults'] as String,
                ),
          active: (props['active'] as num? ?? 0).toInt(),
          error: props['error'] as String?,
        ),
      );
      return ColoredBox(
        color: ctx.theme.bgBase,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: (props['width'] as num).toDouble(),
            child: PopupSelectOverlay(
              sessionId: 'parity',
              controller: controller,
              i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
            ),
          ),
        ),
      );
    },
  ),
};
