import 'dart:async';

import 'package:dsh_feature_plan/dsh_feature_plan.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:flutter/widgets.dart';

import '../helpers/plan_fixture.dart';

class _TabActions implements SidebarTabActions {
  @override
  void openResource(
    String address, {
    int? line,
    Map<String, Object?> params = const {},
  }) {}
  @override
  void openTab(
    String kind, {
    String? replaceTabId,
    Map<String, Object?> params = const {},
  }) {}
}

final Map<String, ParityCase> planModeCases = {
  'plan-mode.chip': ParityCase(
    widgets: const ['dsh_feature_plan:PlanChip'],
    build: (ctx) => Align(
      alignment: Alignment.topLeft,
      child: parityItem(
        'plan-chip-surface',
        PlanChip(
          projection:
              ctx.props['projection'] ??
              const {'active': true, 'pending': false},
          locked: ctx.props['locked'] == true,
          i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
          exitPlanMode: () async => ctx.props['busy'] == true
              ? Completer<String?>().future
              : ctx.props['failure'] == true
              ? 'Synthetic refusal'
              : null,
        ),
      ),
    ),
  ),
  'plan-mode.review': ParityCase(
    widgets: const [
      'dsh_feature_user_questions:PlanReviewPanel',
      'dsh_feature_plan:review actions',
    ],
    build: (ctx) {
      final slots = SlotRegistry();
      for (final slot in DshSlots.all) {
        slots.declare(slot);
      }
      final i18n = DshI18n(DshLocale.fromTag(ctx.locale));
      registerPlanFeature(
        slots,
        i18n: () => i18n,
        services: SyntheticPlanServices(),
      );
      return SizedBox(
        width: (ctx.props['width'] as num).toDouble() + 64,
        child: PlanReviewPanel(
          pending: syntheticPending(
            busy: ctx.props['busy'] == true,
            failure: ctx.props['failure'] == true,
          ),
          review: syntheticReview,
          owner: testSessionOwner('fixture'),
          slots: slots,
          i18n: i18n,
        ),
      );
    },
  ),
  'plan-mode.preview': ParityCase(
    widgets: const ['dsh_feature_plan:PlanPreview'],
    build: (ctx) {
      final name = ctx.props['name'] as String;
      final temporary = name == 'temporary' || name == 'expired';
      final feature = PlanFeature(SyntheticPlanServices(kind: name));
      final owner = SidebarTabOwner(
        session: testSessionOwner('fixture'),
        kind: 'plan',
        actions: _TabActions(),
        contentId: temporary
            ? 'dsh-resource://plan-review/s/review'
            : 'dsh-resource://plan/s/call',
        params: name == 'temporary'
            ? {
                'planReview': {
                  'markdown': syntheticPlan,
                  'title': 'Synthetic plan',
                },
              }
            : const {},
      );
      return parityItem(
        'plan-preview-surface',
        SizedBox(
          width: (ctx.props['width'] as num).toDouble(),
          height: (ctx.props['height'] as num).toDouble(),
          child: PlanPreview(
            owner: owner,
            feature: feature,
            i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
          ),
        ),
      );
    },
  ),
};
