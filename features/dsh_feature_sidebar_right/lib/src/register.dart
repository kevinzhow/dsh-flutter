import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:flutter/widgets.dart';

import 'panel.dart';
import 'state.dart';

/// What the sidebar needs from the composition root.
abstract interface class SidebarServices {
  /// The app navigator: the phone presentation is a sheet pushed onto it.
  GlobalKey<NavigatorState> get navigatorKey;

  /// `ctx.layout`, which the right column reports its presentation to inside
  /// the desktop frame; null where there is no frame.
  LayoutController? get layout;

  /// The window's shortcut service: the sidebar commands and the keys shown on
  /// its controls; null where there is none.
  ShortcutService? get shortcuts;
}

/// Width below which dsh presents the panel fullscreen on its own (a phone).
const double phoneWidth = 768;

/// The right sidebar as other features and the app reach it.
class SidebarRightFeature {
  SidebarRightFeature._(this._slots, this._i18n, this._services);

  final SlotRegistry _slots;
  final DshI18n Function() _i18n;
  final SidebarServices _services;
  final Map<String, SidebarState> _states = {};

  /// The sidebar state of [sessionId] (created on first use).
  SidebarState stateFor(String sessionId) => _states.putIfAbsent(
    sessionId,
    () => SidebarState(
      sessionId,
      types: _slots.sidebarTabs,
      guideTitle: () => _i18n().t('sidebarRight', 'tab.guide.title'),
    ),
  );

  /// Forget every session's sidebar (the host was left).
  void reset() => _states.clear();

  bool _inline(BuildContext context) =>
      DshRightbarHost.owned(context) ||
      MediaQuery.sizeOf(context).width >= sidebarInlineMinWindowWidth;

  /// Show or hide the sidebar of [owner]'s session: a column on wide windows
  /// (the frame's right column on the desktop shell), a sheet otherwise.
  void toggle(BuildContext context, SessionOwner owner) {
    final state = stateFor(owner.sessionId);
    if (_inline(context)) {
      state.toggleExpanded();
    } else {
      unawaited(_sheet(context, owner));
    }
  }

  /// Open the preview of [path] (absolute or workspace-relative) at [line],
  /// showing the sidebar if it is closed (the tool cards' `openFile`).
  void openFile(SessionOwner owner, String path, {int? line}) {
    openResource(
      owner,
      fileAddressFor(owner.sessionId, owner.cwd, path),
      line: line,
    );
  }

  /// Open a feature-registered resource, with in-memory navigation parameters.
  void openResource(
    SessionOwner owner,
    String address, {
    int? line,
    Map<String, Object?> params = const {},
  }) {
    final state = stateFor(owner.sessionId);
    state.openResource(address, line: line, params: params);
    final context = _services.navigatorKey.currentContext;
    if (context == null) return;
    if (_inline(context)) {
      state.setExpanded(true);
    } else if (!_sheetOpen.contains(owner.sessionId)) {
      unawaited(_sheet(context, owner));
    }
  }

  final Set<String> _sheetOpen = {};

