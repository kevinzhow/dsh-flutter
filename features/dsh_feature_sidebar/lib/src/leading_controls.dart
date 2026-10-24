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
          const SizedBox(width: 8),
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

class _Control extends StatefulWidget {
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
  State<_Control> createState() => _ControlState();
}

class _ControlState extends State<_Control> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshTooltip(
      label: widget.label,
      shortcutKeys: widget.keys,
      side: widget.side,
      delay: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: widget.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: DshContainer(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hover ? theme.interactiveBgHover : null,
                borderRadius: BorderRadius.circular(theme.radiusSm),
              ),
              child: DshIcon(
                widget.icon,
                size: 16,
                color: theme.labelSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
