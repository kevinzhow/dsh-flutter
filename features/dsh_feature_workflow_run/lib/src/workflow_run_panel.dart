import 'dart:math' as math;

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef _Facts = ({String mode, int count});
bool _abnormal(WorkflowRunStatus s) => const {
  WorkflowRunStatus.failed,
  WorkflowRunStatus.cancelled,
  WorkflowRunStatus.interrupted,
}.contains(s);
_Facts _phaseFacts(WorkflowRunPhase p) => (
  mode: p.members.any((m) => _abnormal(m.status))
      ? 'abnormal'
      : p.members.any((m) => m.status == WorkflowRunStatus.running)
      ? 'running'
      : 'clean',
  count: p.members.length,
);

class _Disclosure {
  _Disclosure(this.facts) : open = facts.mode != 'clean';
  _Facts facts;
  bool open, pending = false;
  final focus = FocusNode();
  void advance(_Facts next) {
    if (facts == next) {
      if (pending && !focus.hasFocus) {
        open = false;
        pending = false;
      }
      return;
    }
    final old = facts;
    facts = next;
    if (next.mode == 'clean') {
      pending = open && focus.hasFocus;
      open = pending;
    } else if (old.mode == 'clean' ||
        next.mode == 'abnormal' && old.mode != 'abnormal') {
      open = true;
      pending = false;
    } else {
      pending = false;
    }
  }

  void toggle() {
    open = !open;
    pending = false;
  }

  void settle() {
    if (pending) {
      open = false;
      pending = false;
    }
  }
}

/// Workflows retain their own durable liveness even after a foreground step ends.
class WorkflowRunPanel extends StatefulWidget {
  const WorkflowRunPanel({
    super.key,
    required this.data,
    required this.i18n,
    this.canOpen,
    this.onOpen,
  });
  final WorkflowRunData data;
  final DshI18n i18n;
  final bool Function(WorkflowRunMember)? canOpen;
  final void Function(WorkflowRunMember)? onOpen;
  @override
  State<WorkflowRunPanel> createState() => _WorkflowRunPanelState();
}

class _WorkflowRunPanelState extends State<WorkflowRunPanel> {
  late _Disclosure _run;
  final _phases = <String, _Disclosure>{};
  String t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('workflowRun', key, params: params);
  _Facts get runFacts {
    final phases = widget.data.phases.map(_phaseFacts);
    return (
      mode:
          _abnormal(widget.data.status) ||
              phases.any((p) => p.mode == 'abnormal')
          ? 'abnormal'
          : widget.data.status == WorkflowRunStatus.running ||
                phases.any((p) => p.mode == 'running')
          ? 'running'
          : 'clean',
      count: phases.fold(0, (count, p) => count + p.count),
    );
  }

  @override
  void initState() {
    super.initState();
    _run = _Disclosure(runFacts);
    _sync();
  }

  @override
  void didUpdateWidget(WorkflowRunPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final keys = widget.data.phases.map((p) => p.key).toSet();
    for (final key
        in _phases.keys.where((key) => !keys.contains(key)).toList()) {
      _phases.remove(key)!.focus.dispose();
    }
    var phaseStartedCycle = false;
    for (final p in widget.data.phases) {
      final facts = _phaseFacts(p), previous = _phases[p.key];
      if (previous != null &&
          previous.facts.mode == 'clean' &&
          (facts.mode != 'clean' || facts.count != previous.facts.count)) {
        phaseStartedCycle = true;
      }
      (_phases[p.key] ??= _Disclosure(facts)).advance(facts);
    }
    _run.advance(runFacts);
    if (phaseStartedCycle && _run.facts.mode != 'clean' && !_run.open) {
      _run.open = true;
      _run.pending = false;
    }
  }

  @override
  void dispose() {
    _run.focus.dispose();
    for (final p in _phases.values) {
      p.focus.dispose();
    }
    super.dispose();
  }

  String count(int n) =>
      t(n == 1 ? 'run.members.one' : 'run.members.other', {'count': n});
  String phaseSummary(WorkflowRunPhase phase) {
    final counts = <WorkflowRunStatus, int>{};
    for (final m in phase.members) {
      counts.update(m.status, (n) => n + 1, ifAbsent: () => 1);
    }
    final active = [
      WorkflowRunStatus.running,
      WorkflowRunStatus.failed,
      WorkflowRunStatus.cancelled,
      WorkflowRunStatus.interrupted,
    ].where((s) => (counts[s] ?? 0) > 0).toList();
    if (active.isEmpty) {
      return t('statusCount.completed', {
        'count': counts[WorkflowRunStatus.completed] ?? 0,
      });
    }
    if (active.contains(WorkflowRunStatus.interrupted) &&
        (counts[WorkflowRunStatus.completed] ?? 0) > 0) {
      active.insert(0, WorkflowRunStatus.completed);
    }
    return active
        .map((s) => t('statusCount.${s.name}', {'count': counts[s]}))
        .join(' · ');
  }