  Future<void> _sheet(BuildContext context, SessionOwner owner) async {
    if (!_sheetOpen.add(owner.sessionId)) return;
    final theme = context.dsh;
    final state = stateFor(owner.sessionId);
    if (state.layout.tabs.isEmpty) state.setExpanded(true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: theme.bgBase,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(theme.radiusPanel),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        // Full screen, as dsh presents the panel below 768px, and above the
        // on-screen keyboard (a terminal needs the room its keys leave).
        builder: (sheet) => MediaQuery.removeViewInsets(
          context: sheet,
          removeBottom: true,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheet).bottom,
            ),
            child: SizedBox(
              key: const ValueKey('sidebar-sheet'),
              height: double.infinity,
              child: SidebarPanel(
                state: state,
                owner: owner,
                slots: _slots,
                i18n: _i18n(),
                showFullscreen: false,
                shortcuts: _services.shortcuts,
                onCollapse: () => Navigator.of(sheet).pop(),
              ),
            ),
          ),
        ),
      );
    } finally {
      _sheetOpen.remove(owner.sessionId);
    }
  }

  /// The session whose sidebar commands act on (set by the app: the open one).
  SessionOwner? Function() currentSession = () => null;

  void _registerCommands() {
    final shortcuts = _services.shortcuts;
    if (shortcuts == null) return;
    String t(String key) => _i18n().t('sidebarRight', key);
    SidebarState? current() {
      final owner = currentSession();
      return owner == null ? null : stateFor(owner.sessionId);
    }

    ShortcutCommand command({
      required String id,
      required String Function() label,
      required List<String> aliases,
      required ShortcutBinding binding,
      required ShortcutResolution Function() resolve,
    }) => ShortcutCommand(
      id: id,
      label: label,
      aliases: aliases,
      defaults: {
        for (final p in ['desktop:macos', 'desktop:windows', 'desktop:linux'])
          p: binding,
        for (final p in ['web:macos', 'web:windows']) p: binding,
      },
      regions: ShortcutRegion.values,
      resolve: (_) => resolve(),
    );
    _commandOffs.addAll([
      shortcuts.register(
        ShortcutCommand(
          id: 'sidebar.right.toggle',
          label: () => t('command.toggle'),
          aliases: const ['right sidebar', 'toggle right panel'],
          defaults: {
            for (final p in [
              'desktop:macos',
              'desktop:windows',
              'desktop:linux',
            ])
              p: const ShortcutBinding('KeyB', [
                ShortcutModifier.primary,
                ShortcutModifier.alt,
              ]),
            for (final p in ['web:macos', 'web:windows'])
              p: const ShortcutBinding('KeyB', [
                ShortcutModifier.primary,
                ShortcutModifier.shift,
              ]),
          },
          regions: ShortcutRegion.values,
          resolve: (_) {
            final state = current();
            if (state == null) return ShortcutBlocked(t('command.noSession'));
            return ShortcutHandled(state.toggleExpanded);
          },
        ),
      ),
      shortcuts.register(
        command(
          id: 'pane.split',
          label: () => t('dock.splitPane'),
          aliases: const ['split', 'panel'],
          binding: const ShortcutBinding('Backslash', [
            ShortcutModifier.primary,
          ]),
          resolve: () {
            final state = current();
            if (state == null || !state.expanded) {
              return ShortcutBlocked(
                t(state == null ? 'command.noFocus' : 'command.collapsed'),
              );
            }
            if (!state.dock.snapshot.canSplit) {
              return ShortcutBlocked(t('command.budget'));
            }
            return ShortcutHandled(
              () => state.dock.splitPane(state.dock.activeDockPaneId()),
            );
          },
        ),
      ),
      shortcuts.register(
        command(
          id: 'pane.fullscreen.toggle',
          label: () => t('command.fullscreen'),
          aliases: const ['fullscreen', 'panel'],
          binding: const ShortcutBinding('Enter', [
            ShortcutModifier.primary,
            ShortcutModifier.alt,
          ]),
          resolve: () {
            final state = current();
            if (state == null || !state.expanded) {
              return ShortcutBlocked(
                t(state == null ? 'command.noFocus' : 'command.collapsed'),
              );
            }
            return ShortcutHandled(state.toggleFullscreen);
          },
        ),
      ),
    ]);
  }

  final List<void Function()> _commandOffs = [];

  /// Withdraw the commands.
  void dispose() {
    for (final off in _commandOffs.reversed) {
      off();
    }
    _commandOffs.clear();
  }
}

/// Occupy `conversation.session.header.actions` with the button that opens the
/// sidebar and `rightbar.session` with the right column's seat.
SidebarRightFeature registerSidebarRightFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  required SidebarServices services,
}) {
  final feature = SidebarRightFeature._(slots, i18n, services);
  feature._registerCommands();
  slots.register<SessionOwner, Widget>(
    DshSlots.conversationSessionHeaderCorner.typed<SessionOwner, Widget>(),
    (owner) => _SidebarButton(
      feature: feature,
      owner: owner,
      i18n: i18n,
      services: services,
    ),
  );
  slots.register<SessionOwner, Widget>(
    DshSlots.rightbarSession.typed<SessionOwner, Widget>(),
    (owner) => RightbarSeat(
      feature: feature,
      owner: owner,
      slots: slots,
      i18n: i18n,
      services: services,
    ),
  );
  return feature;
}

/// The right column's seat of one session (dsh `RightbarSeat`): the panel
/// anchored to the frame's right edge at the width the frame solved, or
/// covering the frame in fullscreen; and the place where the frame learns the
/// presentation (shown, track, fullscreen) through `ctx.layout`.
class RightbarSeat extends StatefulWidget {
  const RightbarSeat({
    super.key,
    required this.feature,
    required this.owner,
    required this.slots,
    required this.i18n,
    required this.services,
  });

  final SidebarRightFeature feature;
  final SessionOwner owner;
  final SlotRegistry slots;
  final DshI18n Function() i18n;
  final SidebarServices services;

  @override
  State<RightbarSeat> createState() => _RightbarSeatState();
}

class _RightbarSeatState extends State<RightbarSeat> {
  ({bool shown, bool track, bool fullscreen})? _reported;

  SidebarState get state => widget.feature.stateFor(widget.owner.sessionId);

