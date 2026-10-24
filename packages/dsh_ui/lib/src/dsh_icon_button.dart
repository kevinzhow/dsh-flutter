import 'package:flutter/widgets.dart';

import 'dsh_snapped_box.dart';
import 'theme_access.dart';

/// A round icon button at the minimum touch size. [filled] uses the brand
/// button fill (send), otherwise the control is a ghost (stop, close).
class DshIconButton extends StatelessWidget {
  const DshIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.filled = false,
    this.plain = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool filled;

  /// No fill at all: a toolbar action next to text.
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final enabled = onPressed != null;
    final fill = filled
        ? theme.color('--dsw-alias-button-primary-fill')
        : plain
        ? null
        : theme.color('--dsw-alias-button-tool-bar-fill');
    final foreground = filled
        ? theme.labelPrimaryForeground
        : theme.labelPrimary;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: DshSpace.touch,
          height: DshSpace.touch,
          child: Center(
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: DshDecoratedBox(
                decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(icon, size: 18, color: foreground),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
