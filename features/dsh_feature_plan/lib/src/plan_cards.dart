import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// The completed turn's submitted plans, one card per `exit_plan_mode`
/// invocation in invocation order (dsh `PlanCards`): the Markdown file glyph,
/// the plan's heading, "Plan · Markdown" and an Open action.
class PlanCards extends StatelessWidget {
  const PlanCards({
    super.key,
    required this.plans,
    required this.i18n,
    required this.onOpen,
  });

  final List<SubmittedPlan> plans;
  final DshI18n i18n;
  final void Function(SubmittedPlan plan) onOpen;

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      i18n.t('plan', key, params: params);

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) return const SizedBox.shrink();
    final theme = context.dsh;
    final dark = theme.brightness == Brightness.dark;
    final fill = theme.color(
      dark ? '--dsw-static-neutral-850' : '--dsw-static-neutral-50',
    );
    final tile = theme
        .color('--dsw-static-neutral-00')
        .withValues(alpha: dark ? 0.05 : 0.5);
    final base = theme.textStyle('--dsw-font-xs-13');
    return Column(
      key: const ValueKey('plan-cards'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < plans.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Semantics(
            button: true,
            label: _t('preview.openNamed', {'title': plans[i].title}),
            excludeSemantics: true,
            child: GestureDetector(
              key: ValueKey('plan-card-${plans[i].callId}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpen(plans[i]),
              child: Container(
                height: 60,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(theme.radiusLg),
                  border: Border.all(
                    color: theme.color('--dsw-alias-border-l1'),
                    width: dshHairline,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tile,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.color('--dsw-alias-border-l1'),
                          width: dshHairline,
                        ),
                      ),
                      child: const DshMarkdownFileIcon(size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DshChromeText(
                            plans[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: base.copyWith(
                              height: 20 / 13,
                              fontWeight: FontWeight.w500,
                              color: theme.labelPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          DshChromeText(
                            _t('preview.document'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: base
                                .sized(10, line: 16)
                                .copyWith(
                                  color: theme.color(
                                    '--dsw-alias-label-tertiary',
                                  ),
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.color('--dsw-alias-button-floating-fill'),
                        borderRadius: BorderRadius.circular(theme.radiusSm),
                        border: Border.all(
                          color: theme.color('--dsw-alias-border-l3'),
                          width: dshHairline,
                        ),
                      ),
                      child: DshChromeText(
                        _t('preview.action'),
                        style: base
                            .sized(12, line: 18)
                            .copyWith(color: theme.labelPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
