// Submitted-plan cards and the plan document (dsh ui-plan PlanCards, PlanPreview).
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_plan/dsh_feature_plan.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';

SubmittedPlan _plan(Map<String, dynamic> j) => SubmittedPlan(
  callId: j['callId'] as String,
  title: j['title'] as String,
  markdown: j['markdown'] as String,
);

final Map<String, ParityCase> planCases = {
  'plan.card': ParityCase(
    widgets: const ['dsh_feature_plan:PlanCards'],
    build: (ctx) => parityItem(
      'plan-cards',
      PlanCards(
        plans: [
          for (final p
              in (ctx.props['plans'] as List).cast<Map<String, dynamic>>())
            _plan(p),
        ],
        i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
        onOpen: (_) {},
      ),
    ),
  ),
  'plan.preview': ParityCase(
    widgets: const ['dsh_feature_plan:PlanDocument'],
    build: (ctx) => parityItem(
      'plan-preview',
      PlanDocument(plan: _plan(ctx.props['plan'] as Map<String, dynamic>)),
    ),
  ),
};