  Widget text(
    BuildContext c,
    String s, {
    int size = 13,
    bool medium = false,
    double? line,
  }) => DshChromeText(
    s,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: c.dsh
        .textStyle(size == 11 ? '--dsw-font-xxxs-11' : '--dsw-font-xs-13')
        .copyWith(
          height: (line ?? (size == 11 ? 16 : 24)) / size,
          fontWeight: medium ? FontWeight.w500 : FontWeight.w400,
          color: c.dsh.color('--dsw-alias-label-tertiary'),
        ),
  );
  Widget dot(WorkflowRunStatus s) => DshStateDot(switch (s) {
    WorkflowRunStatus.running => DshStateDotState.ongoing,
    WorkflowRunStatus.completed => DshStateDotState.done,
    WorkflowRunStatus.failed => DshStateDotState.error,
    _ => DshStateDotState.warning,
  });
  void toggle(_Disclosure state) {
    DshDisclosureChange(!state.open, context).dispatch(context);
    setState(() {
      state.toggle();
      if (!_run.open) {
        for (final p in _phases.values) {
          p.settle();
        }
      }
    });
  }

  Widget content(_Disclosure state, Widget child) => Focus(
    focusNode: state.focus,
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (hasFocus) {
      if (!hasFocus && state.pending) {
        setState(state.settle);
      }
    },
    child: child,
  );
  Widget header(
    BuildContext c,
    _Disclosure state,
    String name, {
    WorkflowRunStatus? status,
    required String summary,
    required String controlId,
  }) {
    final theme = c.dsh;
    return _WorkflowAction(
      key: ValueKey(controlId),
      label: name,
      expanded: state.open,
      onTap: () => toggle(state),
      preventFocus: state.pending,
      child: DshContainer(
        height: 32,
        padding: EdgeInsets.symmetric(horizontal: status == null ? 0 : 8),
        decoration: status == null
            ? const BoxDecoration()
            : theme.cornerDecoration(
                theme.radiusMd,
                color: theme.color('--dsw-alias-bg-module-platform'),
              ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              SizedBox.square(
                dimension: 16,
                child: Center(
                  child: DshIcon(
                    state.open ? DshIcons.chevronDown : DshIcons.chevronRight,
                    size: 14,
                    color: theme.color('--dsw-alias-label-tertiary'),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .42,
                ),
                child: text(c, name, medium: status != null),
              ),
              const SizedBox(width: 6),
              SizedBox.square(
                dimension: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.color('--dsw-alias-label-tertiary'),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: text(c, summary, line: status == null ? 20 : 18)),
              if (status != null) ...[
                const SizedBox(width: 6),
                dot(status),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(0, constraints.maxWidth * .58 - 60),
                  ),
                  child: text(
                    c,
                    t('status.${status.name}'),
                    size: 11,
                    medium: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final indent = MediaQuery.sizeOf(context).width <= 560 ? 12.0 : 16.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header(
          context,
          _run,
          t('run.title', {'name': widget.data.name}),
          status: widget.data.status,
          summary: count(_run.facts.count),
          controlId: 'workflow-run-header',
        ),
        if (_run.open)
          content(
            _run,
            Padding(
              padding: EdgeInsets.only(top: 4, left: indent),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.data.phases.isEmpty)
                    text(context, t('run.empty'), line: 20),
                  for (var i = 0; i < widget.data.phases.length; i++)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
                      child: Builder(
                        builder: (context) {
                          final p = widget.data.phases[i],
                              state = _phases[widget.data.phases[i].key]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _WorkflowAction(
                                label: p.phase ?? t('phase.unassigned'),
                                expanded: state.open,
                                onTap: () => toggle(state),
                                preventFocus: state.pending,
                                child: SizedBox(
                                  height: 32,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) => Row(
                                      children: [
                                        SizedBox.square(
                                          dimension: 16,
                                          child: DshIcon(
                                            state.open
                                                ? DshIcons.chevronDown
                                                : DshIcons.chevronRight,
                                            size: 14,
                                            color: context.dsh.color(
                                              '--dsw-alias-label-tertiary',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: text(
                                            context,
                                            p.phase == null
                                                ? t('phase.unassigned')
                                                : p.phase!.isEmpty
                                                ? t('phase.empty')
                                                : p.phase!,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox.square(
                                          dimension: 2,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: context.dsh.color(
                                                '--dsw-alias-label-tertiary',
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: text(
                                            context,
                                            count(p.members.length),
                                            line: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: math.min(
                                            132,
                                            constraints.maxWidth * .48,
                                          ),
                                          child: Align(
                                            alignment:
                                                AlignmentDirectional.centerEnd,
                                            child: text(
                                              context,
                                              phaseSummary(p),
                                              line: 20,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (state.open)
                                content(
                                  state,
                                  Padding(
                                    padding: EdgeInsets.only(left: indent),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (
                                          var j = 0;
                                          j < p.members.length;
                                          j++
                                        )
                                          Padding(
                                            padding: EdgeInsets.only(
                                              top: j == 0 ? 0 : 2,
                                            ),
                                            child: _MemberRow(
                                              key: ValueKey(p.members[j].seq),
                                              member: p.members[j],
                                              label: p.members[j].label.isEmpty
                                                  ? t('member.empty')
                                                  : p.members[j].label,
                                              status: t(
                                                'status.${p.members[j].status.name}',
                                              ),
                                              openLabel: t('member.open', {
                                                'name':
                                                    p.members[j].label.isEmpty
                                                    ? t('member.empty')
                                                    : p.members[j].label,
                                              }),
                                              onTap:
                                                  widget.canOpen?.call(
                                                        p.members[j],
                                                      ) ==
                                                      true
                                                  ? () => widget.onOpen?.call(
                                                      p.members[j],
                                                    )
                                                  : null,
                                              dot: dot(p.members[j].status),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _WorkflowAction extends StatefulWidget {
  const _WorkflowAction({
    super.key,
    required this.label,
    required this.child,
    required this.onTap,
    this.expanded,
    this.onFocusChange,
    this.preventFocus = false,
  });
  final String label;
  final Widget child;
  final VoidCallback? onTap;
  final bool? expanded;
  final ValueChanged<bool>? onFocusChange;
  final bool preventFocus;
  @override
  State<_WorkflowAction> createState() => _WorkflowActionState();
}

class _WorkflowActionState extends State<_WorkflowAction> {
  final _focus = FocusNode();
  bool _ring = false;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    expanded: widget.expanded,
    enabled: widget.onTap != null,
    child: FocusableActionDetector(
      focusNode: _focus,
      onFocusChange: widget.onFocusChange,
      onShowFocusHighlight: (v) => setState(() => _ring = v),
      mouseCursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () {
                if (!widget.preventFocus) _focus.requestFocus();
                widget.onTap!();
              },
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: _ring
                ? Border.all(
                    color: context.dsh.color(
                      '--dsw-alias-state-business-primary',
                    ),
                  )
                : null,
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}

class _MemberRow extends StatefulWidget {
  const _MemberRow({
    super.key,
    required this.member,
    required this.label,
    required this.status,
    required this.openLabel,
    required this.dot,
    this.onTap,
  });
  final WorkflowRunMember member;
  final String label, status, openLabel;
  final Widget dot;
  final VoidCallback? onTap;
  @override
  State<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends State<_MemberRow> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final row = SizedBox(
      height: 24,
      child: Row(
        children: [
          SizedBox(width: 16, child: Center(child: widget.dot)),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: DshChromeText(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme
                    .textStyle('--dsw-font-s-14')
                    .copyWith(
                      height: 24 / 14,
                      color: widget.onTap == null
                          ? theme.labelSecondary
                          : theme.color('--dsw-alias-link'),
                      fontWeight: widget.onTap == null
                          ? FontWeight.w400
                          : FontWeight.w500,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: DshChromeText(
              widget.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme
                  .textStyle('--dsw-font-xs-13')
                  .copyWith(height: 20 / 13, color: theme.labelSecondary),
            ),
          ),
        ],
      ),
    );
    return widget.onTap == null && !_focused
        ? row
        : _WorkflowAction(
            label: widget.onTap == null ? widget.label : widget.openLabel,
            onTap: widget.onTap,
            onFocusChange: (v) {
              if (_focused != v) setState(() => _focused = v);
            },
            child: row,
          );
  }
}
