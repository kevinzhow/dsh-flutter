import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One row of the picker menu.
class PickerRow {
  const PickerRow({
    required this.id,
    required this.label,
    required this.icon,
    this.disabled = false,
  });

  final String id;
  final String label;
  final DshIconData icon;
  final bool disabled;
}

/// dsh's anchored `Menu` as the workspace picker uses it (wide windows): a
/// translucent card that opens below its anchor, rows of 34px with a leading
/// folder, the selected one marked by a trailing check, and the add action
/// pinned under a hairline below the scrolling rows.
///
/// Keyboard: Up and Down walk the rows (wrapping), Home and End jump, Enter,
/// Space and Tab settle the focused row, Escape and Shift+Tab close.
class PickerMenu extends StatefulWidget {
  const PickerMenu({
    super.key,
    required this.link,
    required this.rows,
    required this.footer,
    required this.selectedId,
    required this.onSelect,
    required this.onClose,
  });

  final LayerLink link;
  final List<PickerRow> rows;
  final List<PickerRow> footer;
  final String? selectedId;

  final void Function(String id) onSelect;
  final VoidCallback onClose;

  @override
  State<PickerMenu> createState() => _PickerMenuState();
}

class _PickerMenuState extends State<PickerMenu> {
  final _focusNodes = <String, FocusNode>{};
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'workspace-menu');

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _scope.dispose();
    super.dispose();
  }

  List<FocusNode> _rowNodes() => [
    for (final n in _scope.traversalDescendants)
      if (n.debugLabel?.startsWith('picker-row') ?? false) n,
  ];

  void _walk(int delta) {
    final nodes = _rowNodes();
    if (nodes.isEmpty) return;
    final at = nodes.indexWhere((n) => n.hasPrimaryFocus);
    final next = at == -1
        ? (delta > 0 ? 0 : nodes.length - 1)
        : (at + delta) % nodes.length;
    nodes[next].requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab &&
        HardwareKeyboard.instance.isShiftPressed) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _walk(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _walk(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _rowNodes().firstOrNull?.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _rowNodes().lastOrNull?.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The card grows with its widest row between 144 and 360 (dsh's `min-width`
  /// and `max-width`): padding, icon and gap, the label as laid out, and the
  /// trailing check of the selected row.
  double _width(BuildContext context) {
    final theme = context.dsh;
    final style = theme
        .textStyle(DshMenuRecipe.fontToken)
        .copyWith(height: DshMenuRecipe.lineHeight / DshMenuRecipe.fontSize);
    var widest = 0.0;
    for (final row in [...widget.rows, ...widget.footer]) {
      final painter = TextPainter(
        text: TextSpan(text: row.label, style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      final check = row.id == widget.selectedId
          ? DshMenuRecipe.gap + DshMenuRecipe.iconSize
          : 0;
      final w =
          DshMenuRecipe.horizontalPadding * 2 +
          DshMenuRecipe.iconSize +
          DshMenuRecipe.gap +
          painter.width +
          check;
      painter.dispose();
      if (w > widest) widest = w;
    }
    // A status line has its own natural width as well.
    return (widest + DshMenuRecipe.padding * 2).clamp(
      DshMenuRecipe.minWidth,
      DshMenuRecipe.maxWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final menu = TapRegion(
      // The chip that opened the menu shares the group: pressing it again is
      // its own toggle, not an outside tap.
      groupId: widget.link,
      onTapOutside: (_) => widget.onClose(),
      child: FocusScope(
        node: _scope,
        autofocus: true,
        onKeyEvent: _onKey,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: DshMenuRecipe.minWidth,
            maxWidth: DshMenuRecipe.maxWidth,
            // The card stops 12px short of the window's edges; taller content
            // scrolls and keeps the pinned footer in view.
            maxHeight: (screen.height - 24).clamp(0.0, 520.0),
          ),
          child: SizedBox(
            width: _width(context),
            child: DshMenuSurface(
              key: const ValueKey('workspace-menu'),
              child: Semantics(
                container: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [for (final row in widget.rows) _row(row)],
                        ),
                      ),
                    ),
                    if (widget.footer.isNotEmpty)
                      DshMenuFooter(
                        separated: widget.rows.isNotEmpty,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final row in widget.footer) _row(row),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return CompositedTransformFollower(
      link: widget.link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, 4),
      child: Align(
        alignment: Alignment.topLeft,
        // The menu hangs from the anchor, never wider than the window.
        child: menu,
      ),
    );
  }

  Widget _row(PickerRow row) => DshMenuItemButton(
    key: ValueKey('workspace-row-${row.id}'),
    label: row.label,
    icon: row.icon,
    disabled: row.disabled,
    selected: row.id == widget.selectedId,
    focusNode: _focusNodes.putIfAbsent(
      row.id,
      () => FocusNode(debugLabel: 'picker-row-${row.id}'),
    ),
    onPressed: () => widget.onSelect(row.id),
  );
}
