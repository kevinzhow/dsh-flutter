import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'chat_preferences.dart';

class WorkDetailsSettings extends StatelessWidget {
  const WorkDetailsSettings({
    super.key,
    required this.preferences,
    required this.i18n,
  });
  final ChatPreferences preferences;
  final DshI18n i18n;
  String t(String key) => i18n.t('chat', key);
  @override
  Widget build(BuildContext context) => DshWatch(
    changes: preferences.mode.changes,
    builder: (_) => DshWatch(
      changes: preferences.timing.changes,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row('settings.transcript', preferences.mode.value.name, [
            for (final mode in TranscriptViewMode.values)
              (mode.name, 'settings.transcript.${mode.name}'),
          ], (id) => preferences.setMode(TranscriptViewMode.values.byName(id))),
          _row(
            'settings.collapse',
            preferences.timing.value == CollapseTiming.nextInput
                ? 'nextInput'
                : 'completion',
            [
              ('completion', 'settings.collapse.completion'),
              ('nextInput', 'settings.collapse.nextInput'),
            ],
            (id) => preferences.setTiming(
              id == 'nextInput'
                  ? CollapseTiming.nextInput
                  : CollapseTiming.completion,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _row(
    String prefix,
    String value,
    List<(String, String)> choices,
    ValueChanged<String> select,
  ) => _PreferenceRow(
    key: ValueKey(prefix),
    title: t('$prefix.title'),
    description: t('$prefix.description'),
    control: _PreferenceControl(
      id: prefix,
      value: value,
      choices: [for (final (id, label) in choices) (id, t(label))],
      onSelect: select,
    ),
  );
}

/// Chat's preference row keeps the same two-column arrangement at phone widths.
class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    super.key,
    required this.title,
    required this.description,
    required this.control,
  });
  final String title, description;
  final Widget control;
  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshContainer(
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
                  _PreferenceText(
                    title,
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .copyWith(color: theme.labelPrimary, height: 22 / 14),
                  ),
                  const SizedBox(height: 4),
                  _PreferenceText(
                    description,
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
          control,
        ],
      ),
    );
  }
}

/// CSS normal wrapping keeps a long word whole, allowing it to use the
/// reserved right padding. Flutter otherwise splits it into extra lines.
class _PreferenceText extends StatelessWidget {
  const _PreferenceText(this.text, {required this.style});
  final String text;
  final TextStyle style;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.maxWidth.isFinite ||
          RegExp(r'[\u2e80-\u9fff]').hasMatch(text)) {
        return DshLineText(text, style: style);
      }
      final painter = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      );
      double width(String value) {
        painter.text = TextSpan(text: value, style: style);
        painter.layout();
        return painter.width;
      }

      final lines = <String>[];
      var line = '';
      for (final word in text.split(RegExp(r'\s+'))) {
        final candidate = line.isEmpty ? word : '$line $word';
        if (line.isNotEmpty && width(candidate) > constraints.maxWidth) {
          lines.add(line);
          line = word;
        } else {
          line = candidate;
        }
      }
      if (line.isNotEmpty) lines.add(line);
      painter.dispose();
      return DshChromeText(
        lines.join('\n'),
        style: style,
        softWrap: false,
        overflow: TextOverflow.visible,
        semanticsLabel: text,
      );
    },
  );
}

class _PreferenceControl extends StatefulWidget {
  const _PreferenceControl({
    required this.id,
    required this.value,
    required this.choices,
    required this.onSelect,
  });
  final String id, value;
  final List<(String, String)> choices;
  final ValueChanged<String> onSelect;
  @override
  State<_PreferenceControl> createState() => _PreferenceControlState();
}

class _PreferenceControlState extends State<_PreferenceControl> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DshMenu(
    entries: [for (final (id, label) in widget.choices) DshMenuItem(id, label)],
    selectedIds: [widget.value],
    align: DshMenuAlign.end,
    onSelect: (id) {
      _focus.requestFocus();
      widget.onSelect(id);
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
        key: ValueKey('${widget.id}-selector'),
        label: widget.choices.firstWhere((v) => v.$1 == widget.value).$2,
        onPressed: () {
          _focus.requestFocus();
          panel.toggle();
        },
      ),
    ),
  );
}
