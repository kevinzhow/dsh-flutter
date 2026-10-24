import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:flutter/widgets.dart';

import 'dsh_button.dart';
import 'dsh_corners.dart';
import 'dsh_icon.dart';
import 'dsh_icon_data.dart';
import 'dsh_icons.g.dart';
import 'dsh_settings.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// One choice of a [showDshOptionSheet].
class DshOption {
  const DshOption({
    required this.id,
    required this.label,
    this.icon,
    this.badge,
    this.detail,
    this.enabled = true,
  });

  /// The value the sheet answers with.
  final String id;
  final String label;

  /// 16px glyph before the label (dsh `MenuEntry.icon`).
  final DshIconData? icon;

  /// Small caption after the label (the `EXP` badge of Auto review).
  final String? badge;

  /// One sentence under the label (the preset's description).
  final String? detail;
  final bool enabled;
}

/// The phone form of dsh's `Menu`: a bottom sheet listing [options], the
/// selected one marked with a check, answering with the picked id (null when
/// dismissed). dsh opens a popup anchored to the control; a sheet is the
/// native pattern for the same choice on a phone.
Future<String?> showDshOptionSheet(
  BuildContext context, {
  required List<DshOption> options,
  String? selectedId,
  String? title,
}) {
  final theme = context.dsh;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: theme.color('--dsw-alias-bg-layer-2'),
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    ),
    builder: (_) =>
        DshOptionSheet(options: options, selectedId: selectedId, title: title),
  );
}

/// The content of [showDshOptionSheet].
class DshOptionSheet extends StatelessWidget {
  const DshOptionSheet({
    super.key,
    required this.options,
    this.selectedId,
    this.title,
  });

  final List<DshOption> options;
  final String? selectedId;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final label = theme
        .textStyle('--dsw-font-base-16')
        .copyWith(color: theme.labelPrimary);
    final caption = theme
        .textStyle('--dsw-font-xxs-12')
        .copyWith(color: theme.color('--dsw-alias-label-tertiary'));
    return SafeArea(
      child: Column(
        key: const ValueKey('option-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DshSpace.lg,
                DshSpace.md,
                DshSpace.lg,
                DshSpace.xs,
              ),
              child: DshChromeText(
                title!,
                style: theme
                    .textStyle('--dsw-font-s-strong-14')
                    .copyWith(color: theme.labelSecondary),
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in options)
                    Semantics(
                      button: true,
                      selected: selectedId == option.id,
                      enabled: option.enabled,
                      label: option.badge == null
                          ? option.label
                          : '${option.label} ${option.badge}',
                      excludeSemantics: true,
                      child: GestureDetector(
                        key: ValueKey('option-${option.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: option.enabled
                            ? () => Navigator.of(context).pop(option.id)
                            : null,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: DshSpace.touch + 8,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DshSpace.lg,
                              vertical: DshSpace.sm,
                            ),
                            child: Row(
                              children: [
                                if (option.icon != null) ...[
                                  DshIcon(
                                    option.icon!,
                                    size: 18,
                                    color: theme.labelSecondary,
                                  ),
                                  const SizedBox(width: DshSpace.md),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: DshChromeText(
                                              option.label,
                                              style: label,
                                            ),
                                          ),
                                          if (option.badge != null) ...[
                                            const SizedBox(width: 6),
                                            _Badge(text: option.badge!),
                                          ],
                                        ],
                                      ),
                                      if (option.detail != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: DshChromeText(
                                            option.detail!,
                                            style: caption,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (selectedId == option.id)
                                  DshIcon(
                                    DshIcons.check,
                                    size: 16,
                                    color: theme.labelPrimary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: theme.cornerDecoration(
        theme.radiusSm / 2,
        color: theme.color('--dsw-alias-bg-module-platform'),
      ),
      child: DshChromeText(
        text,
        style: theme
            .textStyle('--dsw-font-xxxs-strong-11')
            .copyWith(color: theme.labelSecondary),
      ),
    );
  }
}

/// The risk acknowledgement dialog (dsh `RiskConfirmation` over `Modal`): the
/// confirm button stays disabled until the acknowledgement is checked.
/// Resolves true when confirmed.
Future<bool> showDshRiskDialog(
  BuildContext context, {
  required String title,
  required String description,
  required String acknowledgeLabel,
  required String cancelLabel,
  required String closeLabel,
  required String confirmLabel,
}) async {
  final theme = context.dsh;
  final confirmed = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: closeLabel,
    barrierColor: theme.color('--dsw-alias-bg-mask-1'),
    transitionDuration: Duration.zero,
    pageBuilder: (dialogContext, _, _) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DshRiskDialog(
            title: title,
            description: description,
            acknowledgeLabel: acknowledgeLabel,
            cancelLabel: cancelLabel,
            closeLabel: closeLabel,
            confirmLabel: confirmLabel,
          ),
        ),
      ),
    ),
  );
  return confirmed ?? false;
}

/// The card of [showDshRiskDialog].
class DshRiskDialog extends StatefulWidget {
  const DshRiskDialog({
    super.key,
    required this.title,
    required this.description,
    required this.acknowledgeLabel,
    required this.cancelLabel,
    required this.closeLabel,
    required this.confirmLabel,
  });

  final String title;
  final String description;
  final String acknowledgeLabel;
  final String cancelLabel;
  final String closeLabel;
  final String confirmLabel;

  @override
  State<DshRiskDialog> createState() => _DshRiskDialogState();
}

class _DshRiskDialogState extends State<DshRiskDialog> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final body = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(color: theme.labelSecondary);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: DecoratedBox(
        key: const ValueKey('risk-dialog'),
        decoration: theme.cornerDecoration(
          theme.radiusPanel,
          color: theme.color('--dsw-alias-bg-layer-2'),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: DshChromeText(
                          widget.title,
                          style: theme
                              .textStyle('--dsw-font-base-strong-16')
                              .copyWith(color: theme.labelPrimary),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: widget.closeLabel,
                        excludeSemantics: true,
                        child: GestureDetector(
                          key: const ValueKey('risk-close'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).pop(false),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: Center(
                              child: DshIcon(
                                DshIcons.close,
                                size: 14,
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
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: DshIcon(
                          DshIcons.warning,
                          size: 18,
                          color: theme.color('--dsw-alias-state-error-primary'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DshChromeText(
                          widget.description,
                          key: const ValueKey('risk-description'),
                          style: body,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: DshCheckbox(
                    key: const ValueKey('risk-acknowledge'),
                    value: _acknowledged,
                    onChanged: (v) => setState(() => _acknowledged = v),
                    label: widget.acknowledgeLabel,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DshButton(
                        key: const ValueKey('risk-cancel'),
                        variant: DshButtonVariant.outline,
                        onPressed: () => Navigator.of(context).pop(false),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 44),
                          child: DshChromeText(
                            widget.cancelLabel,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      DshButton(
                        key: const ValueKey('risk-confirm'),
                        variant: DshButtonVariant.primary,
                        onPressed: _acknowledged
                            ? () => Navigator.of(context).pop(true)
                            : null,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 108),
                          child: DshChromeText(
                            widget.confirmLabel,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
