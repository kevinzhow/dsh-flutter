/// The settings shell of the desktop frame (dsh `ui-settings-general`
/// `SettingsRoot.tsx` and the account launcher): the sidebar-foot row that
/// opens the panel, the panel's modal, the `settings.*` seats it renders, the
/// `settings.open` command, and the "open the configuration file" action for a
/// host on this machine.
library;

import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'settings_dialog.dart';

/// What the settings shell needs from the composition root.
abstract interface class SettingsShellServices {
  /// The app navigator: the panel is a modal route pushed onto it.
  GlobalKey<NavigatorState> get navigatorKey;

  DshI18n get i18n;

  ShortcutService? get shortcuts;

  /// Whether the host runs on this machine, where the OS can open a file or a
  /// folder chooser for the user. Null service parts are simply not offered.
  bool get hostIsLocal;

  /// Whether the provider owns a settings document the host can open (dsh
  /// `describe().hasDocument`), and the open request itself. Null when the
  /// host offers none.
  SettingsDocumentOpener? get documentOpener;

  /// What the foot menu shows above its rows (the host and how the link to it
  /// is protected); null for none.
  Widget? moreMenuHeader(BuildContext context);

  /// The inset the frame keeps clear above dialogs.
  double get overlayTop;
}

/// The host's settings-document operations.
abstract interface class SettingsDocumentOpener {
  /// Whether the current provider has a document the host can open natively.
  Future<bool> available();

  /// Open it in the host's native editor; the message of a failure, or null.
  Future<String?> open();
}

/// The shell: one per window.
class SettingsShell extends ChangeNotifier {
  SettingsShell(this.slots, this.services);

  final SlotRegistry slots;
  final SettingsShellServices services;

  bool _open = false;

  /// Whether the panel is showing.
  bool get isOpen => _open;

  /// Open the panel (optionally on [section]); a no-op while it is open.
  Future<void> open({String? section}) async {
    final context = services.navigatorKey.currentContext;
    if (context == null || _open) return;
    _open = true;
    notifyListeners();
    final theme = context.dsh;
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: services.i18n.t('settings', 'close'),
        barrierColor: theme.color('--dsw-alias-bg-mask-1'),
        transitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => SettingsDialog(
          slots: slots,
          i18n: () => services.i18n,
          initialSection: section,
          overlayTop: services.overlayTop,
          onClose: () => Navigator.of(context).pop(),
        ),
      );
    } finally {
      _open = false;
      notifyListeners();
    }
  }

  /// Close the panel when it is showing.
  void close() {
    final nav = services.navigatorKey.currentState;
    if (_open && nav != null && nav.canPop()) nav.pop();
  }

  /// The `settings.open` command: open, or close an open panel.
  void toggle() => _open ? close() : unawaited(open());
}

/// Register the shell: `sidebar.settings` (the foot row), the `settings.header`,
/// `settings.close`, `settings.trigger` and `settings.action` seats, and the
/// `settings.open` command. Returns the shell and a disposer.
({SettingsShell shell, void Function() dispose}) registerSettingsShell(
  SlotRegistry slots, {
  required SettingsShellServices services,
}) {
  final shell = SettingsShell(slots, services);
  String t(String key) => services.i18n.t('settings', key);
  final offs = <void Function()>[
    slots.register<SettingsHeaderOwner, Widget>(
      DshShellSlots.settingsHeader.typed<SettingsHeaderOwner, Widget>(),
      (_) => DshChromeText(t('title')),
    ),
    slots.register<SettingsHeaderOwner, Widget>(
      DshShellSlots.settingsClose.typed<SettingsHeaderOwner, Widget>(),
      (_) => DshChromeText(t('close')),
    ),
    slots.register<SettingsTriggerOwner, Widget>(
      DshShellSlots.settingsTrigger.typed<SettingsTriggerOwner, Widget>(),
      (owner) => _TriggerContent(wide: owner.wide, label: t('trigger')),
    ),
    slots.register<SidebarFootOwner, Widget>(
      DshShellSlots.sidebarSettings.typed<SidebarFootOwner, Widget>(),
      (owner) => SettingsLauncherRow(shell: shell, wide: owner.wide),
    ),
    if (services.hostIsLocal && services.documentOpener != null)
      slots.register<SettingsHeaderOwner, Widget>(
        DshShellSlots.settingsAction.typed<SettingsHeaderOwner, Widget>(),
        (_) => SettingsDocumentAction(
          opener: services.documentOpener!,
          label: t('openDocument'),
          failure: t('openDocument.error'),
        ),
        id: 'settings-document',
      ),
  ];
  final offCommand = services.shortcuts?.register(
    ShortcutCommand(
      id: 'settings.open',
      label: () => t('shortcut.open'),
      aliases: const ['settings', 'preferences'],
      defaults: {
        for (final p in ['desktop:macos', 'desktop:windows', 'desktop:linux'])
          p: const ShortcutBinding('Comma', [ShortcutModifier.primary]),
        for (final p in ['web:macos', 'web:windows'])
          p: const ShortcutBinding('Comma', [
            ShortcutModifier.primary,
            ShortcutModifier.alt,
          ]),
      },
      regions: ShortcutRegion.values,
      modals: const ['settings'],
      resolve: (context) {
        if (context.modal != null && context.modal != 'settings') {
          return const ShortcutBlocked('modal');
        }
        return ShortcutHandled(shell.toggle);
      },
    ),
  );
  return (
    shell: shell,
    dispose: () {
      offCommand?.call();
      for (final off in offs.reversed) {
        off();
      }
      shell.dispose();
    },
  );
}

