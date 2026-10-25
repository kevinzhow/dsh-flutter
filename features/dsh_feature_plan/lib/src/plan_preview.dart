import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'plan_services.dart';
import 'plan_resource.dart';
import 'plan_document.dart';

class PlanPreview extends StatefulWidget {
  const PlanPreview({
    super.key,
    required this.owner,
    required this.feature,
    required this.i18n,
    this.titleOnly = false,
  });
  final SidebarTabOwner owner;
  final PlanFeature feature;
  final DshI18n i18n;
  final bool titleOnly;
  @override
  State<PlanPreview> createState() => _PlanPreviewState();
}

class _PlanPreviewState extends State<PlanPreview> {
  PlanResourceHandle? handle;
  StreamSubscription<PlanResourceSnapshot>? sub;
  @override
  void initState() {
    super.initState();
    bind();
  }

  @override
  void didUpdateWidget(PlanPreview old) {
    super.didUpdateWidget(old);
    if (old.owner.contentId != widget.owner.contentId ||
        old.feature != widget.feature) {
      unbind(old);
      bind();
    }
  }

  void bind() {
    if (isReviewPreviewAddress(widget.owner.contentId)) return;
    handle = widget.feature.acquire(widget.owner.contentId);
    sub = handle?.state.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void unbind(PlanPreview previous) {
    unawaited(sub?.cancel());
    sub = null;
    if (handle case final h?) {
      previous.feature.release(previous.owner.contentId, h);
    }
    handle = null;
  }

  @override
  void dispose() {
    unbind(widget);
    super.dispose();
  }

  String t(String key) => widget.i18n.t('plan', key);
  String failureLine(Object error) {
    if (error is! RemoteException) return '$error';
    return switch (error.code) {
      'plan/invalid-address' => t('preview.invalidAddress'),
      'plan/unavailable' => t('preview.historyUnavailable'),
      'plan/not-found' => t('preview.notFound'),
      _ => error.message,
    };
  }

  @override
  Widget build(BuildContext context) {
    final temporary = isReviewPreviewAddress(widget.owner.contentId);
    final raw = widget.owner.params['planReview'];
    final temp =
        temporary &&
            raw is Map &&
            raw['markdown'] is String &&
            raw['title'] is String
        ? SubmittedPlan(
            callId: '',
            markdown: raw['markdown'] as String,
            title: raw['title'] as String,
          )
        : null;
    final value = handle?.state.value;
    final plan = temporary ? temp : value?.plan;
    if (widget.titleOnly) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DshFileTypeIcon(kind: 'other', size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: DshChromeText(
              plan?.title ?? t('preview.title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    if (plan != null) {
      return Semantics(
        label: plan.title,
        child: PlanDocument(plan: plan),
      );
    }
    final label = temporary
        ? 'preview.expired'
        : handle == null
        ? (PlanAddress.parse(widget.owner.contentId) == null
              ? 'preview.invalidAddress'
              : 'preview.unavailable')
        : value?.failure != null
        ? 'preview.failed'
        : value?.complete == true
        ? 'preview.notFound'
        : 'preview.loading';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DshChromeText(
              t(label),
              key: const ValueKey('plan-preview-status'),
              style: context.dsh
                  .textStyle('--dsw-font-s-14')
                  .copyWith(color: context.dsh.labelSecondary),
            ),
            if (value?.failure != null) ...[
              const SizedBox(height: 8),
              DshChromeText(
                failureLine(value!.failure!),
                style: context.dsh
                    .textStyle('--dsw-font-xxs-12')
                    .copyWith(color: context.dsh.labelSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
