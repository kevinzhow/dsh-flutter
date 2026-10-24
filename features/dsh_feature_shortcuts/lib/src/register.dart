import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'reference_dialog.dart';

/// What the shortcut reference needs from the composition root.
abstract interface class ShortcutsServices {
  /// The app navigator: the reference is a modal route pushed onto it.
  GlobalKey<NavigatorState> get navigatorKey;

  DshI18n get i18n;

  ShortcutService get shortcuts;
}

/// The shortcut reference of one window (dsh `ui-shortcuts` `index.ts`).
class ShortcutsFeature {
  ShortcutsFeature._(this._services);

  final ShortcutsServices _services;
  bool _open = false;

  /// Whether the reference is showing.
  bool get isOpen => _open;

  /// Open the reference (optionally on the editor of [command]); a no-op while
  /// it is open.
  Future<void> open({String? command}) async {
    final context = _services.navigatorKey.currentContext;
    if (context == null || _open) return;
    _open = true;
    final release = _services.shortcuts.modals.push('shortcuts');
    final theme = context.dsh;
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: _services.i18n.t('shortcuts', 'close'),
        barrierColor: theme.color('--dsw-alias-bg-mask-1'),
        transitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => ShortcutReference(
          service: _services.shortcuts,
          i18n: () => _services.i18n,
          initialEditing: command,
          onClose: () => Navigator.of(context).pop(),
        ),
      );
    } finally {
      release();
      _open = false;
    }
  }

  /// Close the reference when it is showing.
  void close() {
    final nav = _services.navigatorKey.currentState;
    if (_open && nav != null && nav.canPop()) nav.pop();
  }

  /// The `shortcuts.open` command: open, or close an open reference.
  void toggle() => _open ? close() : unawaited(open());
}

/// Register the reference: the `shortcuts.open` command (Mod+/), the read-only
/// menu navigation rows, and the General settings row that opens it. Returns
/// the feature and a disposer.
({ShortcutsFeature feature, void Function() dispose}) registerShortcutsFeature(
  SlotRegistry slots, {
  required ShortcutsServices services,
}) {
  final feature = ShortcutsFeature._(services);
  final shortcuts = services.shortcuts;
  String t(String key) => services.i18n.t('shortcuts', key);
  final offs = <void Function()>[
    for (final row in _fixedRows)
      shortcuts.registerFixed(
        ShortcutFixedCommand(
          id: 'fixed.${row.id}',
          label: () => t(row.id),
          keys: row.keys,
          bindings: row.bindings,
          group: ShortcutGroup.menus,
        ),
      ),
    shortcuts.register(
      ShortcutCommand(
        id: 'shortcuts.open',
        label: () => t('open'),
        aliases: const ['shortcuts', 'keyboard shortcuts'],
        defaults: {
          for (final p in allProfiles)
            p: const ShortcutBinding('Slash', [ShortcutModifier.primary]),
        },
        regions: ShortcutRegion.values,
        modals: const ['settings', 'shortcuts'],
        resolve: (context) {
          if (context.modal != null &&
              context.modal != 'settings' &&
              context.modal != 'shortcuts') {
            return const ShortcutBlocked('modal');
          }
          return ShortcutHandled(feature.toggle);
        },
      ),
    ),
    slots.register<SettingsOwner, Widget>(
      DshSlots.settingsGeneralItem.typed<SettingsOwner, Widget>(),
      (_) => _ShortcutsRow(feature: feature, services: services),
      id: 'shortcuts',
      order: 16,
    ),
  ];
  return (
    feature: feature,
    dispose: () {
      for (final off in offs.reversed) {
        off();
      }
    },
  );
}

const _fixedRows = [
  (
    id: 'move',
    keys: ['↑', '↓'],
    bindings: [ShortcutBinding('ArrowUp'), ShortcutBinding('ArrowDown')],
  ),
  (id: 'select', keys: ['Enter'], bindings: [ShortcutBinding('Enter')]),
  (id: 'dismiss', keys: ['Esc'], bindings: [ShortcutBinding('Escape')]),
];

class _ShortcutsRow extends StatefulWidget {
  const _ShortcutsRow({required this.feature, required this.services});

  final ShortcutsFeature feature;
  final ShortcutsServices services;

  @override
  State<_ShortcutsRow> createState() => _ShortcutsRowState();
}

class _ShortcutsRowState extends State<_ShortcutsRow> {
  void Function()? _off;

  @override
  void initState() {
    super.initState();
    _off = widget.services.shortcuts.subscribe(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _off?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final i18n = widget.services.i18n;
    final entry = widget.services.shortcuts.registry.entry('shortcuts.open');
    final hairline = dshHairlineOf(context);
    return DshDecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.color('--dsw-alias-border-l2'),
            width: hairline,
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DshChromeText(
                        i18n.t('shortcuts', 'settings'),
                        style: theme
                            .textStyle('--dsw-font-s-14')
                            .copyWith(color: theme.labelPrimary),
                      ),
                      const SizedBox(height: 4),
                      DshChromeText(
                        i18n.t('shortcuts', 'description'),
                        style: theme
                            .textStyle('--dsw-font-xxs-12')
                            .copyWith(
                              color: theme.color('--dsw-alias-label-tertiary'),
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              DshTooltip(
                label: i18n.t('shortcuts', 'global-hint'),
                shortcutKeys: entry?.keys,
                disabled: entry == null || entry.keys.isEmpty,
                side: DshTooltipSide.top,
                child: DshButton(
                  key: const ValueKey('shortcuts-open-row'),
                  variant: DshButtonVariant.toolbar,
                  semanticLabel: i18n.t('shortcuts', 'view'),
                  onPressed: () => unawaited(widget.feature.open()),
                  child: DshChromeText(i18n.t('shortcuts', 'view')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