class _TriggerContent extends StatelessWidget {
  const _TriggerContent({required this.wide, required this.label});

  final bool wide;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DshIcon(
          DshIcons.settingsMedium,
          size: wide ? 16 : 18,
          color: theme.labelPrimary,
        ),
        if (wide) ...[
          const SizedBox(width: 8),
          DshChromeText(
            label,
            style: theme
                .textStyle('--dsw-font-s-14')
                .copyWith(color: theme.labelPrimary),
          ),
        ],
      ],
    );
  }
}

/// The sidebar-foot row: the `settings.launcher` occupant when one exists
/// (dsh's account menu), else the "More" launcher whose menu opens Settings,
/// else the plain `settings.trigger` button.
class SettingsLauncherRow extends StatefulWidget {
  const SettingsLauncherRow({
    super.key,
    required this.shell,
    required this.wide,
  });

  final SettingsShell shell;
  final bool wide;

  @override
  State<SettingsLauncherRow> createState() => _SettingsLauncherRowState();
}

class _SettingsLauncherRowState extends State<SettingsLauncherRow> {
  final OverlayPortalController _menu = OverlayPortalController();
  final LayerLink _link = LayerLink();
  bool _hover = false;
  void Function()? _keys;

  @override
  void initState() {
    super.initState();
    _keys = widget.shell.services.shortcuts?.subscribe(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _keys?.call();
    super.dispose();
  }

  String _t(String key) => widget.shell.services.i18n.t('settings', key);

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final shell = widget.shell;
    final wide = widget.wide;
    final launcher = shell.slots.renderSingle(
      DshShellSlots.settingsLauncher.typed<SettingsTriggerOwner, Widget>(),
      SettingsTriggerOwner(
        wide: wide,
        settingsOpen: shell.isOpen,
        openSettings: () => unawaited(shell.open()),
      ),
    );
    if (launcher != null) return launcher;
    final more = shell.services.i18n.t('common', 'more');
    final entry = shell.services.shortcuts?.registry.entry('settings.open');
    final keys = entry == null || entry.keys.isEmpty ? null : entry.keys;
    final box = wide ? null : 36.0;
    return OverlayPortal(
      controller: _menu,
      overlayChildBuilder: (context) => _MoreMenu(
        link: _link,
        settingsLabel: _t('trigger'),
        keys: keys,
        onSettings: () {
          _menu.hide();
          unawaited(shell.open());
        },
        onDismiss: _menu.hide,
        header: shell.services.moreMenuHeader(context),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: Padding(
          padding: EdgeInsets.fromLTRB(wide ? 0 : 0, 4, 0, wide ? 4 : 10),
          child: DshTooltip(
            label: more,
            disabled: wide || _menu.isShowing,
            delay: const Duration(milliseconds: 500),
            child: MouseRegion(
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              cursor: SystemMouseCursors.click,
              child: Semantics(
                button: true,
                label: more,
                child: GestureDetector(
                  key: const ValueKey('settings-trigger'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _menu.isShowing ? _menu.hide() : _menu.show(),
                  child: DshContainer(
                    height: wide ? 42 : box,
                    width: box,
                    padding: wide
                        ? const EdgeInsets.fromLTRB(8, 0, 10, 0)
                        : null,
                    alignment: wide ? null : Alignment.center,
                    decoration: BoxDecoration(
                      color: _hover || _menu.isShowing
                          ? theme.interactiveBgHover
                          : null,
                      borderRadius: BorderRadius.circular(theme.radiusMd),
                    ),
                    child: Row(
                      mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
                      mainAxisAlignment: wide
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: [
                        DshIcon(
                          DshShellIcons.ellipsisMedium,
                          size: 14,
                          color: theme.labelPrimary,
                        ),
                        if (wide) ...[
                          const SizedBox(width: 8),
                          DshChromeText(
                            more,
                            style: theme
                                .textStyle('--dsw-font-s-14')
                                .copyWith(color: theme.labelPrimary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.link,
    required this.settingsLabel,
    required this.keys,
    required this.onSettings,
    required this.onDismiss,
    this.header,
  });

  final Widget? header;

  final LayerLink link;
  final String settingsLabel;
  final List<String>? keys;
  final VoidCallback onSettings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(2, -4),
          child: Align(
            alignment: Alignment.topLeft,
            child: DshContainer(
              key: const ValueKey('settings-more-menu'),
              constraints: const BoxConstraints(minWidth: 124),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.color('--dsw-alias-bg-layer-2'),
                borderRadius: BorderRadius.circular(theme.radiusMd + 4),
                border: Border.all(
                  color: theme.color('--dsw-alias-border-l2'),
                  width: dshHairlineOf(context),
                ),
                boxShadow: theme.boxShadow('--dsw-elevation-prominent'),
              ),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (header != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                        child: header,
                      ),
                      DshContainer(
                        height: dshHairlineOf(context),
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.color('--dsw-alias-border-l2'),
                        ),
                      ),
                    ],
                    _MenuRow(
                      key: const ValueKey('settings-more-settings'),
                      icon: DshIcons.settingsMedium,
                      label: settingsLabel,
                      keys: keys,
                      onTap: onSettings,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.keys,
    required this.onTap,
  });

  final DshIconData icon;
  final String label;
  final List<String>? keys;
  final VoidCallback onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: DshContainer(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _hover ? theme.interactiveBgHover : null,
              borderRadius: BorderRadius.circular(theme.radiusMd),
            ),
            child: Row(
              children: [
                DshIcon(widget.icon, size: 14, color: theme.labelPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: DshChromeText(
                    widget.label,
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .copyWith(color: theme.labelPrimary),
                  ),
                ),
                if (widget.keys != null) ...[
                  const SizedBox(width: 12),
                  DshShortcutKeys(keys: widget.keys!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The header action that opens the settings document in the host's editor
/// (dsh `SettingsDocumentAction`): drawn only once the host confirms there is
/// one, and only for a host on this machine.
class SettingsDocumentAction extends StatefulWidget {
  const SettingsDocumentAction({
    super.key,
    required this.opener,
    required this.label,
    required this.failure,
  });

  final SettingsDocumentOpener opener;
  final String label;
  final String failure;

  @override
  State<SettingsDocumentAction> createState() => _SettingsDocumentActionState();
}

class _SettingsDocumentActionState extends State<SettingsDocumentAction> {
  bool _ready = false;
  bool _opening = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.opener.available().then((v) {
        if (mounted) setState(() => _ready = v);
      }),
    );
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failed = false;
    });
    final error = await widget.opener.open();
    if (mounted) {
      setState(() {
        _opening = false;
        _failed = error != null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    final theme = context.dsh;
    final hairline = dshHairlineOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_failed) ...[
          DshChromeText(
            widget.failure,
            style: theme
                .textStyle('--dsw-font-xxs-12')
                .copyWith(
                  color: theme.color('--dsw-alias-state-error-primary'),
                ),
          ),
          const SizedBox(width: 8),
        ],
        Opacity(
          opacity: _opening ? 0.4 : 1,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Semantics(
              button: true,
              label: widget.label,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('settings-open-document'),
                behavior: HitTestBehavior.opaque,
                onTap: _open,
                child: DshContainer(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(theme.radiusSm),
                    border: Border.all(
                      color: theme.color('--dsw-alias-border-l3'),
                      width: hairline,
                    ),
                  ),
                  child: DshChromeText(
                    widget.label,
                    style: theme
                        .textStyle('--dsw-font-xxs-12')
                        .copyWith(color: theme.labelPrimary),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
