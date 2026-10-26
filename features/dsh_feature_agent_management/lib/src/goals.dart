import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart'
    show Material, MaterialType, TextField, InputDecoration, InputBorder;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class GoalDock extends StatefulWidget {
  const GoalDock({
    super.key,
    required this.owner,
    required this.remotes,
    required this.ensureOpen,
    required this.i18n,
  });
  final SessionOwner owner;
  final HostRemotes remotes;
  final Future<void> Function() ensureOpen;
  final DshI18n i18n;
  @override
  State<GoalDock> createState() => _GoalDockState();
}

class _GoalDockState extends State<GoalDock> {
  late final model = GoalModel(
    session: widget.owner.session,
    remotes: widget.remotes,
    ensureOpen: widget.ensureOpen,
  );
  @override
  void dispose() {
    unawaited(model.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      GoalBar(model: model, i18n: widget.i18n);
}

class GoalBar extends StatefulWidget {
  const GoalBar({super.key, required this.model, required this.i18n});
  final GoalModel model;
  final DshI18n i18n;
  @override
  State<GoalBar> createState() => _GoalBarState();
}

class _GoalBarState extends State<GoalBar> {
  final draft = TextEditingController();
  StreamSubscription<int>? sub;
  bool editing = false;
  String? editingId, lastId;
  String t(String key) => widget.i18n.t('goal', key);
  @override
  void initState() {
    super.initState();
    lastId = widget.model.goal?.id;
    sub = widget.model.changed.changes.listen((_) {
      if (!mounted) return;
      if (lastId != widget.model.goal?.id) {
        editing = false;
        editingId = null;
        lastId = widget.model.goal?.id;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(sub?.cancel());
    draft.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final text = draft.text.trim();
    if (text.isEmpty) return;
    final id = editingId;
    final ok = await widget.model.act('edit', objective: text, expectedId: id);
    if (mounted && ok && editingId == id) setState(() => editing = false);
  }

  Widget action(String verb, DshIconData icon, VoidCallback onPressed) =>
      DshTooltip(
        label: t('action.$verb'),
        side: DshTooltipSide.bottom,
        delay: const Duration(milliseconds: 500),
        child: DshButton(
          size: DshButtonSize.sm,
          semanticLabel: t('action.$verb'),
          onPressed: widget.model.pending ? null : onPressed,
          child: DshIcon(icon, size: 14),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final m = widget.model, goal = m.goal, theme = context.dsh;
    if (goal == null ||
        goal.phase.value == 'complete' ||
        goal.id == m.clearedId) {
      return const SizedBox.shrink();
    }
    final activation = m.currentActivation;
    final label = goal.phase.value == 'active' && activation == 'disarmed'
        ? t('phase.active.disarmed')
        : t('phase.${goal.phase.value}');
    final content = Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 5, 4),
        child: Row(
          children: [
            if (editing) ...[
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape): () {
                      if (!m.pending) setState(() => editing = false);
                    },
                  },
                  child: TextField(
                    controller: draft,
                    autofocus: true,
                    enabled: !m.pending,
                    style: theme.textStyle('--dsw-font-xs-13'),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => unawaited(save()),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      labelText: t('objective.aria'),
                    ),
                  ),
                ),
              ),
              if (draft.text.trim().isNotEmpty)
                action('save', DshIcons.check, () => unawaited(save())),
              action(
                'cancel',
                DshIcons.close,
                () => setState(() => editing = false),
              ),
            ] else ...[
              const DshIcon(DshIcons.goal, size: 14),
              const SizedBox(width: 10),
              Text(
                label,
                style: theme
                    .textStyle('--dsw-font-xs-13')
                    .copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  goal.objective,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme
                      .textStyle('--dsw-font-xs-13')
                      .copyWith(
                        color: theme.color('--dsw-alias-label-primary-dimmed'),
                      ),
                ),
              ),
              if (goal.phase.value == 'active' && activation == 'armed')
                action(
                  'pause',
                  DshIcons.pause,
                  () => unawaited(m.act('pause')),
                ),
              if (goal.phase.value == 'paused' ||
                  (goal.phase.value == 'active' && activation == 'disarmed'))
                action(
                  'resume',
                  DshIcons.play,
                  () => unawaited(m.act('resume')),
                ),
              action('edit', DshIcons.edit, () {
                draft.text = goal.objective;
                setState(() {
                  editing = true;
                  editingId = goal.id;
                });
              }),
              action('clear', DshIcons.trash, () => unawaited(m.act('clear'))),
            ],
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DshDecoratedBox(
            decoration: BoxDecoration(
              color: theme.color('--dsw-specific-menu'),
              borderRadius: BorderRadius.circular(theme.radiusMd),
              boxShadow: theme.boxShadow('--dsw-elevation-panel'),
            ),
            child: SizedBox(
              height: 36,
              child: goal.blockedReason == null
                  ? content
                  : DshTooltip(
                      label: goal.blockedReason!.message,
                      child: content,
                    ),
            ),
          ),
          if (m.error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                m.error!,
                style: theme
                    .textStyle('--dsw-font-xxs-12')
                    .copyWith(
                      color: theme.color('--dsw-alias-state-error-primary'),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
