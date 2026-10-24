import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// A neutral capsule with a red dot and the localized exit status of a
/// settled command (dsh `ExitCodeBadge`, a neutral `Tag`).
class ExitBadge extends StatelessWidget {
  const ExitBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: DshDecoratedBox(
        decoration: BoxDecoration(
          color: theme.color('--dsw-alias-bg-module-platform'),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DshDecoratedBox(
                decoration: BoxDecoration(
                  color: theme.color('--dsw-alias-state-error-primary'),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 4, height: 4),
              ),
              const SizedBox(width: 5),
              DshChromeText(
                label,
                maxLines: 1,
                style: theme
                    .textStyle('--dsw-font-xs-13')
                    .sized(11, line: 17)
                    .copyWith(
                      fontWeight: FontWeight.w500,
                      color: theme.labelSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
