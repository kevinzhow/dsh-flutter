import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'guide.dart';
import 'state.dart';

/// The body slot as this feature uses it.
final Slot<SidebarTabOwner, Widget> paneTabSlot = DshSlots.sidebarRightPaneTab
    .typed<SidebarTabOwner, Widget>();

/// A tab's title as its chip shows it (a live terminal name).
final Slot<SidebarTabOwner, Widget> paneTabTitleSlot = DshSlots
    .sidebarRightPaneTabTitle
    .typed<SidebarTabOwner, Widget>();

/// One provider's card on the guide page.
final Slot<SidebarGuideOwner, Widget> guideEntrySlot = DshSlots
    .sidebarRightTabGuideEntry
    .typed<SidebarGuideOwner, Widget>();

/// The panel (dsh `SidebarPanel` over the docking kit): one or two panes, each a
/// tab strip over the body of its active tab, with the panel's two controls (the
/// presentation switch and the collapse button) at the far end of the top-right
/// strip. Bodies of kept types stay mounted while another tab is in front, so
/// what a person scrolled or expanded is still there when they come back.
class SidebarPanel extends StatelessWidget {
  const SidebarPanel({
    super.key,
    required this.state,
    required this.owner,
    required this.slots,
    required this.i18n,
    required this.onCollapse,
    this.bordered = false,
    this.showFullscreen = true,
    this.shortcuts,
  });

  final SidebarState state;
  final SessionOwner owner;
  final SlotRegistry slots;
  final DshI18n i18n;
  final VoidCallback onCollapse;

  /// A hairline on the left edge (the column beside the conversation).
  final bool bordered;

  /// Whether the presentation switch is offered (not in the phone sheet, which
  /// is fullscreen already).
  final bool showFullscreen;

  /// For the effective keys shown on the controls.
  final ShortcutService? shortcuts;

  String _t(String key) => i18n.t('sidebarRight', key);

  List<String>? _keys(String id) {
    final entry = shortcuts?.registry.entry(id);
    return entry == null || entry.keys.isEmpty ? null : entry.keys;
  }

  String _title(SidebarTab tab) {
    if (tab.kind == filesTabKind) return i18n.t('sidebarFiles', 'type.label');
    if (tab.kind == guideTabKind) return _t('tab.guide.title');
    final address = parseSessionFileAddress(tab.contentId);
    return address == null
        ? (tab.title.isEmpty ? tab.contentId : tab.title)
        : pathPartsOf(address.path).name;
  }

