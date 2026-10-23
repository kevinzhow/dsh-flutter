import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'agent_loop_card_controller.dart';

/// Locale namespace of this page's copy.
const String agentLoopLocale = 'settings.agentLoop';

/// The agent loop's settings page: how many tool calls one step may run at once
/// (dsh `AgentLoopCard`). Renders the Plugins page's one-liner
/// ([PluginItemView.summary]) or the form ([PluginItemView.page]).
class AgentLoopCard extends StatelessWidget {
  const AgentLoopCard({
    super.key,
    required this.controller,
    required this.i18n,
    required this.view,
  });

  final AgentLoopCardController controller;
  final DshI18n i18n;
  final PluginItemView view;

  @override
  Widget build(BuildContext context) {
    String t(String key) => i18n.t(agentLoopLocale, key);
    if (view == PluginItemView.summary) return Text(t('description'));
    return DshSettingsFormStoreBuilder<AgentLoopCardState>(
      store: controller.store,
      builder: (context, state) => DshSettingsForm(
        labels: DshSettingsFormLabels(
          unavailable: t('unavailable'),
          readOnly: t('readOnly'),
          saveFailed: t('saveFailed'),
          save: t('save'),
          saving: t('saving'),
        ),
        state: state.shell,
        onSave: controller.actions.save,
        onDiscard: controller.actions.discard,
        children: [
          DshSettingsValueField(
            id: 'plugin-config-agent-loop-parallel',
            label: t('maxParallel'),
            hint: t('maxParallelHint'),
            overriddenLabel: t('overridden'),
            resetLabel: t('reset'),
            invalidLabel: t('invalidNumber'),
            numeric: true,
            disabled: !state.shell.writable,
            text: state.maxParallelToolCalls.text,
            overridden: state.maxParallelToolCalls.overridden,
            invalid: state.maxParallelToolCalls.invalid,
            onEdit: (text) =>
                controller.actions.edit(maxParallelToolCallsField, text),
            onReset: () =>
                controller.actions.resetField(maxParallelToolCallsField),
          ),
        ],
      ),
    );
  }
}
