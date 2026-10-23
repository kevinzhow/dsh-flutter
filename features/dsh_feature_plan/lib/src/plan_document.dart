import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:flutter/widgets.dart';

/// A submitted plan's complete Markdown, read-only (dsh `PlanPreview`): the
/// document in a scrolling pane with the phone padding (16 18 32).
class PlanDocument extends StatelessWidget {
  const PlanDocument({super.key, required this.plan});

  final SubmittedPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return SingleChildScrollView(
      key: const ValueKey('plan-document'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: theme.labelPrimary),
        child: DshMarkdown(plan.markdown, selectable: true),
      ),
    );
  }
}

/// The plan sheet shown on phones in place of the sidebar tab: the Markdown
/// file glyph and heading over the document.
class PlanSheet extends StatelessWidget {
  const PlanSheet({super.key, required this.plan, required this.i18n});

  final SubmittedPlan plan;
  final DshI18n i18n;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
          child: Row(
            children: [
              const DshMarkdownFileIcon(size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plan.title,
                  key: const ValueKey('plan-sheet-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme
                      .textStyle('--dsw-font-s-strong-14')
                      .copyWith(color: theme.labelPrimary),
                ),
              ),
              GestureDetector(
                key: const ValueKey('plan-sheet-close'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: DshSpace.touch,
                  height: DshSpace.touch,
                  child: Center(
                    child: Text(
                      i18n.t('common', 'close'),
                      style: theme
                          .textStyle('--dsw-font-xs-13')
                          .copyWith(color: theme.labelSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: PlanDocument(plan: plan)),
      ],
    );
  }
}

/// Open [plan] in a full-height sheet.
Future<void> showPlanSheet(
  BuildContext context, {
  required SubmittedPlan plan,
  required DshI18n i18n,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: context.dsh.bgBase,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.92,
    child: PlanSheet(plan: plan, i18n: i18n),
  ),
);
