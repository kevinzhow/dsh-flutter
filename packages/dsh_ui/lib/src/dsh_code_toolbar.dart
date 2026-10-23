import 'package:flutter/widgets.dart';

import 'dsh_code_language.dart';
import 'dsh_icon.dart';
import 'dsh_icon_data.dart';
import 'dsh_icons.g.dart';
import 'theme_access.dart';

/// Language fallback and wrapping labels of a code card toolbar.
class DshCodeToolbarLabels {
  const DshCodeToolbarLabels({
    required this.codeLabel,
    required this.wrapLabel,
    required this.unwrapLabel,
    required this.copy,
    required this.copied,
  });

  final String codeLabel;
  final String wrapLabel;
  final String unwrapLabel;
  final String copy;
  final String copied;
}

/// The shared header of a code card (dsh `CodeToolbar`): language (or the
/// generic label), optional title and status, and the wrap and copy actions.
class DshCodeToolbar extends StatelessWidget {
  const DshCodeToolbar({
    super.key,
    required this.labels,
    required this.copied,
    required this.wrapped,
    this.lang,
    this.title,
    this.status,
    this.onCopy,
    this.onWrap,
  });

  final DshCodeToolbarLabels labels;
  final String? lang;
  final String? title;
  final String? status;
  final bool copied;
  final bool wrapped;
  final VoidCallback? onCopy;
  final VoidCallback? onWrap;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final secondary = theme.color('--dsw-alias-label-secondary');
    final base = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(fontSize: 11, height: 18 / 11);
    final code = theme.textStyle('--dsw-font-markdown-code-block');

    Widget action(
      DshIconData icon,
      String label,
      VoidCallback? onTap,
      Key key,
    ) => Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(child: DshIcon(icon, size: 14, color: secondary)),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 18, 8),
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  dshSupportsHighlighting(lang) ? lang! : labels.codeLabel,
                  style: base.copyWith(
                    color: tertiary,
                    fontFamily: code.fontFamily,
                    fontFamilyFallback: code.fontFamilyFallback,
                  ),
                ),
                if (title != null) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: base.copyWith(color: tertiary),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (status != null) ...[
            Text(status!, style: base.copyWith(color: tertiary)),
            const SizedBox(width: 8),
          ],
          if (onWrap != null)
            action(
              wrapped ? DshIcons.nowrap : DshIcons.wrap,
              wrapped ? labels.unwrapLabel : labels.wrapLabel,
              onWrap,
              const ValueKey('code-wrap'),
            ),
          if (onWrap != null && onCopy != null) const SizedBox(width: 4),
          if (onCopy != null)
            action(
              copied ? DshIcons.check : DshIcons.copy,
              copied ? labels.copied : labels.copy,
              onCopy,
              const ValueKey('code-copy'),
            ),
        ],
      ),
    );
  }
}
