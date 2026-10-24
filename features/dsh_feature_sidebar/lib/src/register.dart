import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'leading_controls.dart';
import 'sidebar_root.dart';
import 'sidebar_services.dart';

/// Occupy `sidebar` with the shell and `shell.leading` with the window-chrome
/// controls, and register the New Session command (dsh `ui-sidebar` `apply`).
/// Returns a disposer.
void Function() registerSidebarFeature(
  SlotRegistry slots, {
  required SidebarServices services,
}) {
  final disposers = <void Function()>[
    slots.register<SidebarOwner, Widget>(
      DshShellSlots.sidebar.typed<SidebarOwner, Widget>(),
      (owner) => SidebarRoot(owner: owner, slots: slots, services: services),
    ),
    slots.register<Object?, Widget>(
      DshShellSlots.shellLeading.typed<Object?, Widget>(),
      (_) => _LeadingHost(services: services),
    ),
  ];
  final off = services.shortcuts?.register(
    ShortcutCommand(
      id: sessionNewCommand,
      label: () => services.i18n.t('workspace', 'session.new'),
      aliases: const ['new session', 'new chat'],
      defaults: {
        for (final p in ['desktop:macos', 'desktop:windows', 'desktop:linux'])
          p: const ShortcutBinding('KeyN', [ShortcutModifier.primary]),
        for (final p in ['web:macos', 'web:windows'])
          p: const ShortcutBinding('KeyN', [
            ShortcutModifier.primary,
            ShortcutModifier.alt,
          ]),
      },
      regions: const [ShortcutRegion.page, ShortcutRegion.editable],
      resolve: (_) => ShortcutHandled(services.startSession),
    ),
  );
  return () {
    off?.call();
    for (final d in disposers.reversed) {
      d();
    }
  };
}

class _LeadingHost extends StatelessWidget {
  const _LeadingHost({required this.services});

  final SidebarServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _StoreListenable(services),
      builder: (context, _) {
        final info = services.layout.store.layoutInfo;
        final collapsed = info.viewportWidth < 1024
            ? !info.narrowExpanded
            : info.sidebar == 0;
        return SidebarLeadingControls(services: services, collapsed: collapsed);
      },
    );
  }
}

class _StoreListenable extends ChangeNotifier {
  _StoreListenable(SidebarServices services) {
    _off = services.layout.store.subscribe(notifyListeners);
  }

  late final void Function() _off;

  @override
  void dispose() {
    _off();
    super.dispose();
  }
}
