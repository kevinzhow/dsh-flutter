import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'question_tracker.dart';
import 'question_wait_strip.dart';

/// Composer takeover for a pending set of questions (dsh `QuestionComposer`,
/// phone subset): one question at a time with its options (single or multiple
/// choice) and an "Other" free-text answer; "Next" moves on, the last question
/// sends every answer, and the dismiss control abandons the whole set.
///
/// A timed question shows its countdown ("Continuing in 20s"), paused while the
/// person is in the answer surface, with a button to take time (the Host then
/// waits until they answer); once the agent went on without an answer the card
/// says so and still takes the answer.
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
  StreamSubscription<QuestionCardSnapshot>? _cardSub;
  bool _sentViaWaterfall = false;

  @override
  void initState() {
    super.initState();
    _cardSub = widget.pending.card.changes.listen(_onCard);
  }

  /// A waterfall submission is only "sent": the gateway drops an outcome that
  /// arrives after another client settled the event, without telling anyone.
  /// The panel therefore stays locked until the projection closes the card; a
  /// card that turns continued while a submission is in flight is unlocked so
  /// the same draft can go through the Remote path.
  void _onCard(QuestionCardSnapshot card) {
    if (!mounted) return;
    if (_sentViaWaterfall && card.phase == QuestionPhase.continued) {
      _sentViaWaterfall = false;
      setState(() {
        _busy = false;
        _error = _q('error.resubmit');
      });
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    unawaited(_cardSub?.cancel());
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

  Future<void> _run(
    Future<void> Function() action, {
    bool keepLocked = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var failed = false;
    try {
      await action();
    } on Object catch (e) {
      failed = true;
      _sentViaWaterfall = false;
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted && (failed || !keepLocked)) setState(() => _busy = false);
    }
  }

  Future<void> _submit() {
    final channel = widget.pending.snapshot.channel;
    _sentViaWaterfall = channel == QuestionChannel.waterfall;
    return _run(() async {
      await widget.pending.submit([
        for (var i = 0; i < _drafts.length; i++)
          QuestionAnswer(
            widget.pending.questions[i].id,
            _drafts[i].selected.toList(),
            custom: _drafts[i].custom.text.trim(),
          ),
      ]);
      // A continued question was accepted by the Host: the panel is done.
      if (channel == QuestionChannel.rpc) {
        _sentViaWaterfall = false;
        await widget.pending.dismiss();
      }
    }, keepLocked: channel == QuestionChannel.waterfall);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final questions = widget.pending.questions;
    if (questions.isEmpty) return const SizedBox.shrink();
    final q = questions[_index];
    final draft = _drafts[_index];
    final last = _index == questions.length - 1;
    final label = theme.labelPrimary;
    final card = widget.pending.snapshot;
    final status = theme
        .textStyle('--dsw-font-xxs-12')
        .copyWith(color: theme.labelSecondary);
    return Focus(
      // The countdown pauses while the person is anywhere in the answer
      // surface, and resumes when they leave it.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) =>
          focused ? widget.pending.holdFocus() : widget.pending.releaseFocus(),
      child: DshCard(
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
                  child: DshChromeText(
                    questions.length > 1
                        ? _a(
                            'question.progress',
                            params: {
                              'index': _index + 1,
                              'count': questions.length,
                            },
                          )
                        : _a('question.waiting'),
                    style: status,
                  ),
                ),
                DshButton(
                  key: const ValueKey('question-dismiss'),
                  size: DshButtonSize.sm,
                  semanticLabel: _q(
                    widget.pending.hidesOnDismiss ? 'nav.close' : 'nav.cancel',
                  ),
                  onPressed: _busy ? null : () => _run(widget.pending.dismiss),
                  // Putting a panel away is an icon (its name is the tooltip
                  // in dsh); abandoning the set keeps its words.
                  child: widget.pending.hidesOnDismiss
                      ? DshIcon(
                          DshIcons.close,
                          size: 12,
                          color: theme.labelPrimary,
                        )
                      : DshChromeText(_q('nav.cancel')),
                ),
              ],
            ),
            if (QuestionWaitStrip.shows(card))
              Padding(
                padding: const EdgeInsets.only(top: DshSpace.xs),
                child: QuestionWaitStrip(
                  card: card,
                  i18n: widget.i18n,
                  onTakeTime: _busy ? null : widget.pending.takeTime,
                ),
              ),
            const SizedBox(height: DshSpace.sm),
            if (q.header != null)
              DshChromeText(
                q.header!,
                style: theme
                    .textStyle('--dsw-font-xxs-strong-12')
                    .copyWith(color: theme.labelSecondary),
              ),
            DshChromeText(
              q.question,
              key: const ValueKey('question-text'),
              style: theme
                  .textStyle('--dsw-font-base-strong-16')
                  .copyWith(color: label),
            ),
            if (q.detail != null)
              Padding(
                padding: const EdgeInsets.only(top: DshSpace.xs),
                child: DshChromeText(
                  q.detail!,
                  style: theme
                      .textStyle('--dsw-font-s-14')
                      .copyWith(color: theme.labelSecondary),
                ),
              ),
            const SizedBox(height: DshSpace.sm),
            for (final (i, o) in q.options.indexed)
              _OptionTile(
                key: ValueKey('option-${o.label}'),
                option: o,
                index: i,
                selected: draft.selected.contains(o.label),
                multi: q.multiSelect,
                enabled: !_busy,
                onTap: () => setState(() {
                  widget.pending.engage();
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
                widget.pending.engage();
                if (!q.multiSelect && draft.custom.text.isNotEmpty) {
                  draft.selected.clear();
                }
              }),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: DshSpace.xs),
                child: DshChromeText(
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
                    child: DshChromeText(_q('nav.prev')),
                  ),
                const SizedBox(width: DshSpace.sm),
                DshButton(
                  key: ValueKey(last ? 'question-submit' : 'question-next'),
                  variant: DshButtonVariant.primary,
                  onPressed: _busy || !_answered(_index)
                      ? null
                      : (last ? _submit : () => setState(() => _index++)),
                  child: DshChromeText(
                    last ? _a('question.submit') : _q('action.next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// dsh's option indicator (QuestionComposer `.checkbox` and `.number`): a
/// 14px box with the check inside for several answers, the option's number on
/// a small overlay tile for one.
class _OptionMark extends StatelessWidget {
  const _OptionMark({
    required this.multi,
    required this.selected,
    required this.index,
  });

  final bool multi;
  final bool selected;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final radius = BorderRadius.circular(theme.number('--dsw-radius-xs'));
    return SizedBox(
      width: 20,
      height: 20,
      child: multi
          ? Center(
              child: DshDecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: selected ? theme.labelPrimary : null,
                  border: Border.all(
                    color: selected
                        ? theme.labelPrimary
                        : theme.color('--dsw-alias-border-l4'),
                    width: 0.5,
                  ),
                ),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: selected
                      ? Center(
                          child: DshIcon(
                            DshIcons.check,
                            size: 12,
                            color: theme.labelPrimaryForeground,
                          ),
                        )
                      : null,
                ),
              ),
            )
          : DshDecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                color: theme.color('--dsw-alias-bg-overlay'),
              ),
              child: Center(
                child: DshChromeText(
                  '${index + 1}',
                  style: theme
                      .textStyle('--dsw-font-xxs-12')
                      .copyWith(
                        color: selected
                            ? theme.labelPrimary
                            : theme.color('--dsw-alias-label-secondary'),
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.option,
    required this.index,
    required this.selected,
    required this.multi,
    required this.enabled,
    required this.onTap,
  });

  final QuestionOption option;
  final int index;
  final bool selected;
  final bool multi;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
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
                _OptionMark(multi: multi, selected: selected, index: index),
                const SizedBox(width: DshSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DshChromeText(
                        option.label,
                        style: theme
                            .textStyle('--dsw-font-s-14')
                            .copyWith(color: theme.labelPrimary),
                      ),
                      if (option.description != null)
                        DshChromeText(
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
