import 'dart:async';

import 'package:dsh_client/generated_agent_presets.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart'
    show SelectionArea, InkWell, Material, MaterialType;

bool builtInPreset(AgentPresetRow row) =>
    row.name == null &&
    const ['standard', 'ptc', 'minimal', 'cordis'].contains(row.id);
String? _copyStem(AgentPresetRow row) => !builtInPreset(row)
    ? null
    : switch (row.id) {
        'standard' => 'Standard',
        'ptc' => 'Ptc',
        'minimal' => 'Minimal',
        'cordis' => 'Cordis',
        _ => null,
      };
String presetName(AgentPresetRow row, DshI18n i18n) {
  final stem = _copyStem(row);
  return stem == null
      ? row.name ?? row.id
      : i18n.t('settings.agentPreset', 'preset${stem}Name');
}

String? _description(AgentPresetRow row, DshI18n i18n) {
  final stem = _copyStem(row);
  return stem == null
      ? row.description
      : i18n.t('settings.agentPreset', 'preset${stem}Description');
}

class AgentPresetSection extends StatefulWidget {
  const AgentPresetSection({
    super.key,
    required this.model,
    required this.i18n,
    this.startCreator,
  });
  final AgentPresetsModel model;
  final DshI18n i18n;
  final VoidCallback? startCreator;
  @override
  State<AgentPresetSection> createState() => _AgentPresetSectionState();
}

class _AgentPresetSectionState extends State<AgentPresetSection> {
  StreamSubscription<int>? _sub;
  @override
  void initState() {
    super.initState();
    _sub = widget.model.changed.changes.listen((_) {
      if (mounted) setState(() {});
    });
    scheduleMicrotask(() {
      if (mounted) unawaited(widget.model.load());
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    widget.model.closeView(announce: false);
    super.dispose();
  }

  String t(String key) => widget.i18n.t('settings.agentPreset', key);
  Future<void> _view(AgentPresetRow row) async {
    await widget.model.view(row.id);
    if (!mounted || widget.model.document?.agentPreset != row.id) return;
    final content = widget.model.document!.content;
    await showDshDialog<void>(
      context,
      label: '${t('view')} · ${presetName(row, widget.i18n)}',
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${t('view')} · ${presetName(row, widget.i18n)}'),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: SelectionArea(
                  child: Text(
                    content,
                    style: context.dsh.fixedCodeStyle(size: 12, line: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DshButton(
              autofocus: true,
              variant: DshButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('close')),
            ),
          ],
        ),
      ),
    );
    widget.model.closeView();
  }

  Future<void> _guide(AgentPresetRow row, bool usage) async {
    final stem = _copyStem(row);
    if (stem == null) return;
    await showDshDialog<void>(
      context,
      label: presetName(row, widget.i18n),
      builder: (context) =>
          _PresetGuide(stem: stem, i18n: widget.i18n, usage: usage),
    );
  }

