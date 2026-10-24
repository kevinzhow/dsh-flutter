import 'package:flutter/widgets.dart';

import 'dsh_icon.dart';
import 'dsh_icon_data.dart';
import 'dsh_icons.g.dart';
import 'dsh_shimmer.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// The 24px process row of dsh's flow (`DisclosureRow`): a 16px leading box
/// with the 14px business glyph (a chevron up while open), the title, then
/// [collapsedContent], all in tertiary text that turns secondary on hover.
/// While [open] the [children] follow under the row.
class DshDisclosureRow extends StatefulWidget {
  const DshDisclosureRow({
    super.key,
    required this.icon,
    required this.title,
    required this.open,
    required this.expandable,
    required this.onToggle,
    this.running = false,
    this.collapsedContent,
    this.children,
    this.titleColor,
  });

  final DshIconData icon;
  final String title;
  final bool open;
  final bool expandable;
  final VoidCallback onToggle;

  /// Animate the complete header while the operation runs.
  final bool running;

  /// Row content after the title (separator, summary, badges), laid out in a
  /// shrink-to-fit row; the summary inside should be [Flexible].
  final Widget? collapsedContent;

  /// Expanded body, shown under the row while [open].
  final Widget? children;
  final Color? titleColor;

  @override
  State<DshDisclosureRow> createState() => _DshDisclosureRowState();
}

class _DshDisclosureRowState extends State<DshDisclosureRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final color = _hover
        ? theme.color('--dsw-alias-label-secondary')
        : theme.color('--dsw-alias-label-tertiary');
    final rowColor = widget.titleColor ?? color;
    final titleStyle = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(color: rowColor, height: 24 / 13);
    final leadingIcon = widget.open ? DshIcons.chevronUp : widget.icon;
    final row = Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: Center(child: DshIcon(leadingIcon, size: 14, color: rowColor)),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: DshShimmer(
            active: widget.running,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DshChromeText(widget.title, style: titleStyle, maxLines: 1),
                if (widget.collapsedContent != null)
                  Flexible(child: widget.collapsedContent!),
              ],
            ),
          ),
        ),
      ],
    );
    final header = SizedBox(
      height: 24,
      child: ClipRect(
        child: DefaultTextStyle.merge(
          style: titleStyle.copyWith(color: color),
          child: row,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: widget.expandable
              ? Semantics(
                  button: true,
                  expanded: widget.open,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onToggle,
                    child: header,
                  ),
                )
              : header,
        ),
        if (widget.open && widget.children != null) widget.children!,
      ],
    );
  }
}
