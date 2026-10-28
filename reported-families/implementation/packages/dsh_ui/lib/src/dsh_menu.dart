import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dsh_anchored_panel.dart';
import 'dsh_icon_data.dart';
import 'dsh_menu_item.dart';
import 'dsh_menu_footer.dart';
import 'dsh_menu_follower.dart';
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
    this.shortcut,
    this.onSelect,
  });

  final String label;
  final DshIconData? icon;
  final bool danger;
  final bool disabled;
  final DshMenuShortcut? shortcut;

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
    this.footer = const [],
    this.align = DshMenuAlign.start,
    this.dense = false,
    this.minWidth = DshMenuRecipe.minWidth,
    this.compact = false,
    this.selectionFill = false,
    this.controller,
    this.frameOverlayTop,
  });

  /// Draws the anchor; call [DshPanelController.toggle] to open the card.
  final Widget Function(BuildContext context, DshPanelController controller)
  builder;
  final List<DshMenuEntry> entries;

  /// Entries pinned outside the scrolling items, as in the source Menu.
  final List<DshMenuEntry> footer;
  final ValueChanged<String> onSelect;
  final List<String> selectedIds;
  final DshMenuAlign align;
  final bool dense, compact, selectionFill;
  final double minWidth;
  final DshPanelController? controller;

  /// The source `--dsh-frame-overlay-top`, when a desktop frame reserves space.
  final double? frameOverlayTop;

  @override
  Widget build(BuildContext context) => DshAnchoredPanel(
    controller: controller,
    gap: DshMenuRecipe.anchorGap,
    menuViewport: true,
    frameOverlayTop: frameOverlayTop,
    align: align == DshMenuAlign.end ? DshPanelAlign.end : DshPanelAlign.start,
    builder: builder,
    panelBuilder: (context, panel) => DshMenuCard(
      key: const ValueKey('dsh-menu'),
      entries: entries,
      footer: footer,
      frameOverlayTop: frameOverlayTop,
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
    this.footer = const [],
    this.dense = false,
    this.compact = false,
    this.selectionFill = false,
    this.autofocus = false,
    this.minWidth = DshMenuRecipe.minWidth,
    this.onDismiss,
    this.frameOverlayTop,
  });
  final List<DshMenuEntry> entries;
  final List<DshMenuEntry> footer;
  final ValueChanged<String> onSelect;
  final List<String> selectedIds;
  final bool dense, compact, selectionFill, autofocus;
  final double minWidth;
  final VoidCallback? onDismiss;
  final double? frameOverlayTop;
  @override
  State<DshMenuCard> createState() => _DshMenuCardState();
}

class _DshMenuCardState extends State<DshMenuCard> {
  final _containerFocus = FocusNode(skipTraversal: true);
  final _rowFocus = <String, FocusNode>{};
  int? _walkIndex;
  List<DshMenuItem> get enabled => [
    ...widget.entries,
    ...widget.footer,
  ].whereType<DshMenuItem>().where((e) => !e.disabled).toList();
  FocusNode node(String id) => _rowFocus.putIfAbsent(id, () {
    final focus = FocusNode();
    focus.addListener(() {
      if (!focus.hasFocus) return;
      final context = focus.context;
      final object = context?.findRenderObject();
      if (context == null || object == null) return;
      final position = Scrollable.maybeOf(context)?.position;
      // Browser focus reveals a row in either direction, without moving an
      // already visible row or scrolling the pinned footer's siblings.
      position?.ensureVisible(
        object,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      position?.ensureVisible(
        object,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
    return focus;
  });
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
      maxHeight: math.max(
        0,
        MediaQuery.sizeOf(context).height -
            dshMenuSafeInsetsOf(context).vertical -
            DshMenuRecipe.viewportBottomMargin -
            math.max(
              DshMenuRecipe.viewportTopMargin,
              widget.frameOverlayTop ?? DshMenuRecipe.frameOverlayTopFallback,
            ),
      ),
    ),
    child: DshMenuSurface(
      compact: widget.compact,
      child: Focus(
        focusNode: _containerFocus,
        autofocus: widget.autofocus,
        onKeyEvent: (_, event) => key(event),
        child: Semantics(
          container: true,
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: entries(widget.entries),
                    ),
                  ),
                ),
                if (widget.footer.isNotEmpty)
                  DshMenuFooter(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: entries(widget.footer),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> entries(List<DshMenuEntry> items) => [
    for (var i = 0; i < items.length; i++)
      switch (items[i]) {
        DshMenuSeparator() =>
          i == 0 || items[i - 1] is DshMenuSeparator
              ? const SizedBox.shrink()
              : DshMenuSeparatorLine(compact: widget.compact),
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
          shortcut: item.shortcut,
          focusNode: node(item.id),
          onPressed: () => select(item),
        ),
      },
  ];
}

/// The canonical divider for arbitrary-content menus.
class DshMenuSeparatorLine extends StatelessWidget {
  const DshMenuSeparatorLine({super.key, this.compact = false});
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
