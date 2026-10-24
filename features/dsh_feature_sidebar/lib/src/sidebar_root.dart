/// The sidebar shell (dsh `ui-sidebar` `SidebarRoot.tsx`): the brand row, New
/// Session, the global panel entries, the browsing region and the foot, in the
/// wide column and in the 56px rail, with the window-chrome variants of macOS
/// (a 52px strip clearing the traffic lights, no rail) and Windows (controls in
/// the caption row).
library;

import 'dart:async';

import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'brand_mark.dart';
import 'sidebar_services.dart';

/// Wide-content unmount delay; matches the 150ms wide-content fade-out.
const Duration collapseSettle = Duration(milliseconds: 150);

/// The id of the command that opens a New Session.
const String sessionNewCommand = 'session.new';

/// The id of the command that toggles the left sidebar.
const String sidebarToggleCommand = 'sidebar.left.toggle';

/// The sidebar column of one window.
class SidebarRoot extends StatefulWidget {
  const SidebarRoot({
    super.key,
    required this.owner,
    required this.slots,
    required this.services,
  });

  final SidebarOwner owner;
  final SlotRegistry slots;
  final SidebarServices services;

  @override
  State<SidebarRoot> createState() => _SidebarRootState();
}

class _SidebarRootState extends State<SidebarRoot> {
  Timer? _settle;
  bool _settled = false;
  double _lastWide = 0;
  StreamSubscription<String>? _slotSub;
  void Function()? _keysSub;
  void Function()? _panelSub;

  @override
  void initState() {
    super.initState();
    _settled = widget.owner.collapsed;
    _lastWide = widget.owner.width;
    _slotSub = widget.slots.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _keysSub = widget.services.shortcuts?.subscribe(() {
      if (mounted) setState(() {});
    });
    _panelSub = widget.services.layout.store.subscribe(() {
      if (mounted) setState(() {});
    });
    if (widget.owner.collapsed) {
      _settled = true;
    }
  }

  @override
  void didUpdateWidget(SidebarRoot old) {
    super.didUpdateWidget(old);
    final collapsed = widget.owner.collapsed;
    if (collapsed != old.owner.collapsed) {
      _settle?.cancel();
      if (!collapsed) {
        _settled = false;
      } else {
        _settle = Timer(collapseSettle, () {
          if (mounted) setState(() => _settled = true);
        });
      }
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    unawaited(_slotSub?.cancel());
    _keysSub?.call();
    _panelSub?.call();
    super.dispose();
  }

  String _t(String key) => widget.services.i18n.t('sidebar', key);

  List<String>? _keys(String id) {
    final entry = widget.services.shortcuts?.registry.entry(id);
    return entry == null || entry.keys.isEmpty ? null : entry.keys;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final chrome = ShellScope.of(context);
    final owner = widget.owner;
    final collapsed = owner.collapsed;
    final windows = chrome.windowsTitlebar;
    final darwin = chrome.darwin;
    // Windows keeps its expanded content while collapsed (the column has no
    // rail); elsewhere the wide content stays until the fade settles.
    final wide = windows ? !collapsed : (!collapsed || !_settled);
    if (!collapsed) _lastWide = owner.width;
    final fading = collapsed && wide;
    final panels = widget.slots.entries(
      DshShellSlots.sidebarPanellist.typed<SidebarPanelIconOwner, Widget>(),
    );
    final info = widget.services.layout.panelInfo;
    final rail = !wide;
    final padding = windows && collapsed
        ? EdgeInsets.zero
        : rail
        ? const EdgeInsets.fromLTRB(10, 18, 10, 6)
        : const EdgeInsets.fromLTRB(12, 6, 12, 6);

    // A drawer closes once something in it was picked.
    void closeDrawer() {
      if (owner.drawer) widget.services.layout.closeNarrowSidebar();
    }

    VoidCallback picked(VoidCallback action) => () {
      action();
      closeDrawer();
    };

    final toggle = _Toggle(
      key: const ValueKey('sidebar-toggle'),
      wide: wide,
      collapsed: collapsed,
      windows: windows,
      label: _t(collapsed ? 'toggle.open' : 'toggle.collapse'),
      keys: _keys(sidebarToggleCommand),
      slots: widget.slots,
      onPressed: widget.services.layout.toggleSidebar,
    );

    final children = <Widget>[
      if (darwin)
        chrome.drag(
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
              child: Align(
                alignment: chrome.fullscreen
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: toggle,
              ),
            ),
          ),
        ),
      if (!(windows && collapsed))
        chrome.drag(
          _LogoRow(
            wide: wide,
            darwin: darwin,
            windows: windows,
            brandName: widget.services.brandName,
            slots: widget.slots,
            label: _t('session.new.label'),
            onNew: picked(widget.services.startSession),
            toggle: darwin || windows || owner.drawer ? null : toggle,
            topTuck: darwin,
          ),
        ),
      _NewSession(
        key: const ValueKey('sidebar-new-session'),
        wide: wide,
        windows: windows,
        darwin: darwin,
        label: _t('session.new'),
        aria: _t('session.new.label'),
        keys: _keys(sessionNewCommand),
        onPressed: picked(widget.services.startSession),
      ),
      if (panels.isNotEmpty)
        _PanelList(
          key: const ValueKey('sidebar-panels'),
          wide: wide,
          panels: panels,
          activeId: info.activePanelId,
          slots: widget.slots,
          onSelect: (id) {
            widget.services.layout.selectPanel(id);
            closeDrawer();
          },
        ),
      Expanded(
        child: Padding(
          padding: wide ? const EdgeInsets.only(left: 0) : EdgeInsets.zero,
          // dsh fills this region with the workspace browser; the composition
          // supplies it (`sidebar.workspaces` itself is the browser's add action).
          child: widget.services.browsingRegion(
            context,
            SidebarSectionOwner(
              wide: wide,
              expandSidebar: () {
                if (collapsed) widget.services.layout.toggleSidebar();
              },
              navigated: owner.drawer ? closeDrawer : null,
            ),
          ),
        ),
      ),
      _Foot(slots: widget.slots, wide: wide),
    ];

