import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import 'question_tracker.dart';

/// Composer takeover for a pending set of questions (dsh `QuestionComposer`,
/// phone subset): one question at a time with its options (single or multiple
/// choice) and an "Other" free-text answer; "Next" moves on, the last question
/// sends every answer, and the dismiss control abandons the whole set.
class QuestionPanel extends StatefulWidget {
  const QuestionPanel({super.key, required this.pending, required this.i18n});

  final PendingQuestion pending;
  final DshI18n i18n;

  @override
  State<QuestionPanel> createState() => _QuestionPanelState();
}

class _Draft {
  final Set<String> selected = {};
  final TextEditingController custom = TextEditingController();
}

class _QuestionPanelState extends State<QuestionPanel> {
  late final List<_Draft> _drafts = [
    for (final _ in widget.pending.questions) _Draft(),
  ];
  int _index = 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final d in _drafts) {
      d.custom.dispose();
    }
    super.dispose();
  }

  String _q(String key, {Map<String, Object?> params = const {}}) =>
      widget.i18n.t('question', key, params: params);
  String _a(String key, {Map<String, Object?> params = const {}}) =>
      widget.i18n.t(appNamespace, key, params: params);

  bool _answered(int i) =>
      _drafts[i].selected.isNotEmpty ||
      _drafts[i].custom.text.trim().isNotEmpty;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run(
    () => widget.pending.submit([
      for (var i = 0; i < _drafts.length; i++)
        QuestionAnswer(
          widget.pending.questions[i].id,
          _drafts[i].selected.toList(),
          custom: _drafts[i].custom.text.trim(),
        ),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final questions = widget.pending.questions;
    if (questions.isEmpty) return const SizedBox.shrink();
    final q = questions[_index];
    final draft = _drafts[_index];
    final last = _index == questions.length - 1;
    final label = theme.labelPrimary;
    return DshCard(
      key: const ValueKey('question-panel'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const DshStatusDot(DshStatus.warn),
              const SizedBox(width: DshSpace.sm),
              Expanded(
                child: Text(
                  questions.length > 1
                      ? _a(
                          'question.progress',
                          params: {
                            'index': _index + 1,
                            'count': questions.length,
                          },
                        )
                      : _a('question.waiting'),
                  style: theme
                      .textStyle('--dsw-font-xxs-12')
                      .copyWith(color: theme.labelSecondary),
                ),
              ),
              DshButton(
                key: const ValueKey('question-dismiss'),
                size: DshButtonSize.sm,
                onPressed: _busy ? null : () => _run(widget.pending.dismiss),
                child: Text(_q('nav.cancel')),
              ),
            ],
          ),
          const SizedBox(height: DshSpace.sm),
          if (q.header != null)
            Text(
              q.header!,
              style: theme
                  .textStyle('--dsw-font-xxs-strong-12')
                  .copyWith(color: theme.labelSecondary),
            ),
          Text(
            q.question,
            key: const ValueKey('question-text'),
            style: theme
                .textStyle('--dsw-font-base-strong-16')
                .copyWith(color: label),
          ),
          if (q.detail != null)
            Padding(
              padding: const EdgeInsets.only(top: DshSpace.xs),
              child: Text(
                q.detail!,
                style: theme
                    .textStyle('--dsw-font-s-14')
                    .copyWith(color: theme.labelSecondary),
              ),
            ),
          const SizedBox(height: DshSpace.sm),
          for (final o in q.options)
            _OptionTile(
              key: ValueKey('option-${o.label}'),
              option: o,
              selected: draft.selected.contains(o.label),
              multi: q.multiSelect,
              enabled: !_busy,
              onTap: () => setState(() {
                if (q.multiSelect) {
                  if (!draft.selected.remove(o.label)) {
                    draft.selected.add(o.label);
                  }
                } else {
                  draft.selected
                    ..clear()
                    ..add(o.label);
                }
              }),
            ),
          const SizedBox(height: DshSpace.xs),
          DshTextField(
            key: const ValueKey('question-custom'),
            controller: draft.custom,
            placeholder: q.options.isEmpty
                ? _q('custom.placeholder')
                : '${_a('question.other')}  ${_q('custom.placeholder')}',
            enabled: !_busy,
            onChanged: (_) => setState(() {
              if (!q.multiSelect && draft.custom.text.isNotEmpty) {
                draft.selected.clear();
              }
            }),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: DshSpace.xs),
              child: Text(
                _error!,
                key: const ValueKey('question-error'),
                style: theme
                    .textStyle('--dsw-font-xxs-12')
                    .copyWith(
                      color: theme.color('--dsw-alias-state-error-primary'),
                    ),
              ),
            ),
          const SizedBox(height: DshSpace.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_index > 0)
                DshButton(
                  key: const ValueKey('question-prev'),
                  onPressed: _busy ? null : () => setState(() => _index--),
                  child: Text(_q('nav.prev')),
                ),
              const SizedBox(width: DshSpace.sm),
              DshButton(
                key: ValueKey(last ? 'question-submit' : 'question-next'),
                variant: DshButtonVariant.primary,
                onPressed: _busy || !_answered(_index)
                    ? null
                    : (last ? _submit : () => setState(() => _index++)),
                child: Text(last ? _a('question.submit') : _q('action.next')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.option,
    required this.selected,
    required this.multi,
    required this.enabled,
    required this.onTap,
  });

  final QuestionOption option;
  final bool selected;
  final bool multi;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final accent = theme.color('--dsw-alias-state-business-primary');
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DshSpace.touch),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: DshSpace.xs),
            child: Row(
              children: [
                Icon(
                  multi
                      ? (selected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank)
                      : (selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                  size: 20,
                  color: selected
                      ? accent
                      : theme.color('--dsw-alias-label-tertiary'),
                ),
                const SizedBox(width: DshSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        style: theme
                            .textStyle('--dsw-font-s-14')
                            .copyWith(color: theme.labelPrimary),
                      ),
                      if (option.description != null)
                        Text(
                          option.description!,
                          style: theme
                              .textStyle('--dsw-font-xxs-12')
                              .copyWith(color: theme.labelSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
