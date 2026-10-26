import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'form_scope.dart';
import 'subagent_models.dart';

/// The shared Subagent form fences each owning namespace independently and
/// blocks the one Save while either section is invalid or conflicted.
class SubagentSettingsCard extends StatefulWidget {
  const SubagentSettingsCard({
    super.key,
    required this.limits,
    required this.models,
    required this.i18n,
  });
  final ConfigForm limits;
  final SubagentModelsController models;
  final DshI18n i18n;
  @override
  State<SubagentSettingsCard> createState() => _SubagentSettingsCardState();
}

class _SubagentSettingsCardState extends State<SubagentSettingsCard> {
  late final SettingsFormModel limits;
  late final void Function() off;
  StreamSubscription<Object?>? sub;
  String t(String key) => widget.i18n.t('settings.subagent', key);
  @override
  void initState() {
    super.initState();
    limits = SettingsFormModel(ConfigFormScope(widget.limits), [
      settingsLimitField('maxDepth', 0),
      settingsLimitField('maxActiveSubagents', 1),
    ]);
    off = limits.bind(limits.shell).subscribe(_changed);
    sub = widget.models.changed.changes.listen((_) => _changed());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    off();
    unawaited(sub?.cancel());
    limits.dispose();
    super.dispose();
  }

  SettingsFormShell get shell {
    final parts = [
      limits.shell(),
      widget.models.shell,
    ].where((s) => s.available);
    return SettingsFormShell(
      available: parts.isNotEmpty,
      writable: parts.every((s) => s.writable),
      dirty: parts.any((s) => s.dirty),
      invalid:
          parts.any((s) => s.invalid) ||
          (widget.models.shell.available &&
              widget.models.dirty &&
              widget.models.conflicted),
      saving: parts.any((s) => s.saving),
      failed: parts.any((s) => s.failed),
    );
  }

  Future<void> _save() async {
    final s = shell;
    if (!s.available || !s.writable || !s.dirty || s.invalid || s.saving) {
      return;
    }
    final writes = <Future<void>>[];
    if (widget.models.shell.available && widget.models.dirty) {
      writes.add(widget.models.save());
    }
    if (limits.shell().available && limits.shell().dirty) {
      writes.add(limits.save());
    }
    await Future.wait(writes);
  }

  void _discard() {
    if (shell.saving) return;
    limits.actions().discard();
    widget.models.discard();
  }

  Widget _limit(String field, bool depth) {
    final s = limits.field(field);
    final actions = limits.actions();
    return DshSettingsValueField(
      id: field,
      label: t(depth ? 'subagentMaxDepth' : 'subagentMaxActive'),
      text: s.text,
      overridden: s.overridden,
      invalid: s.invalid,
      overriddenLabel: t('overridden'),
      resetLabel: t('reset'),
      invalidLabel: t(
        depth ? 'subagentDepthInvalid' : 'subagentCapacityInvalid',
      ),
      disabled: !limits.shell().writable || shell.saving,
      numeric: true,
      onEdit: (value) => actions.edit(field, value),
      onReset: () => actions.resetField(field),
      help: DshSettingsFieldHelp(
        label: t(
          depth ? 'subagentDepthHelpLabel' : 'subagentCapacityHelpLabel',
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t(depth ? 'subagentDepthHelp' : 'subagentCapacityHelp')),
            if (depth) ...[
              const SizedBox(height: 8),
              Text('0  ${t('subagentDepthZero')}'),
              Text('1  ${t('subagentDepthOne')}'),
              const SizedBox(height: 8),
              Text(t('subagentDepthOverride')),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DshSettingsForm(
    labels: DshSettingsFormLabels(
      unavailable: t('unavailable'),
      readOnly: t('readOnly'),
      saveFailed: t('saveFailed'),
      save: t('save'),
      saving: t('saving'),
    ),
    state: shell,
    onSave: () => unawaited(_save()),
    onDiscard: _discard,
    children: [
      if (limits.shell().available) ...[
        Text(
          t('subagentLimitsTitle'),
          style: context.dsh.textStyle('--dsw-font-base-16'),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 456
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _limit('maxDepth', true)),
                    const SizedBox(width: 16),
                    Expanded(child: _limit('maxActiveSubagents', false)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _limit('maxDepth', true),
                    const SizedBox(height: 16),
                    _limit('maxActiveSubagents', false),
                  ],
                ),
        ),
      ],
      if (widget.models.shell.available) ...[
        const SizedBox(height: 20),
        SubagentModelsCard(
          controller: widget.models,
          i18n: widget.i18n,
          embedded: true,
          combinedShell: shell,
        ),
      ],
    ],
  );
}
