import '../engine/types.dart';

/// Every string the kit renders, already localized by the embedder (dsh
/// `DockLabels`). Accessible names are included: a control with no visible text
/// still needs one, and the kit must not invent it.
class DockLabels {
  const DockLabels({
    required this.emptyPane,
    required this.splitPane,
    this.splitPaneKeys,
    required this.splitPaneDisabled,
    required this.splitPaneNarrow,
    required this.closeTab,
    this.closeTabKeys,
    required this.addTab,
    required this.dropZone,
  });

  /// Body of a pane holding no tabs.
  final String emptyPane;

  /// The split control, while splitting is allowed.
  final String splitPane;

  /// Effective split keys shown as separate tooltip keycaps.
  final List<String>? splitPaneKeys;

  /// The split control, once the pane budget is spent.
  final String splitPaneDisabled;

  /// The split control, while the pane is too narrow for two working halves.
  final String splitPaneNarrow;

  /// Destroy a tab: the chip's close control and the menu's close item.
  final String closeTab;

  /// Effective close keys shown as separate tooltip keycaps.
  final List<String>? closeTabKeys;

  /// The strip's add control, which seats the embedder's seeded tab.
  final String addTab;

  /// The drop hint's caption for each body zone a dragged tab can land on.
  final Map<DockZone, String> dropZone;
}
