import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'catalog.dart';

/// One child's own transcript, read-only (dsh's `subagentchat` tab): the chat
/// view of the child's session through `conversation.view`, under a bar naming
/// the child, with the read-only notice where the composer would be.
class SubagentTranscript extends StatelessWidget {
  const SubagentTranscript({
    super.key,
    required this.child,
    required this.entry,
    required this.slots,
    required this.i18n,
    required this.viewSlot,
    required this.onClose,
  });

  final SessionOwner child;
  final SubagentEntry entry;
  final SlotRegistry slots;
  final DshI18n i18n;
  final Slot<SessionOwner, Widget> viewSlot;
  final VoidCallback onClose;

  String _s(String key) => i18n.t('subagent', key);

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final views = slots.renderList(viewSlot, child);
    final title = entry.label ?? entry.id;
    final readonly = entry.mode == 'one-shot'
        ? (_s('readonly.oneShot.title'), _s('readonly.oneShot.body'))
        : entry.mode == 'unknown'
        ? (_s('readonly.title'), _s('readonly.unknown.body'))
        : (_s('readonly.title'), _s('readonly.body'));
    return ColoredBox(
      color: theme.bgBase,
      child: SafeArea(
        child: Column(
          key: const ValueKey('subagent-transcript'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, DshSpace.lg, 4),
              child: Row(
                children: [
                  GestureDetector(
                    key: const ValueKey('subagent-close'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    child: SizedBox(
                      width: DshSpace.touch,
                      height: DshSpace.touch,
                      child: Center(
                        child: Transform.rotate(
                          angle: 1.5708,
                          child: DshIcon(
                            DshIcons.chevronDown,
                            size: 16,
                            color: theme.labelSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DshChromeText(
                          title,
                          key: const ValueKey('subagent-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme
                              .textStyle('--dsw-font-base-strong-16')
                              .copyWith(color: theme.labelPrimary),
                        ),
                        DshChromeText(
                          modeLabel(i18n, entry.mode),
                          style: theme
                              .textStyle('--dsw-font-xxs-12')
                              .copyWith(
                                color: theme.color(
                                  '--dsw-alias-label-tertiary',
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: views.isEmpty ? const SizedBox.shrink() : views.first,
            ),
            Container(
              key: const ValueKey('subagent-readonly'),
              width: double.infinity,
              margin: const EdgeInsets.all(DshSpace.md),
              padding: const EdgeInsets.all(DshSpace.md),
              decoration: BoxDecoration(
                color: theme.color('--dsw-alias-bg-layer-2'),
                borderRadius: BorderRadius.circular(theme.radiusLg),
                border: Border.all(
                  color: theme.color('--dsw-alias-border-l2'),
                  width: dshHairline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DshChromeText(
                    readonly.$1,
                    style: theme
                        .textStyle('--dsw-font-s-strong-14')
                        .copyWith(color: theme.labelPrimary),
                  ),
                  const SizedBox(height: 4),
                  DshChromeText(
                    readonly.$2,
                    style: theme
                        .textStyle('--dsw-font-xs-13')
                        .copyWith(color: theme.labelSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