  Widget _card(AgentPresetRow row) {
    final theme = context.dsh;
    final name = presetName(row, widget.i18n);
    final enabled =
        !row.isDefault && row.broken == null && !widget.model.saving;
    return DshDecoratedBox(
      decoration: BoxDecoration(
        color: theme.color(
          row.isDefault
              ? '--dsw-alias-bg-module-platform'
              : '--dsw-alias-settings-card-fill',
        ),
        borderRadius: BorderRadius.circular(theme.radiusXl),
        border: Border.all(
          width: .5,
          color: theme.color(
            row.broken != null
                ? '--dsw-alias-state-error-primary'
                : row.isDefault
                ? '--dsw-static-neutral-bluish-400'
                : '--dsw-alias-settings-card-stroke',
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            selected: row.isDefault,
            button: true,
            label:
                '${t(row.broken != null
                    ? 'brokenBadge'
                    : row.isDefault
                    ? 'inUse'
                    : 'setDefault')}: $name',
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: enabled
                    ? () => unawaited(widget.model.makeDefault(row.id))
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            name,
                            style: theme.textStyle('--dsw-font-base-16'),
                          ),
                          _PresetTag(
                            label: t(
                              row.isDefault
                                  ? 'inUse'
                                  : builtInPreset(row)
                                  ? 'builtInGroup'
                                  : 'customGroup',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        row.id,
                        style: theme.fixedCodeStyle(size: 11, line: 21),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _description(row, widget.i18n) ?? t('noDescription'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (row.broken != null)
                        Semantics(
                          liveRegion: true,
                          child: Text('${t('brokenBadge')}: ${row.broken}'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Wrap(
              spacing: 4,
              children: [
                if (builtInPreset(row)) ...[
                  DshButton(
                    size: DshButtonSize.sm,
                    onPressed: () => unawaited(_guide(row, false)),
                    child: Text(t('modeExplanation')),
                  ),
                  DshButton(
                    size: DshButtonSize.sm,
                    onPressed: () => unawaited(_guide(row, true)),
                    child: Text(t('howToUse')),
                  ),
                ],
                DshButton(
                  size: DshButtonSize.sm,
                  semanticLabel: '${t('view')}: $name',
                  onPressed: () => unawaited(_view(row)),
                  icon: const DshIcon(DshIcons.browse),
                  child: Text(t('view')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('nav'),
            style: context.dsh
                .textStyle('--dsw-font-m-18')
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(t('sectionIntro')),
          const SizedBox(height: 12),
          if (m.error != null)
            _Notice(
              m.error == 'standardUnavailable'
                  ? t('standardUnavailable')
                  : m.error == 'presetSaveRefused'
                  ? widget.i18n.t('settings.agentLoop', 'saveFailed')
                  : m.error!,
            ),
          if (m.loading) DshSpinner(color: context.dsh.labelPrimary),
          for (final builtin in [true, false]) ...[
            if (m.visibleRows.any((r) => builtInPreset(r) == builtin) ||
                (!builtin &&
                    widget.startCreator != null &&
                    m.rows.any((r) => r.id == 'cordis'))) ...[
              if (!builtin) const SizedBox(height: 20),
              Text(t(builtin ? 'builtInGroup' : 'customGroup')),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, c) {
                  final columns = c.maxWidth >= 548 ? 2 : 1;
                  final width = (c.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final row in m.visibleRows.where(
                        (r) => builtInPreset(r) == builtin,
                      ))
                        SizedBox(width: width, child: _card(row)),
                    ],
                  );
                },
              ),
              if (!builtin &&
                  widget.startCreator != null &&
                  m.rows.any((r) => r.id == 'cordis'))
                DshButton(
                  onPressed: m.saving ? null : widget.startCreator,
                  icon: const DshIcon(DshIcons.plus),
                  child: Text(t('creatorDraft')),
                ),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _PresetGuide extends StatefulWidget {
  const _PresetGuide({
    required this.stem,
    required this.i18n,
    required this.usage,
  });
  final String stem;
  final DshI18n i18n;
  final bool usage;
  @override
  State<_PresetGuide> createState() => _PresetGuideState();
}

class _PresetGuideState extends State<_PresetGuide> {
  late bool usage = widget.usage;
  String t(String key) => widget.i18n.t('settings.agentPreset', key);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('preset${widget.stem}Name')),
        const SizedBox(height: 12),
        Text(t('guide${widget.stem}Intro')),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            DshButton(
              onPressed: () => setState(() => usage = false),
              child: Text(t('modeExplanation')),
            ),
            DshButton(
              onPressed: () => setState(() => usage = true),
              child: Text(t('howToUse')),
            ),
          ],
        ),
        Flexible(
          child: SingleChildScrollView(
            key: ValueKey(usage),
            child: DshMarkdown(
              t('guide${widget.stem}${usage ? 'Usage' : 'Explanation'}'),
            ),
          ),
        ),
        DshButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('close')),
        ),
      ],
    ),
  );
}

class AgentPresetChip extends StatefulWidget {
  const AgentPresetChip({super.key, required this.model, required this.i18n});
  final AgentPresetsModel model;
  final DshI18n i18n;
  @override
  State<AgentPresetChip> createState() => _AgentPresetChipState();
}

class _AgentPresetChipState extends State<AgentPresetChip> {
  StreamSubscription<int>? sub;
  @override
  void initState() {
    super.initState();
    sub = widget.model.changed.changes.listen((_) {
      if (mounted) setState(() {});
    });
    scheduleMicrotask(() {
      if (mounted) unawaited(widget.model.load());
    });
  }

  @override
  void dispose() {
    unawaited(sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    if (m.options.isEmpty || m.current.isEmpty) return const SizedBox.shrink();
    final row = m.rows.where((r) => r.id == m.current).firstOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DshMenu(
          entries: [
            for (final r in m.options)
              DshMenuItem(r.id, presetName(r, widget.i18n)),
          ],
          selectedIds: [m.current],
          onSelect: (id) => unawaited(m.select(id)),
          builder: (context, menu) => DshButton(
            size: DshButtonSize.sm,
            onPressed: m.selecting ? null : menu.toggle,
            icon: const DshIcon(DshIcons.agentPreset),
            child: Text(row == null ? m.current : presetName(row, widget.i18n)),
          ),
        ),
        if (m.selectionError != null) _Notice(m.selectionError!),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: context.dsh
          .textStyle('--dsw-font-xxs-12')
          .copyWith(
            color: context.dsh.color('--dsw-alias-state-error-primary'),
          ),
    ),
  );
}

class _PresetTag extends StatelessWidget {
  const _PresetTag({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => DshDecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(
        width: .5,
        color: context.dsh.color('--dsw-alias-border-l3'),
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(label, style: context.dsh.textStyle('--dsw-font-xxs-12')),
    ),
  );
}
