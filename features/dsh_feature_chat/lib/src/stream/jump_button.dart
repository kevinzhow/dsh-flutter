import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// dsh's "back to bottom" control (`ui-chat` `ChatView.module.css` `.toBottom`:
/// 34px round chevron on the floating-button fill, panel elevation with the
/// l3 border as its ring, 16px above the composer at the trailing edge).
///
/// With unread content below it widens to a pill carrying the count
/// ("3 new"): the count and its placement follow raft-flutter's timeline
/// bottom control (`RaftTimelineBottomControls`, "N new" in place of "Back to
/// bottom", bottom-anchored in the timeline Stack).
class StreamJumpButton extends StatefulWidget {
  const StreamJumpButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.countLabel,
    this.touchTarget = true,
  });

  /// "Back to bottom" (the semantic label, and the tooltip-equivalent).
  final String label;

  /// "N new" while content arrived below the reader; null for the bare chevron.
  final String? countLabel;
  final VoidCallback onPressed;

  /// Grow the 34px control to the 44px touch target (off for the parity captures).
  final bool touchTarget;

  @override
  State<StreamJumpButton> createState() => _StreamJumpButtonState();
}

class _StreamJumpButtonState extends State<StreamJumpButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final count = widget.countLabel;
    final label = widget.label;
    final onPressed = widget.onPressed;
    final ink = theme.labelPrimary;
    final shadows = [
      for (final (i, s) in theme.boxShadow('--dsw-elevation-panel').indexed)
        i == 0
            ? BoxShadow(
                color: theme.color('--dsw-alias-border-l3'),
                spreadRadius: s.spreadRadius,
              )
            : s,
    ];
    return Semantics(
      button: true,
      label: count == null ? label : '$label, $count',
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        key: const ValueKey('chat-to-bottom'),
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        // The 34px visual sits in a 44px touch target.
        child: SizedBox(
          height: widget.touchTarget ? DshSpace.touch : null,
          child: Center(
            widthFactor: 1,
            heightFactor: widget.touchTarget ? null : 1,
            // dsh's `.toBottom:hover` swaps to the floating-hover fill.
            child: MouseRegion(
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: DshShadowBox(
                color: theme.color(
                  _hover
                      ? '--dsw-alias-button-floating-hover'
                      : '--dsw-alias-button-floating-fill',
                ),
                radius: 17,
                shadows: shadows,
                padding: count == null
                    ? EdgeInsets.zero
                    : const EdgeInsets.only(left: 12, right: 14),
                child: SizedBox(
                  height: 34,
                  width: count == null ? 34 : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DshIcon(DshIcons.chevronDown, color: ink),
                      if (count != null) ...[
                        const SizedBox(width: 6),
                        DshChromeText(
                          count,
                          key: const ValueKey('chat-new-count'),
                          style: theme
                              .textStyle('--dsw-font-xs-13')
                              .copyWith(
                                color: ink,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