  SidebarTabOwner _tabOwner(SidebarTab tab) => SidebarTabOwner(
    session: owner,
    id: tab.id,
    kind: tab.kind,
    contentId: tab.contentId,
    actions: state,
    params: tab.params,
    line: tab.line,
    revision: tab.revision,
    visible: state.isFront(tab.id),
  );

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final labels = DockLabels(
          emptyPane: _t('dock.emptyPane'),
          splitPane: _t('dock.splitPane'),
          splitPaneKeys: _keys('pane.split'),
          splitPaneDisabled: _t('dock.splitPaneDisabled'),
          splitPaneNarrow: _t('dock.splitPaneNarrow'),
          closeTab: _t('dock.closeTab'),
          addTab: _t('dock.addTab'),
          dropZone: {
            DockZone.center: _t('dock.drop.center'),
            DockZone.left: _t('dock.drop.left'),
            DockZone.right: _t('dock.drop.right'),
            DockZone.top: _t('dock.drop.top'),
            DockZone.bottom: _t('dock.drop.bottom'),
          },
        );
        return DshDecoratedBox(
          key: const ValueKey('sidebar-panel'),
          decoration: BoxDecoration(
            color: theme.bgBase,
            border: bordered
                ? Border(
                    left: BorderSide(
                      color: theme.color('--dsw-alias-border-l4'),
                      width: dshHairlineOf(context),
                    ),
                  )
                : null,
          ),
          child: DockLayout(
            controller: state.dock,
            labels: labels,
            canAddTab: state.canAddTab,
            canCloseTab: state.canClose,
            onCloseTab: (id) => state.close(id.value),
            keepMounted: (record) =>
                slots.sidebarTabs.typeOf(record.kind)?.keepMounted ?? false,
            horizontalDrops: true,
            chrome: _Chrome(
              state: state,
              showFullscreen: showFullscreen,
              collapseLabel: _t('chrome.collapseAria'),
              collapseTooltip: _t('chrome.collapse'),
              collapseKeys: _keys('sidebar.right.toggle'),
              fullscreenLabel: _t(
                state.fullscreen
                    ? 'chrome.exitFullscreen'
                    : 'chrome.toFullscreen',
              ),
              fullscreenKeys: _keys('pane.fullscreen.toggle'),
              onCollapse: onCollapse,
            ),
            renderTab: (context, record) {
              final tab = state.tabs.firstWhere((t) => t.id == record.id);
              if (tab.kind == guideTabKind) {
                return GuideBody(
                  key: const ValueKey('sidebar-guide'),
                  state: state,
                  tabId: tab.id,
                  owner: owner,
                  slots: slots,
                );
              }
              return slots.renderKeyed(paneTabSlot, tab.kind, _tabOwner(tab)) ??
                  Center(
                    child: DshChromeText(
                      _t('tab.unavailable'),
                      style: theme
                          .textStyle('--dsw-font-s-14')
                          .copyWith(color: theme.labelSecondary),
                    ),
                  );
            },
            renderTabTitle: (context, record) {
              final tab = state.tabs.firstWhere((t) => t.id == record.id);
              final custom = slots.renderKeyed(
                paneTabTitleSlot,
                tab.kind,
                _tabOwner(tab),
              );
              if (custom != null) return custom;
              return DshChromeText(
                _title(tab),
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: theme
                    .textStyle('--dsw-font-xs-13')
                    .copyWith(
                      color: tab.id == state.activeId
                          ? theme.labelPrimary
                          : theme.labelSecondary,
                      height: 1.4,
                    ),
              );
            },
          ),
        );
      },
    );
  }
}

/// The surface-wide controls at the far end of the top-right strip.
class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.state,
    required this.showFullscreen,
    required this.collapseLabel,
    required this.collapseTooltip,
    required this.collapseKeys,
    required this.fullscreenLabel,
    required this.fullscreenKeys,
    required this.onCollapse,
  });

  final SidebarState state;
  final bool showFullscreen;
  final String collapseLabel;
  final String collapseTooltip;
  final List<String>? collapseKeys;
  final String fullscreenLabel;
  final List<String>? fullscreenKeys;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showFullscreen) ...[
          _ChromeButton(
            key: const ValueKey('sidebar-fullscreen'),
            icon: state.fullscreen
                ? DshShellIcons.panelExitFullscreen
                : DshShellIcons.panelFullscreen,
            label: fullscreenLabel,
            keys: fullscreenKeys,
            onPressed: state.toggleFullscreen,
          ),
          const SizedBox(width: 8),
        ],
        _ChromeButton(
          key: const ValueKey('sidebar-collapse'),
          icon: DshShellIcons.panelLeft,
          mirrored: true,
          label: collapseLabel,
          tooltip: collapseTooltip,
          keys: collapseKeys,
          onPressed: onCollapse,
        ),
      ],
    );
  }
}

class _ChromeButton extends StatefulWidget {
  const _ChromeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.keys,
    this.mirrored = false,
  });

  final DshIconData icon;
  final String label;
  final String? tooltip;
  final List<String>? keys;
  final VoidCallback onPressed;
  final bool mirrored;

  @override
  State<_ChromeButton> createState() => _ChromeButtonState();
}

class _ChromeButtonState extends State<_ChromeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    Widget glyph = DshIcon(widget.icon, size: 16, color: theme.labelSecondary);
    if (widget.mirrored) {
      glyph = Transform.flip(flipX: true, child: glyph);
    }
    return DshTooltip(
      label: widget.tooltip ?? widget.label,
      shortcutKeys: widget.keys,
      side: DshTooltipSide.bottom,
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
              child: glyph,
            ),
          ),
        ),
      ),
    );
  }
}
