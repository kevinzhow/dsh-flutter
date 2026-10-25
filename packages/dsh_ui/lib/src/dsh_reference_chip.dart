import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dsh_icon.dart';
import 'dsh_icons.g.dart';
import 'dsh_tooltip.dart';
import 'theme_access.dart';

/// Sent-reference presentation inherits the consumer's font and baseline.
/// Only the owning feature supplies navigation; labels never invent an action.
class DshReferenceChip extends StatelessWidget {
  const DshReferenceChip({
    super.key,
    required this.appearance,
    required this.label,
    required this.title,
    this.onActivate,
  });
  final String appearance, label, title;
  final VoidCallback? onActivate;
  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final size =
        base.fontSize ?? context.dsh.textStyle('--dsw-font-s-14').fontSize!;
    final ink = context.dsh.color('--dsw-alias-state-business-primary');
    final icon = switch (appearance) {
      'session' => DshIcons.chatLines,
      'file' => DshIcons.browse,
      _ => DshIcons.folderClose,
    };
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text.rich(
        TextSpan(
          style: base.copyWith(color: ink, fontWeight: FontWeight.w500),
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Transform.translate(
                  offset: Offset(0, size * .125),
                  child: DshIcon(icon, size: size, color: ink),
                ),
              ),
            ),
            TextSpan(text: label),
          ],
        ),
      ),
    );
    return DshTooltip(
      label: title,
      child: onActivate == null
          ? content
          : Semantics(
              button: true,
              label: label,
              child: FocusableActionDetector(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                },
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      onActivate!();
                      return null;
                    },
                  ),
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onActivate,
                    child: content,
                  ),
                ),
              ),
            ),
    );
  }
}
