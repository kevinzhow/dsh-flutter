import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// Only Host-visible ancestry is supplied by the owner. Current titles remain
/// plain text; ancestor titles navigate, and the lineage seat may decorate or
/// replace a subagent crumb without importing its feature.
class SessionBreadcrumbs extends StatelessWidget {
  const SessionBreadcrumbs({
    super.key,
    required this.owner,
    required this.slots,
    required this.i18n,
    required this.fallback,
  });
  final SessionOwner owner;
  final SlotRegistry slots;
  final DshI18n i18n;
  final Widget fallback;
  @override
  Widget build(BuildContext context) {
    final chain = owner.lineage;
    if (chain.isEmpty) return fallback;
    return Semantics(
      label: i18n.t('conversation', 'session.hierarchy'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < chain.length; index++) ...[
            if (index > 0) const DshChromeText('/'),
            Flexible(
              child: Builder(
                builder: (context) {
                  final crumb = chain[index];
                  final current = index == chain.length - 1;
                  final open = current || owner.openAncestor == null
                      ? null
                      : () => owner.openAncestor!(crumb.sessionId);
                  final title = Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: DshChromeText(
                      crumb.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.dsh
                          .textStyle('--dsw-font-s-strong-14')
                          .copyWith(
                            color: current
                                ? context.dsh.labelPrimary
                                : context.dsh.labelSecondary,
                            height: 20 / 14,
                          ),
                    ),
                  );
                  final basic = current && !crumb.subagent
                      ? fallback
                      : open == null
                      ? title
                      : Semantics(
                          button: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: open,
                            child: title,
                          ),
                        );
                  final decoration = slots.renderSingle(
                    DshSlots.conversationSessionHeaderLineage
                        .typed<SessionLineageOwner, Widget>(),
                    SessionLineageOwner(
                      session: owner,
                      crumb: crumb,
                      openTitle: open,
                    ),
                  );
                  if (crumb.subagent) return decoration ?? basic;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: basic),
                      if (current && decoration != null) decoration,
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
