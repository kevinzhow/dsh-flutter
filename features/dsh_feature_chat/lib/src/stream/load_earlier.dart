import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// dsh's "Load earlier" control (`ChatView.module.css` `.older button`): a
/// 12px label in the secondary colour on the solid hover fill, 4px by 12px
/// padding, small radius; disabled it reads "Loading…" at 60% opacity. Older
/// pages are also read by themselves near the top; this stays for the reader
/// who wants it now (and when a page failed), as in dsh.
class LoadEarlierButton extends StatelessWidget {
  const LoadEarlierButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.touchTarget = true,
  });

  final String label;

  /// Null while a page is being read (the control is disabled).
  final VoidCallback? onPressed;

  /// Grow the 24px control to the 44px touch target (off for the parity captures).
  final bool touchTarget;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        // The visual is dsh's 24px control inside the 44px touch target.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: touchTarget ? DshSpace.touch : 0,
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: touchTarget ? null : 1,
            child: Opacity(
              opacity: enabled ? 1 : 0.6,
              child: DshDecoratedBox(
                // dsh's corner shape (superellipse), not a circular arc.
                decoration: theme.cornerDecoration(
                  theme.radiusSm,
                  color: theme.color('--dsw-alias-interactive-bg-hover-solid'),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: DshChromeText(
                    label,
                    // 12px on a 17px line: the control is 25px with its padding.
                    style: theme
                        .textStyle('--dsw-font-xxs-12')
                        .copyWith(color: theme.labelSecondary, height: 17 / 12),
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