  @override
  void dispose() {
    // Leaving is part of the report: a seat that goes away with its session
    // hands the track back.
    widget.services.layout?.closeRightbar();
    super.dispose();
  }

  void _report(bool shown, bool track, bool fullscreen) {
    final next = (shown: shown, track: track, fullscreen: fullscreen);
    if (_reported == next) return;
    _reported = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final layout = widget.services.layout;
      if (!mounted || layout == null) return;
      if (next.shown) {
        layout.openRightbar(next.track, next.fullscreen);
      } else {
        layout.closeRightbar();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final geometry = DshRightbarGeometry.maybeOf(context);
        final shown = state.expanded;
        if (geometry == null) {
          // No frame: the legacy column beside the conversation on a wide window.
          if (!shown ||
              MediaQuery.sizeOf(context).width < sidebarInlineMinWindowWidth) {
            return const SizedBox.shrink();
          }
          return SizedBox(
            key: const ValueKey('sidebar-inline'),
            width: sidebarInlineWidth,
            child: _panel(bordered: true, showFullscreen: false),
          );
        }
        final auto = geometry.viewportWidth < phoneWidth;
        final fullscreen = auto || state.fullscreen;
        final track = shown && !auto;
        if (shown && !fullscreen && !geometry.canShow) {
          // Insufficient room closes the panel; it never reopens on widening.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) state.setExpanded(false);
          });
        }
        _report(shown, track, fullscreen);
        if (!shown) return const SizedBox.shrink();
        if (fullscreen) {
          return SizedBox.expand(
            key: const ValueKey('sidebar-fullscreen-panel'),
            child: _panel(bordered: false, showFullscreen: !auto),
          );
        }
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            key: const ValueKey('sidebar-inline'),
            width: geometry.width,
            child: _panel(bordered: true, showFullscreen: true),
          ),
        );
      },
    );
  }

  Widget _panel({required bool bordered, required bool showFullscreen}) =>
      SidebarPanel(
        state: state,
        owner: widget.owner,
        slots: widget.slots,
        i18n: widget.i18n(),
        bordered: bordered,
        showFullscreen: showFullscreen,
        shortcuts: widget.services.shortcuts,
        onCollapse: () => state.setExpanded(false),
      );
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.feature,
    required this.owner,
    required this.i18n,
    required this.services,
  });

  final SidebarRightFeature feature;
  final SessionOwner owner;
  final DshI18n Function() i18n;
  final SidebarServices services;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final state = feature.stateFor(owner.sessionId);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        // Inside the frame the button is the way back in while the panel is
        // hidden; while it is shown the panel's own collapse button leads out.
        if (DshRightbarHost.owned(context) && state.expanded) {
          return const SizedBox.shrink();
        }
        if (DshRightbarHost.owned(context)) {
          return _ExpandButton(
            label: i18n().t('sidebarRight', 'chrome.expand'),
            aria: i18n().t('sidebarRight', 'chrome.expandAria'),
            keys: _toggleKeys(services),
            onPressed: () => feature.toggle(context, owner),
          );
        }
        return Semantics(
          button: true,
          label: i18n().t('sidebarRight', 'chrome.expandAria'),
          child: GestureDetector(
            key: const ValueKey('sidebar-open'),
            behavior: HitTestBehavior.opaque,
            onTap: () => feature.toggle(context, owner),
            child: SizedBox(
              width: DshSpace.touch,
              height: DshSpace.touch,
              child: Center(
                child: DshIcon(
                  DshIcons.folderClose,
                  size: 20,
                  color: theme.labelSecondary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

List<String>? _toggleKeys(SidebarServices services) {
  final entry = services.shortcuts?.registry.entry('sidebar.right.toggle');
  return entry == null || entry.keys.isEmpty ? null : entry.keys;
}

/// The corner seat's way back into the hidden panel (dsh `ExpandButton`): the
/// left sidebar's collapse glyph mirrored, in a 28px button.
class _ExpandButton extends StatefulWidget {
  const _ExpandButton({
    required this.label,
    required this.aria,
    required this.keys,
    required this.onPressed,
  });

  final String label;
  final String aria;
  final List<String>? keys;
  final VoidCallback onPressed;

  @override
  State<_ExpandButton> createState() => _ExpandButtonState();
}

class _ExpandButtonState extends State<_ExpandButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshTooltip(
      label: widget.label,
      shortcutKeys: widget.keys,
      side: DshTooltipSide.bottom,
      delay: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: widget.aria,
          excludeSemantics: true,
          child: GestureDetector(
            key: const ValueKey('sidebar-open'),
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
              child: Transform.flip(
                flipX: true,
                child: DshIcon(
                  DshShellIcons.panelLeft,
                  size: 15,
                  color: theme.labelSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
