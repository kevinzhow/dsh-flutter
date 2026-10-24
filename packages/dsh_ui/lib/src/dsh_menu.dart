import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import 'dsh_anchored_panel.dart';
import 'dsh_icon.dart';
import 'dsh_icon_data.dart';
import 'dsh_icons.g.dart';
import 'dsh_pixel_snap.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// One entry of a [DshMenu]: a row, a heading or a separator.
sealed class DshMenuEntry {
  const DshMenuEntry(this.id);
  final String id;
}

/// A selectable row.
class DshMenuItem extends DshMenuEntry {
  const DshMenuItem(
    super.id,
    this.label, {
    this.icon,
    this.danger = false,
    this.disabled = false,
  });

  final String label;
  final DshIconData? icon;
  final bool danger;
  final bool disabled;
}

/// A non-interactive heading row.
class DshMenuLabel extends DshMenuEntry {
  const DshMenuLabel(super.id, this.text);
  final String text;
}

/// A hairline between groups.
class DshMenuSeparator extends DshMenuEntry {
  const DshMenuSeparator(super.id);
}

/// Where the card sits against its anchor (dsh `Menu` `align`).
enum DshMenuAlign { start, end }

/// Handle a [DshMenu] anchor builder uses to open and close its menu.
typedef DshMenuController = DshPanelController;

/// The anchored dropdown of dsh's `Menu` primitive: a translucent blurred card
/// 4px below its anchor with 4px padding, rows of 34px (30px [dense]) with an
/// icon, the label and a trailing check on selected rows, 11px heading rows and
/// 0.5px separators. [builder] draws the anchor; the card closes on a selection
/// or a press outside it.
class DshMenu extends StatelessWidget {
  const DshMenu({
    super.key,
    required this.builder,
    required this.entries,
    required this.onSelect,
    this.selectedIds = const [],
    this.align = DshMenuAlign.start,
    this.dense = false,
    this.minWidth = 144,
    this.controller,
  });

  /// Draws the anchor; call [DshPanelController.toggle] to open the card.
  final Widget Function(BuildContext context, DshPanelController controller)
  builder;
  final List<DshMenuEntry> entries;
  final ValueChanged<String> onSelect;
  final List<String> selectedIds;
  final DshMenuAlign align;
  final bool dense;
  final double minWidth;
  final DshPanelController? controller;

  @override
  Widget build(BuildContext context) => DshAnchoredPanel(
    controller: controller,
    align: align == DshMenuAlign.end ? DshPanelAlign.end : DshPanelAlign.start,
    builder: builder,
    panelBuilder: (context, panel) => DshMenuCard(
      key: const ValueKey('dsh-menu'),
      entries: entries,
      selectedIds: selectedIds,
      dense: dense,
      minWidth: minWidth,
      onSelect: (id) {
        panel.close();
        onSelect(id);
      },
    ),
  );
}

/// The card itself, for callers that place it on their own (tests, the dock).
class DshMenuCard extends StatelessWidget {
  const DshMenuCard({
    super.key,
    required this.entries,
    required this.onSelect,
    this.selectedIds = const [],
    this.dense = false,
    this.minWidth = 144,
  });

  final List<DshMenuEntry> entries;
  final ValueChanged<String> onSelect;
  final List<String> selectedIds;
  final bool dense;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final radius = BorderRadius.circular(theme.radiusLg);
    final hairline = dshHairlineOf(context);
    return DshContainer(
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: 360),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: theme.boxShadow('--dsw-elevation-prominent'),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            // CSS `saturate(150%)`.
            inner: const ColorFilter.matrix(<double>[
              1.3935, -0.3575, -0.0360, 0, 0, //
              -0.1065, 1.1425, -0.0360, 0, 0, //
              -0.1065, -0.3575, 1.4640, 0, 0, //
              0, 0, 0, 1, 0, //
            ]),
          ),
          child: DshContainer(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.color('--dsw-menu-surface-fill'),
              borderRadius: radius,
              border: Border.all(
                color: theme.color('--dsw-alias-border-l1'),
                width: hairline,
              ),
            ),
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < entries.length; i++)
                    switch (entries[i]) {
                      DshMenuSeparator() =>
                        i == 0 || entries[i - 1] is DshMenuSeparator
                            ? const SizedBox.shrink()
                            : const _Separator(),
                      DshMenuLabel(:final id, :final text) => _Heading(
                        key: ValueKey('dsh-menu-label-$id'),
                        text: text,
                        dense: dense,
                      ),
                      final DshMenuItem item => _Row(
                        key: ValueKey('dsh-menu-${item.id}'),
                        item: item,
                        selected: selectedIds.contains(item.id),
                        dense: dense,
                        onTap: () => onSelect(item.id),
                      ),
                    },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: DshContainer(
        height: dshHairlineOf(context),
        decoration: BoxDecoration(color: theme.color('--dsw-alias-border-l2')),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({super.key, required this.text, required this.dense});

  final String text;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: dense ? 3 : 6),
      child: DshChromeText(
        text,
        style: theme
            .textStyle('--dsw-font-xxxs-11')
            .copyWith(
              color: theme.color('--dsw-alias-label-tertiary'),
              height: 15 / 11,
            ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.item,
    required this.selected,
    required this.dense,
    required this.onTap,
  });

  final DshMenuItem item;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final item = widget.item;
    final ink = item.danger
        ? theme.color('--dsw-alias-state-error-primary')
        : theme.labelPrimary;
    final iconInk = item.danger
        ? theme.color('--dsw-alias-state-error-primary')
        : theme.color('--dsw-alias-menu-icon');
    final hover = _hover && !item.disabled;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: item.disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: Semantics(
        button: true,
        enabled: !item.disabled,
        selected: widget.selected,
        label: item.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: item.disabled ? null : widget.onTap,
          child: Opacity(
            opacity: item.disabled ? 0.4 : 1,
            child: DshContainer(
              constraints: BoxConstraints(minHeight: widget.dense ? 30 : 34),
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: widget.dense ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: hover
                    ? (item.danger
                          ? theme.color(
                              '--dsw-alias-interactive-bg-hover-danger',
                            )
                          : theme.interactiveBgHover)
                    : null,
                borderRadius: BorderRadius.circular(theme.radiusMd),
              ),
              child: Row(
                children: [
                  if (item.icon != null) ...[
                    DshIcon(item.icon!, size: 14, color: iconInk),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: DshChromeText(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .textStyle('--dsw-font-xs-13')
                          .copyWith(color: ink, height: 20 / 13),
                    ),
                  ),
                  if (widget.selected) ...[
                    const SizedBox(width: 6),
                    DshIcon(
                      DshIcons.check,
                      size: 14,
                      color: theme.labelPrimary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
