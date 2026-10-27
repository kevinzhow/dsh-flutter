import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_icon.dart';
import 'dsh_icon_data.dart';
import 'dsh_icons.g.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

// Retain the existing direct library import while the components use separate files.
export 'dsh_risk_dialog.dart';

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
    return DshContainer(
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
