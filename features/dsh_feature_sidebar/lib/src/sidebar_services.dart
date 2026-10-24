import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

/// What the sidebar shell needs from the composition root.
abstract interface class SidebarServices {
  /// The copy dictionary in the current language.
  DshI18n get i18n;

  /// `ctx.layout`: the sidebar toggle and the global panel selection.
  LayoutController get layout;

  /// Start a New Session (the shell's New Session button and shortcut).
  void startSession();

  /// The product name drawn in the brand row.
  String get brandName;

  /// The browsing region between the panel entries and the foot: the workspace
  /// browser, drawn for the column's current shape.
  Widget browsingRegion(BuildContext context, SidebarSectionOwner owner);

  /// The window's shortcut service, for tooltips and the New Session command.
  ShortcutService? get shortcuts;
}
