import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dsh_anchored_panel.dart';
import 'dsh_icon_data.dart';
import 'dsh_menu_item.dart';
import 'dsh_menu_surface.dart';
import 'dsh_recipes.g.dart';
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
    this.onSelect,
  });

  final String label;
  final DshIconData? icon;
  final bool danger;
  final bool disabled;

  /// A contributed row may own its action; the enclosing menu still closes.
  final VoidCallback? onSelect;
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
    this.minWidth = DshMenuRecipe.minWidth,
    this.compact = false,
    this.selectionFill = false,
    this.controller,
  });

  /// Draws the anchor; call [DshPanelController.toggle] to open the card.
  final Widget Function(BuildContext context, DshPanelController controller)
  builder;
  final List<DshMenuEntry> entries;
  final ValueChanged<String> onSelect;
  final List<String> selectedIds;
  final DshMenuAlign align;
  final bool dense, compact, selectionFill;
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
      compact: compact,
      selectionFill: selectionFill,
      autofocus: true,
      onDismiss: panel.close,
      minWidth: minWidth,
      onSelect: (id) {
        panel.close();
        onSelect(id);
      },
    ),
  );
}

/// Cards and contributed rows share the same material and row implementation.
class DshMenuCard extends StatefulWidget {
  const DshMenuCard({
    super.key,
    required this.entries,
    required this.onSelect,
    this.selectedIds = const [],
    this.dense = false,
    this.compact = false,
    this.selectionFill = false,
    this.autofocus = false,
    this.minWidth = DshMenuRecipe.minWidth,
    this.onDismiss,
  });
  final List<DshMenuEntry> entries;
  final ValueChanged<String> onSelect;
  final List<String> selectedIds;
  final bool dense, compact, selectionFill, autofocus;
  final double minWidth;
  final VoidCallback? onDismiss;
  @override
  State<DshMenuCard> createState() => _DshMenuCardState();
}

class _DshMenuCardState extends State<DshMenuCard> {
  final _containerFocus = FocusNode(skipTraversal: true);
  final _rowFocus = <String, FocusNode>{};
  int? _walkIndex;
  List<DshMenuItem> get enabled => widget.entries
      .whereType<DshMenuItem>()
      .where((e) => !e.disabled)
      .toList();
  FocusNode node(String id) => _rowFocus.putIfAbsent(id, () => FocusNode());
  @override
  void dispose() {
    _containerFocus.dispose();
    for (final n in _rowFocus.values) {
      n.dispose();
    }
    super.dispose();
  }

  void select(DshMenuItem item) {
    widget.onSelect(item.id);
    item.onSelect?.call();
  }

  KeyEventResult key(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final hardware = HardwareKeyboard.instance;
    if (hardware.isControlPressed ||
        hardware.isAltPressed ||
        hardware.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final rows = enabled;
    final focused = rows.indexWhere((row) => node(row.id).hasFocus);
    final key = event.logicalKey;
    if ((key == LogicalKeyboardKey.escape && !hardware.isShiftPressed) ||
        (key == LogicalKeyboardKey.tab && hardware.isShiftPressed)) {
      if (widget.onDismiss == null) return KeyEventResult.ignored;
      widget.onDismiss!();
      return KeyEventResult.handled;
    }
    if (rows.isEmpty) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.tab && focused >= 0) {
      select(rows[focused]);
      return KeyEventResult.handled;
    }
    final from = focused >= 0 ? focused : _walkIndex;
    final next = switch (key) {
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => rows.length - 1,
      LogicalKeyboardKey.arrowDown =>
        from == null ? 0 : (from + 1) % rows.length,
      LogicalKeyboardKey.arrowUp =>
        from == null ? rows.length - 1 : (from + rows.length - 1) % rows.length,
      LogicalKeyboardKey.tab => 0,
      _ => null,
    };
    if (next == null) return KeyEventResult.ignored;
    _walkIndex = next;
    node(rows[next].id).requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      minWidth: widget.compact && widget.minWidth == DshMenuRecipe.minWidth
          ? DshMenuRecipe.compactMinWidth
          : widget.minWidth,
      maxWidth: DshMenuRecipe.maxWidth,
    ),
    child: DshMenuSurface(
      compact: widget.compact,
      child: Focus(
        focusNode: _containerFocus,
        autofocus: widget.autofocus,
        onKeyEvent: (_, event) => key(event),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.entries.length; i++)
                switch (widget.entries[i]) {
                  DshMenuSeparator() =>
                    i == 0 || widget.entries[i - 1] is DshMenuSeparator
                        ? const SizedBox.shrink()
                        : _Separator(compact: widget.compact),
                  DshMenuLabel(:final id, :final text) => _Heading(
                    key: ValueKey('dsh-menu-label-$id'),
                    text: text,
                    dense: widget.dense,
                    compact: widget.compact,
                  ),
                  final DshMenuItem item => DshMenuItemButton(
                    key: ValueKey('dsh-menu-${item.id}'),
                    label: item.label,
                    icon: item.icon,
                    disabled: item.disabled,
                    danger: item.danger,
                    selected: widget.selectedIds.contains(item.id),
                    selectionFill: widget.selectionFill,
                    dense: widget.dense,
                    compact: widget.compact,
                    focusNode: node(item.id),
                    onPressed: () => select(item),
                  ),
                },
            ],
          ),
        ),
      ),
    ),
  );
}

class _Separator extends StatelessWidget {
  const _Separator({required this.compact});
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: compact
          ? DshMenuRecipe.compactSeparatorMargin
          : DshMenuRecipe.separatorHorizontalMargin,
      vertical: compact
          ? DshMenuRecipe.compactSeparatorMargin
          : DshMenuRecipe.separatorVerticalMargin,
    ),
    child: DshContainer(
      height: DshMenuRecipe.separatorWidth,
      decoration: BoxDecoration(
        color: context.dsh.color(DshMenuRecipe.separatorToken),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading({
    super.key,
    required this.text,
    required this.dense,
    required this.compact,
  });
  final String text;
  final bool dense, compact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: compact
          ? DshMenuRecipe.compactHeadingHorizontalPadding
          : DshMenuRecipe.headingHorizontalPadding,
      vertical: compact
          ? DshMenuRecipe.compactHeadingVerticalPadding
          : dense
          ? DshMenuRecipe.denseHeadingVerticalPadding
          : DshMenuRecipe.headingVerticalPadding,
    ),
    child: DshChromeText(
      text,
      style: context.dsh
          .textStyle(
            compact
                ? DshMenuRecipe.compactHeadingFontToken
                : DshMenuRecipe.headingFontToken,
          )
          .copyWith(
            color: context.dsh.color(DshMenuRecipe.headingToken),
            fontSize: compact ? DshMenuRecipe.compactHeadingFontSize : null,
            height: compact
                ? DshMenuRecipe.compactHeadingLineHeight /
                      DshMenuRecipe.compactHeadingFontSize
                : DshMenuRecipe.headingLineHeight /
                      DshMenuRecipe.headingFontSize,
          ),
    ),
  );
}
