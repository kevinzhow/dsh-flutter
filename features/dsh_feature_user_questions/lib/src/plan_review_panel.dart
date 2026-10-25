import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'question_tracker.dart';

/// One plan decision over the request's original approval label. Requesting
/// changes returns to the composer; it does not invent a declined answer.
class PlanReviewPanel extends StatefulWidget {
  const PlanReviewPanel({
    super.key,
    required this.pending,
    required this.review,
    required this.owner,
    required this.slots,
    required this.i18n,
  });
  final PendingQuestion pending;
  final PlanReview review;
  final SessionOwner owner;
  final SlotRegistry slots;
  final DshI18n i18n;
  @override
  State<PlanReviewPanel> createState() => _PlanReviewPanelState();
}

class _PlanReviewPanelState extends State<PlanReviewPanel> {
  StreamSubscription<QuestionCardSnapshot>? sub;
  bool busy = false, sentWaterfall = false;
  String? error;
  @override
  void initState() {
    super.initState();
    sub = widget.pending.card.changes.listen((card) {
      if (!mounted) return;
      if (sentWaterfall && card.phase == QuestionPhase.continued) {
        sentWaterfall = false;
        setState(() {
          busy = false;
          error = t('error.resubmit');
        });
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    unawaited(sub?.cancel());
    super.dispose();
  }

  String t(String key) => widget.i18n.t('question', key);
  Future<void> settle(
    Future<void> Function() send, {
    bool keepLocked = false,
  }) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await send();
      if (mounted && !keepLocked) setState(() => busy = false);
    } on Object catch (e) {
      sentWaterfall = false;
      if (mounted) {
        setState(() {
          busy = false;
          error = e is RemoteException
              ? e.message
              : e is StateError
              ? e.message
              : '$e'.replaceFirst(RegExp(r'^Exception: '), '');
        });
      }
    }
  }

  void approve() {
    final channel = widget.pending.snapshot.channel;
    sentWaterfall = channel == QuestionChannel.waterfall;
    unawaited(
      settle(() async {
        await widget.pending.submit([
          QuestionAnswer(widget.review.id, [widget.review.approve.label]),
        ]);
        if (channel == QuestionChannel.rpc) await widget.pending.dismiss();
      }, keepLocked: channel == QuestionChannel.waterfall),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final title = dshMarkdownPlainText(widget.review.plan, mode: 'first-line');
    final paragraph = dshMarkdownPlainText(
      widget.review.plan,
      mode: 'first-paragraph',
    );
    final actions = widget.slots.renderList(
      DshSlots.conversationPlanReviewActions.typed<PlanReviewOwner, Widget>(),
      PlanReviewOwner(
        session: widget.owner,
        requestKey: widget.pending.key,
        markdown: widget.review.plan,
        callId: widget.review.callId,
      ),
    );
    Widget feedback() => Semantics(
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 16),
        child: DshTooltip(
          label: error ?? '',
          disabled: error == null,
          child: DshChromeText(
            error ?? '',
            key: const ValueKey('plan-review-error'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme
                .textStyle('--dsw-font-xxxs-11')
                .copyWith(
                  height: 16 / 11,
                  color: theme.color('--dsw-alias-state-error-primary'),
                ),
          ),
        ),
      ),
    );
    final card = DshShadowBox(
      key: const ValueKey('plan-review-card'),
      color: theme.color('--dsw-specific-input-major'),
      radius: theme.radiusXl,
      shadows: [
        for (final (i, s) in theme.boxShadow('--dsw-elevation-panel').indexed)
          i == 0
              ? BoxShadow(
                  color: theme.color('--dsw-alias-border-l2'),
                  spreadRadius: s.spreadRadius,
                )
              : s,
      ],
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.radiusXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DshContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.color('--dsw-alias-state-warn-tertiary'),
              ),
              child: Row(
                children: [
                  DshStateDot(
                    busy ? DshStateDotState.ongoing : DshStateDotState.warning,
                  ),
                  const SizedBox(width: 8),
                  DshChromeText(
                    t('plan.header'),
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .copyWith(
                          height: 20 / 14,
                          color: theme.color('--dsw-alias-state-warn-primary'),
                        ),
                  ),
                  const Spacer(),
                  ...actions,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DshChromeText(
                    title,
                    key: const ValueKey('plan-review-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .sized(15, line: 22)
                        .copyWith(
                          fontWeight: FontWeight.w500,
                          color: theme.labelPrimary,
                        ),
                  ),
                  if (paragraph != title && paragraph.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    DshChromeText(
                      paragraph,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .textStyle('--dsw-font-s-14')
                          .copyWith(
                            height: 24 / 14,
                            color: theme.labelSecondary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width <= 720 ? 12 : 16,
                8,
                MediaQuery.sizeOf(context).width <= 720 ? 12 : 16,
                MediaQuery.sizeOf(context).width <= 720 ? 10 : 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: feedback()),
                  const SizedBox(width: 12),
                  DshButton(
                    key: const ValueKey('plan-review-discuss'),
                    variant: DshButtonVariant.outline,
                    onPressed: busy
                        ? null
                        : () => unawaited(settle(widget.pending.dismiss)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const DshIcon(DshShellIcons.editOutline, size: 14),
                        const SizedBox(width: 6),
                        DshChromeText(t('plan.discuss')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  DshTooltip(
                    label: widget.review.approve.description ?? '',
                    disabled: widget.review.approve.description == null,
                    child: DshButton(
                      key: const ValueKey('plan-review-approve'),
                      variant: DshButtonVariant.primary,
                      onPressed: busy ? null : approve,
                      child: DshChromeText(t('plan.approve')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 6, 32, 10),
      child: Semantics(
        container: true,
        label: widget.review.question,
        child: card,
      ),
    );
  }
}