    Widget content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: rail
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.stretch,
        children: windows && collapsed ? const [SizedBox.shrink()] : children,
      ),
    );
    // The expanded content freezes at its width while it fades out, so the
    // sliding column clips it instead of reflowing it.
    if (fading || (wide && _lastWide > 0 && owner.width < _lastWide)) {
      content = OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: _lastWide,
        maxWidth: _lastWide,
        child: content,
      );
    }
    return DefaultTextStyle(
      style: theme
          .textStyle('--dsw-font-s-14')
          .copyWith(color: theme.labelPrimary),
      child: AnimatedOpacity(
        opacity: fading ? 0 : 1,
        duration: collapseSettle,
        curve: const Cubic(0.4, 0, 0.2, 1),
        child: content,
      ),
    );
  }
}

class _LogoRow extends StatelessWidget {
  const _LogoRow({
    required this.wide,
    required this.darwin,
    required this.windows,
    required this.brandName,
    required this.slots,
    required this.label,
    required this.onNew,
    required this.toggle,
    required this.topTuck,
  });

  final bool wide;
  final bool darwin;
  final bool windows;
  final String brandName;
  final SlotRegistry slots;
  final String label;
  final VoidCallback onNew;
  final Widget? toggle;
  final bool topTuck;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    // Rail: 36px, the toggle left, 12 below. Wide: 60px with 8/0/8/4 padding.
    final height = windows ? 40.0 : (wide ? 60.0 : 36.0);
    final mark =
        slots.renderSingle(
          DshShellSlots.sidebarBrandMark.typed<SidebarBrandMarkOwner, Widget>(),
          const SidebarBrandMarkOwner(size: 24),
        ) ??
        const WhaleeMark(size: 24);
    final name =
        slots.renderSingle(
          DshShellSlots.sidebarBrandName.typed<Object?, Widget>(),
          null,
        ) ??
        DshChromeText(
          brandName,
          maxLines: 1,
          style: theme
              .textStyle('--dsw-font-base-strong-16')
              .copyWith(color: theme.labelPrimary),
        );
    final identity = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 8),
        Flexible(child: name),
      ],
    );
    Widget brand = Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      button: !darwin,
      child: darwin
          ? Align(alignment: Alignment.centerLeft, child: identity)
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: const ValueKey('sidebar-brand'),
                behavior: HitTestBehavior.opaque,
                onTap: onNew,
                child: Align(alignment: Alignment.centerLeft, child: identity),
              ),
            ),
    );
    return Padding(
      padding: EdgeInsets.only(
        top: topTuck ? 0 : 0,
        bottom: windows || !wide ? (windows ? 0 : 12) : 4,
      ),
      child: SizedBox(
        height: wide || windows ? height - (topTuck ? 12 : 0) : height,
        child: Padding(
          padding: wide
              ? EdgeInsets.fromLTRB(
                  windows ? 8 : 4,
                  windows ? 0 : 8,
                  0,
                  windows ? 0 : 8,
                )
              : EdgeInsets.zero,
          child: Row(
            children: [
              if (wide) Expanded(child: brand),
              if (toggle != null) toggle!,
            ],
          ),
        ),
      ),
    );
  }
}

