import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'submission_policy.dart';

class EnterBehaviorSettings extends StatefulWidget {
  const EnterBehaviorSettings({
    super.key,
    required this.preferences,
    required this.i18n,
  });
  final ConversationPreferences preferences;
  final DshI18n i18n;
  @override
  State<EnterBehaviorSettings> createState() => _EnterBehaviorSettingsState();
}

class _EnterBehaviorSettingsState extends State<EnterBehaviorSettings> {
  final _focus = FocusNode();
  String t(String key) => widget.i18n.t('conversation', key);
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DshWatch(
    changes: widget.preferences.busyEnter.changes,
    builder: (context) {
      final theme = context.dsh;
      return DshContainer(
        key: const ValueKey('settings-enter'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: dshBorderWidthOf(context, .5),
              color: theme.color('--dsw-alias-border-l2'),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DshLineText(
                      t('settings.enter.title'),
                      style: theme
                          .textStyle('--dsw-font-s-14')
                          .copyWith(color: theme.labelPrimary, height: 22 / 14),
                    ),
                    const SizedBox(height: 4),
                    DshLineText(
                      t('settings.enter.description'),
                      style: theme
                          .textStyle('--dsw-font-xxs-12')
                          .copyWith(
                            color: theme.color('--dsw-alias-label-tertiary'),
                            height: 18 / 12,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            DshMenu(
              entries: [
                for (final id in ['queue', 'steer'])
                  DshMenuItem(id, t('settings.enter.$id')),
              ],
              selectedIds: [widget.preferences.busyEnter.value],
              align: DshMenuAlign.end,
              onSelect: (id) {
                _focus.requestFocus();
                widget.preferences.setBusyEnter(id);
              },
              builder: (context, panel) => FocusableActionDetector(
                focusNode: _focus,
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                },
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      panel.toggle();
                      return null;
                    },
                  ),
                },
                child: DshSelectorPill(
                  key: const ValueKey('settings-enter-selector'),
                  label: t(
                    'settings.enter.${widget.preferences.busyEnter.value}',
                  ),
                  onPressed: () {
                    _focus.requestFocus();
                    panel.toggle();
                  },
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
