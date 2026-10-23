import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'shell_card_controller.dart';

/// Locale namespace of this page's copy.
const String shellLocale = 'settings.shell';

/// The shell executor's settings page: the limits every command the agent runs
/// is bound by (dsh `ShellCard`). Renders the Plugins page's one-liner
/// ([PluginItemView.summary]) or the form ([PluginItemView.page]).
class ShellCard extends StatelessWidget {
  const ShellCard({
    super.key,
    required this.controller,
    required this.i18n,
    required this.view,
  });

  final ShellCardController controller;
  final DshI18n i18n;
  final PluginItemView view;

  @override
  Widget build(BuildContext context) {
    String t(String key) => i18n.t(shellLocale, key);
    if (view == PluginItemView.summary) return Text(t('description'));
    final actions = controller.actions;
    return DshSettingsFormStoreBuilder<ShellCardState>(
      store: controller.store,
      builder: (context, state) {
        Widget field({
          required String id,
          required String field,
          required String label,
          required String hint,
          required SettingsFieldState value,
          bool topDivider = false,
        }) => DshSettingsValueField(
          id: id,
          label: t(label),
          hint: t(hint),
          overriddenLabel: t('overridden'),
          resetLabel: t('reset'),
          invalidLabel: t('invalidNumber'),
          numeric: true,
          topDivider: topDivider,
          disabled: !state.shell.writable,
          text: value.text,
          overridden: value.overridden,
          invalid: value.invalid,
          onEdit: (text) => actions.edit(field, text),
          onReset: () => actions.resetField(field),
        );
        return DshSettingsForm(
          labels: DshSettingsFormLabels(
            unavailable: t('unavailable'),
            readOnly: t('readOnly'),
            saveFailed: t('saveFailed'),
            save: t('save'),
            saving: t('saving'),
          ),
          state: state.shell,
          onSave: actions.save,
          onDiscard: actions.discard,
          children: [
            field(
              id: 'plugin-config-shell-timeout',
              field: timeoutMsField,
              label: 'timeoutMs',
              hint: 'timeoutMsHint',
              value: state.timeoutMs,
            ),
            field(
              id: 'plugin-config-shell-output',
              field: maxOutputBytesField,
              label: 'maxOutputBytes',
              hint: 'maxOutputBytesHint',
              value: state.maxOutputBytes,
              topDivider: true,
            ),
          ],
        );
      },
    );
  }
}
