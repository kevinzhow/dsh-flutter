import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'subagent_limits_card_controller.dart';

/// Locale namespace of this page's copy.
const String subagentLocale = 'settings.subagent';

/// Width at which the two limits sit side by side (dsh's grid
/// `repeat(auto-fit, minmax(min(220px, 100%), 1fr))` with a 16px gap); below
/// it they stack, as on a phone.
const double subagentLimitsTwoColumnWidth = 220 * 2 + 16;

/// The Subagent settings page: the delegation limits (dsh `SubagentCard` with
/// only its limits section). Renders the Plugins page's one-liner
/// ([PluginItemView.summary]) or the form ([PluginItemView.page]).
class SubagentCard extends StatelessWidget {
  const SubagentCard({
    super.key,
    required this.controller,
    required this.i18n,
    required this.view,
  });

  final SubagentLimitsCardController controller;
  final DshI18n i18n;
  final PluginItemView view;

  @override
  Widget build(BuildContext context) {
    String t(String key) => i18n.t(subagentLocale, key);
    if (view == PluginItemView.summary) return Text(t('subagentDescription'));
    final theme = context.dsh;
    final actions = controller.actions;
    return DshSettingsFormStoreBuilder<SubagentLimitsCardState>(
      store: controller.store,
      builder: (context, state) {
        final disabled = !state.shell.writable || state.shell.saving;
        final depth = DshSettingsValueField(
          id: 'plugin-config-subagent-depth',
          label: t('subagentMaxDepth'),
          help: DshSettingsFieldHelp(
            label: t('subagentDepthHelpLabel'),
            content: _DepthHelp(
              intro: t('subagentDepthHelp'),
              zero: t('subagentDepthZero'),
              one: t('subagentDepthOne'),
              precedence: t('subagentDepthOverride'),
            ),
          ),
          overriddenLabel: t('overridden'),
          resetLabel: t('reset'),
          invalidLabel: t('subagentDepthInvalid'),
          numeric: true,
          disabled: disabled,
          text: state.maxDepth.text,
          overridden: state.maxDepth.overridden,
          invalid: state.maxDepth.invalid,
          onEdit: (text) => actions.edit(maxDepthField, text),
          onReset: () => actions.resetField(maxDepthField),
        );
        final capacity = DshSettingsValueField(
          id: 'plugin-config-subagent-capacity',
          label: t('subagentMaxActive'),
          help: DshSettingsFieldHelp(
            label: t('subagentCapacityHelpLabel'),
            content: Text(t('subagentCapacityHelp')),
          ),
          overriddenLabel: t('overridden'),
          resetLabel: t('reset'),
          invalidLabel: t('subagentCapacityInvalid'),
          numeric: true,
          disabled: disabled,
          text: state.maxActiveSubagents.text,
          overridden: state.maxActiveSubagents.overridden,
          invalid: state.maxActiveSubagents.invalid,
          onEdit: (text) => actions.edit(maxActiveSubagentsField, text),
          onReset: () => actions.resetField(maxActiveSubagentsField),
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: DshLineText(
                      t('subagentLimitsTitle'),
                      key: const ValueKey('subagent-limits-title'),
                      style: theme
                          .textStyle('--dsw-font-xs-strong-13')
                          .copyWith(color: theme.labelPrimary),
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth >= subagentLimitsTwoColumnWidth
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: depth),
                              const SizedBox(width: 16),
                              Expanded(child: capacity),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              depth,
                              const SizedBox(height: 4),
                              capacity,
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The rules the depth field's information button discloses (dsh's
/// `depthTable`): what 0 and 1 mean, and the per-tool override.
class _DepthHelp extends StatelessWidget {
  const _DepthHelp({
    required this.intro,
    required this.zero,
    required this.one,
    required this.precedence,
  });

  final String intro;
  final String zero;
  final String one;
  final String precedence;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final line = BorderSide(
      color: theme.color('--dsw-alias-border-l2'),
      width: dshHairline,
    );
    Widget row(String depth, String meaning, {required bool first}) =>
        DecoratedBox(
          decoration: BoxDecoration(border: first ? null : Border(top: line)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    depth,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: theme.labelPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(meaning)),
              ],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(intro),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: line, bottom: line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row('0', zero, first: true),
              row('1', one, first: false),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(precedence),
      ],
    );
  }
}
