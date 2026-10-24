import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// The adoption error dialog (dsh's `folderError` Modal): the Host's refusal
/// under a title, with Cancel and "Choose again". Pops `true` for a retry.
class FolderErrorForm extends StatelessWidget {
  const FolderErrorForm({
    super.key,
    required this.message,
    required this.title,
    required this.cancelLabel,
    required this.closeLabel,
    required this.retryLabel,
    required this.retryEnabled,
  });

  final String message;
  final String title;
  final String cancelLabel;
  final String closeLabel;
  final String retryLabel;

  /// Retrying needs an occupant to serve the flow.
  final bool retryEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Padding(
      key: const ValueKey('folder-error'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: DshChromeText(
                      title,
                      style: theme
                          .textStyle('--dsw-font-base-strong-16')
                          .copyWith(color: theme.labelPrimary, height: 24 / 16),
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: closeLabel,
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const ValueKey('folder-error-close'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(false),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(
                        child: DshIcon(
                          DshIcons.close,
                          size: 16,
                          color: theme.labelSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: Semantics(
              liveRegion: true,
              child: DshChromeText(
                message,
                key: const ValueKey('folder-error-message'),
                style: theme
                    .textStyle('--dsw-font-xxs-12')
                    .copyWith(
                      color: theme.color('--dsw-alias-state-error-primary'),
                      height: 18 / 12,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72),
                  child: DshButton(
                    key: const ValueKey('folder-error-cancel'),
                    variant: DshButtonVariant.outline,
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Center(widthFactor: 1, child: Text(cancelLabel)),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72),
                  child: DshButton(
                    key: const ValueKey('folder-error-retry'),
                    variant: DshButtonVariant.primary,
                    onPressed: retryEnabled
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: Center(widthFactor: 1, child: Text(retryLabel)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
