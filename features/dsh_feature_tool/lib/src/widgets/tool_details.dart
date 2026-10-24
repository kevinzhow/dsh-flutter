import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import '../model/details_model.dart';

/// Compact read-only fields and lists of a recorded result (dsh
/// `ToolDetails`): a caption, then one block per entity with status glyphs,
/// badges and `label  value` fields; unchanged todos fold into one line.
class ToolDetailsView extends StatefulWidget {
  const ToolDetailsView({super.key, required this.model});

  final DetailsModel model;

  @override
  State<ToolDetailsView> createState() => _ToolDetailsViewState();
}

class _ToolDetailsViewState extends State<ToolDetailsView> {
  bool _unchangedOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final m = widget.model;
    final base = theme.textStyle('--dsw-font-xs-13');
    final caption = theme.color('--dsw-alias-label-caption');
    final divider = Container(
      height: dshHairlineOf(context),
      color: theme.color('--dsw-alias-border-l2'),
    );
    final children = <Widget>[];
    if (m.caption != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: DshChromeText(
            m.caption!,
            style: base.sized(12).copyWith(color: caption),
          ),
        ),
      );
    }
    if (m.items.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: DshChromeText(
            m.empty ?? '',
            style: base.copyWith(color: theme.labelSecondary),
          ),
        ),
      );
    } else {
      for (var i = 0; i < m.items.length; i++) {
        if (i > 0) children.add(divider);
        children.add(_DetailItemView(item: m.items[i]));
      }
    }
    final unchanged = m.unchanged;
    if (unchanged != null) {
      children.add(divider);
      children.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _unchangedOpen = !_unchangedOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                DshIcon(
                  _unchangedOpen ? DshIcons.chevronDown : DshIcons.chevronRight,
                  size: 14,
                  color: theme.color('--dsw-alias-label-tertiary'),
                ),
                const SizedBox(width: 6),
                DshChromeText(
                  unchanged.label,
                  style: base.copyWith(
                    color: theme.color('--dsw-alias-label-tertiary'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (_unchangedOpen) {
        for (var i = 0; i < unchanged.items.length; i++) {
          children.add(divider);
          children.add(_DetailItemView(item: unchanged.items[i]));
        }
      }
    }
    return DshContainer(
      key: const ValueKey('tool-details'),
      decoration: context.dshOutlined(
        theme.radiusLg,
        fill: theme.color('--dsw-alias-markdown-code-block'),
        border: theme.color('--dsw-alias-border-l1'),
      ),
      child: theme.clipCorners(
        theme.radiusLg,
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailItemView extends StatelessWidget {
  const _DetailItemView({required this.item});

  final DetailItem item;

  Color _tone(DshThemeData c, String tone) => switch (tone) {
    'info' => c.color('--dsw-alias-state-business-primary'),
    'success' => c.color('--dsw-alias-state-success-primary'),
    'warning' => c.color('--dsw-alias-state-warn-primary'),
    'error' => c.color('--dsw-alias-state-error-primary'),
    _ => c.color('--dsw-alias-label-caption'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final base = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(color: theme.labelSecondary);
    final caption = theme.color('--dsw-alias-label-caption');
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final removed = item.change?.value == 'removed';
    final status = item.status;

    Widget statusGlyph() {
      final v = item.change?.value;
      final Color color = v == 'added'
          ? theme.color('--dsw-alias-state-success-primary')
          : v == 'removed'
          ? theme.color('--dsw-alias-state-error-primary')
          : theme.labelSecondary;
      return SizedBox(
        width: 14,
        height: 18,
        child: Center(
          child: v == 'added'
              ? DshChromeText('+', style: base.sized(16).copyWith(color: color))
              : v == 'removed'
              ? DshChromeText('−', style: base.sized(16).copyWith(color: color))
              : status!.value == 'completed'
              ? DshIcon(DshIcons.check, size: 14, color: color)
              : status.value == 'in_progress'
              ? DshIcon(DshIcons.play, size: 14, color: color)
              : DshDecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: tertiary,
                      width: dshBorderWidthOf(context, 1),
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const SizedBox(width: 10, height: 10),
                ),
        ),
      );
    }

    final heading = <Widget>[
      if (status != null) ...[statusGlyph(), const SizedBox(width: 8)],
      if (item.title != null)
        Flexible(
          child: DshChromeText(
            item.title!,
            style: base.copyWith(
              color: removed ? tertiary : theme.labelSecondary,
              decoration: removed ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      if (item.badge != null) ...[
        const SizedBox(width: 8),
        DshDecoratedBox(
          decoration: BoxDecoration(
            color: _tone(theme, item.badge!.tone),
            shape: BoxShape.circle,
          ),
          child: const SizedBox(width: 5, height: 5),
        ),
        const SizedBox(width: 5),
        DshChromeText(
          item.badge!.label,
          style: base.sized(12).copyWith(color: _tone(theme, item.badge!.tone)),
        ),
      ],
      if (status != null) ...[
        const Spacer(),
        const SizedBox(width: 8),
        if (item.previousStatus != null)
          DshChromeText(
            '${item.previousStatus} → ',
            style: base.sized(12).copyWith(color: tertiary),
          ),
        DshChromeText(
          status.label +
              (item.change?.value == 'updated' && item.previousStatus == null
                  ? ' · ${item.change!.label}'
                  : ''),
          style: base.sized(12).copyWith(color: caption),
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (heading.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: heading,
            ),
          if (item.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: DshChromeText(
                item.subtitle!,
                style: base.sized(12).copyWith(color: tertiary),
              ),
            ),
          if (item.description != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: DshChromeText(
                item.description!,
                style: base.copyWith(color: caption),
              ),
            ),
          if (item.fields.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: heading.isNotEmpty ? 6 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < item.fields.length; i++) ...[
                    if (i > 0) const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 5.5 * 13,
                          child: DshChromeText(
                            item.fields[i].label,
                            style: base.copyWith(color: caption),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DshChromeText(
                            item.fields[i].value,
                            style: base,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