/// The sidebar toggle: a plain panel icon expanded, the brand mark on the rail
/// until hovered (then the expand glyph).
class _Toggle extends StatefulWidget {
  const _Toggle({
    super.key,
    required this.wide,
    required this.collapsed,
    required this.windows,
    required this.label,
    required this.keys,
    required this.slots,
    required this.onPressed,
  });

  final bool wide;
  final bool collapsed;
  final bool windows;
  final String label;
  final List<String>? keys;
  final SlotRegistry slots;
  final VoidCallback onPressed;

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final rail = !widget.wide && !widget.windows;
    final box = rail ? 36.0 : 28.0;
    final iconSize = rail ? 18.0 : 16.0;
    final ink = rail ? theme.labelPrimary : theme.labelSecondary;
    Widget glyph;
    if (rail && !_hover) {
      glyph =
          widget.slots.renderSingle(
            DshShellSlots.sidebarBrandMark
                .typed<SidebarBrandMarkOwner, Widget>(),
            const SidebarBrandMarkOwner(size: 24),
          ) ??
          const WhaleeMark(size: 24);
    } else {
      glyph = DshIcon(DshShellIcons.panelLeft, size: iconSize, color: ink);
    }
    final badge = rail
        ? widget.slots.renderSingle(
            DshShellSlots.sidebarToggleBadge.typed<Object?, Widget>(),
            null,
          )
        : null;
    return DshTooltip(
      label: widget.label,
      shortcutKeys: widget.keys,
      side: widget.windows ? DshTooltipSide.bottom : DshTooltipSide.right,
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
              width: box,
              height: box,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hover ? theme.interactiveBgHover : null,
                borderRadius: BorderRadius.circular(
                  rail ? theme.radiusMd : theme.radiusSm,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [glyph, ?badge],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewSession extends StatefulWidget {
  const _NewSession({
    super.key,
    required this.wide,
    required this.windows,
    required this.darwin,
    required this.label,
    required this.aria,
    required this.keys,
    required this.onPressed,
  });

  final bool wide;
  final bool windows;
  final bool darwin;
  final String label;
  final String aria;
  final List<String>? keys;
  final VoidCallback onPressed;

  @override
  State<_NewSession> createState() => _NewSessionState();
}

class _NewSessionState extends State<_NewSession> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final hairline = dshHairlineOf(context);
    if (!widget.wide) {
      // Windows draws the collapsed New Session in the caption (the leading
      // controls); the rail keeps a plain 36px icon control.
      if (widget.windows) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DshTooltip(
          label: widget.aria,
          shortcutKeys: widget.keys,
          delay: const Duration(milliseconds: 500),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            cursor: SystemMouseCursors.click,
            child: Semantics(
              button: true,
              label: widget.aria,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onPressed,
                child: DshContainer(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _hover ? theme.interactiveBgHover : null,
                    borderRadius: BorderRadius.circular(theme.radiusMd),
                  ),
                  child: DshIcon(
                    DshShellIcons.newChatRegular,
                    size: 18,
                    color: theme.labelPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final fill = widget.darwin
        ? theme
              .color('--dsw-static-neutral-bluish-00')
              .withValues(
                alpha: theme.brightness == Brightness.dark
                    ? (_hover ? 0.2 : 0.15)
                    : (_hover ? 0.3 : 0.55),
              )
        : _hover
        ? theme.color('--dsw-alias-button-floating-hover')
        : theme.color('--dsw-alias-button-elevated-fill');
    final style = theme
        .textStyle('--dsw-font-s-strong-14')
        .copyWith(color: theme.labelPrimary);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.windows ? 0 : 2,
        widget.windows ? 8 : 0,
        2,
        12,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: widget.aria,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: DshContainer(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(theme.radiusMd),
                border: Border.all(
                  color: theme.color('--dsw-alias-border-l3'),
                  width: hairline,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DshIcon(
                        DshShellIcons.newChatMedium,
                        size: 14,
                        color: theme.labelPrimary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: DshChromeText(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: style,
                        ),
                      ),
                    ],
                  ),
                  if (_hover && widget.keys != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: DshShortcutKeys(keys: widget.keys!),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelList extends StatelessWidget {
  const _PanelList({
    super.key,
    required this.wide,
    required this.panels,
    required this.activeId,
    required this.slots,
    required this.onSelect,
  });

  final bool wide;
  final List<SlotEntryInfo> panels;
  final String? activeId;
  final SlotRegistry slots;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    final slot = DshShellSlots.sidebarPanellist
        .typed<SidebarPanelIconOwner, Widget>();
    return Padding(
      padding: EdgeInsets.only(bottom: wide ? 8 : 12),
      child: Column(
        crossAxisAlignment: wide
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < panels.length; i++) ...[
            if (i > 0) SizedBox(height: wide ? 4 : 12),
            _PanelRow(
              key: ValueKey('sidebar-panel-${panels[i].id}'),
              wide: wide,
              label: panels[i].label ?? panels[i].id,
              active: panels[i].id == activeId,
              glyph: slots.renderOnly(
                slot,
                panels[i].id,
                SidebarPanelIconOwner(
                  size: wide ? 16 : 18,
                  active: panels[i].id == activeId,
                ),
              ),
              onTap: () => onSelect(panels[i].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _PanelRow extends StatefulWidget {
  const _PanelRow({
    super.key,
    required this.wide,
    required this.label,
    required this.active,
    required this.glyph,
    required this.onTap,
  });

  final bool wide;
  final String label;
  final bool active;
  final Widget? glyph;
  final VoidCallback onTap;

  @override
  State<_PanelRow> createState() => _PanelRowState();
}

class _PanelRowState extends State<_PanelRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final fill = widget.active || _hover ? theme.interactiveBgHover : null;
    final row = DshContainer(
      constraints: widget.wide ? const BoxConstraints(minHeight: 36) : null,
      width: widget.wide ? null : 36,
      height: widget.wide ? null : 36,
      margin: widget.wide ? const EdgeInsets.symmetric(horizontal: 2) : null,
      padding: widget.wide
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 7)
          : null,
      alignment: widget.wide ? null : Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(theme.radiusMd),
      ),
      child: Row(
        mainAxisSize: widget.wide ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: widget.wide
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          if (widget.glyph != null) widget.glyph!,
          if (widget.wide) ...[
            const SizedBox(width: 8),
            Flexible(
              child: DshChromeText(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme
                    .textStyle('--dsw-font-s-14')
                    .copyWith(color: theme.labelPrimary),
              ),
            ),
          ],
        ],
      ),
    );
    return DshTooltip(
      label: widget.label,
      disabled: widget.wide,
      delay: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          selected: widget.active,
          label: widget.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: row,
          ),
        ),
      ),
    );
  }
}

class _Foot extends StatelessWidget {
  const _Foot({required this.slots, required this.wide});

  final SlotRegistry slots;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final actions = slots.renderList(
      DshShellSlots.sidebarFooterAction.typed<SidebarFootOwner, Widget>(),
      SidebarFootOwner(wide: wide),
    );
    final settings = slots.renderSingle(
      DshShellSlots.sidebarSettings.typed<SidebarFootOwner, Widget>(),
      SidebarFootOwner(wide: wide),
    );
    return Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: [
        if (actions.isNotEmpty) Row(children: actions),
        ?settings,
      ],
    );
  }
}
