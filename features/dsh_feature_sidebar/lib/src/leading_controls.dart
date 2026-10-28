import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'sidebar_root.dart';
import 'sidebar_services.dart';

/// Window-chrome controls for the hidden sidebar (dsh `HeaderLeadingControls`,
/// the frame's `shell.leading` seat): on macOS the open-sidebar and New Session
/// controls beside the traffic lights; on Windows the sidebar toggle (always,
/// in the caption row) and New Session while the sidebar is collapsed.
class SidebarLeadingControls extends StatefulWidget {
  const SidebarLeadingControls({
    super.key,
    required this.services,
    required this.collapsed,
  });

  final SidebarServices services;

  /// Whether the sidebar is closed (Windows adds New Session then).
  final bool collapsed;

  @override
  State<SidebarLeadingControls> createState() => _SidebarLeadingControlsState();
}

class _SidebarLeadingControlsState extends State<SidebarLeadingControls> {
  void Function()? _keys;

  @override
  void initState() {
    super.initState();
    _keys = widget.services.shortcuts?.subscribe(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _keys?.call();
    super.dispose();
  }

  List<String>? _keysOf(String id) {
    final entry = widget.services.shortcuts?.registry.entry(id);
    return entry == null || entry.keys.isEmpty ? null : entry.keys;
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ShellScope.of(context);
    final services = widget.services;
    String t(String key) => services.i18n.t('sidebar', key);
    final toggleLabel = t(widget.collapsed ? 'toggle.open' : 'toggle.collapse');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Control(
          key: const ValueKey('leading-toggle'),
          icon: DshShellIcons.panelLeft,
          label: toggleLabel,
          keys: _keysOf(sidebarToggleCommand),
          side: chrome.windowsTitlebar
              ? DshTooltipSide.bottom
              : DshTooltipSide.right,
          onPressed: services.layout.toggleSidebar,
        ),
        if (!chrome.windowsTitlebar || widget.collapsed) ...[
          const SizedBox(width: DshHeaderLeadingRecipe.controlsGap),
          _Control(
            key: const ValueKey('leading-new-session'),
            icon: DshShellIcons.newChatRegular,
            label: t('session.new.label'),
            keys: _keysOf(sessionNewCommand),
            side: chrome.windowsTitlebar
                ? DshTooltipSide.bottom
                : DshTooltipSide.right,
            onPressed: services.startSession,
          ),
        ],
      ],
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    super.key,
    required this.icon,
    required this.label,
    required this.keys,
    required this.side,
    required this.onPressed,
  });

  final DshIconData icon;
  final String label;
  final List<String>? keys;
  final DshTooltipSide side;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DshTooltip(
      label: label,
      shortcutKeys: keys,
      side: side,
      delay: const Duration(
        milliseconds: DshHeaderLeadingRecipe.tooltipDelayMs,
      ),
      child: DshButton(
        profile: DshButtonProfile.headerAction,
        semanticLabel: label,
        onPressed: onPressed,
        child: DshIcon(icon, size: DshHeaderLeadingRecipe.iconSize),
      ),
    );
  }
}
