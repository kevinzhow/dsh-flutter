import 'package:dsh_ui/dsh_ui.dart';
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
class PickerMenu extends StatelessWidget {
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
  Widget build(BuildContext context) => DshMenuFollower(
    link: link,
    child: TapRegion(
      // The trigger owns its toggle, including its outside-tap group.
      groupId: link,
      onTapOutside: (_) => onClose(),
      child: FocusScope(
        autofocus: true,
        child: DshMenuCard(
          key: const ValueKey('workspace-menu'),
          entries: [for (final row in rows) _entry(row)],
          footer: [for (final row in footer) _entry(row)],
          selectedIds: [if (selectedId != null) selectedId!],
          autofocus: true,
          onSelect: onSelect,
          onDismiss: onClose,
        ),
      ),
    ),
  );

  DshMenuItem _entry(PickerRow row) =>
      DshMenuItem(row.id, row.label, icon: row.icon, disabled: row.disabled);
}
