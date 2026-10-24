import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';

/// `ctx.layout` and its store, the shortcut of the sidebar toggle, and the
/// retain-the-selected-panel rule (dsh `ui-layout` `index.ts`): one per window.
class LayoutFeature {
  LayoutFeature._(this.store, this.controller, this._dispose);

  final LayoutStore store;
  final LayoutController controller;
  final void Function() _dispose;

  /// Release the shortcut and pending navigations.
  void dispose() => _dispose();
}

/// Create the layout of one window. [slots] answers which `main` keys are
/// registered (selecting an absent panel throws, and a panel that vanishes
/// returns to the Conversation), [shortcuts] receives the sidebar toggle,
/// [i18n] names it. [viewportWidth] bootstraps the first render.
LayoutFeature registerLayoutFeature(
  SlotRegistry slots, {
  required ShortcutService? shortcuts,
  required DshI18n Function() i18n,
  required double viewportWidth,
}) {
  final store = LayoutStore(viewportWidth: viewportWidth);
  final mainSlot = DshShellSlots.main.typed<Object?, Object?>();
  Iterable<String> mainKeys() => slots.keys(mainSlot);
  final controller = LayoutController(store, (id) => mainKeys().contains(id));
  final sub = slots.changes.listen((name) {
    if (name == mainSlot.name) store.retainMainPanels(mainKeys());
  });
  final disposeShortcut = shortcuts?.register(
    ShortcutCommand(
      id: 'sidebar.left.toggle',
      label: () => i18n().t('shortcuts.layout', 'toggle'),
      aliases: const ['sidebar', 'toggle left sidebar'],
      defaults: {
        for (final p in ['desktop:macos', 'desktop:windows', 'desktop:linux'])
          p: const ShortcutBinding('KeyB', [ShortcutModifier.primary]),
        for (final p in ['web:macos', 'web:windows'])
          p: const ShortcutBinding('KeyB', [
            ShortcutModifier.primary,
            ShortcutModifier.alt,
          ]),
      },
      regions: ShortcutRegion.values
          .where((r) => r != ShortcutRegion.terminal)
          .toList(),
      resolve: (_) => ShortcutHandled(controller.toggleSidebar),
    ),
  );
  return LayoutFeature._(store, controller, () {
    disposeShortcut?.call();
    sub.cancel();
    controller.dispose();
  });
}
