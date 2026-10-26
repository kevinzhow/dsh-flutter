import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'inventory.dart';

void Function() registerPluginSettings(
  SlotRegistry slots, {
  required HostRemotes remotes,
  required DshI18n Function() i18n,
}) {
  final offs = [
    slots.register<SettingsOwner, Widget>(
      DshSlots.settingsSection.typed<SettingsOwner, Widget>(),
      (_) => _PluginSettingsTabs(slots: slots, i18n: i18n()),
      id: 'plugins',
      order: 15,
      label: () => i18n().t('settings.plugins', 'nav'),
    ),
    slots.register<SettingsOwner, Widget>(
      DshSlots.settingsPluginsTab.typed<SettingsOwner, Widget>(),
      (_) => PluginInventorySection(remotes: remotes, i18n: i18n()),
      id: 'all',
      order: 10,
      label: () => i18n().t('settings.pluginInventory', 'tab'),
    ),
  ];
  return () {
    for (final off in offs.reversed) {
      off();
    }
  };
}

class _PluginSettingsTabs extends StatefulWidget {
  const _PluginSettingsTabs({required this.slots, required this.i18n});
  final SlotRegistry slots;
  final DshI18n i18n;
  @override
  State<_PluginSettingsTabs> createState() => _PluginSettingsTabsState();
}

class _PluginSettingsTabsState extends State<_PluginSettingsTabs> {
  String? selected;
  StreamSubscription<String>? sub;
  @override
  void initState() {
    super.initState();
    sub = widget.slots.changes.listen((name) {
      if (name == DshSlots.settingsPluginsTab.name && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = DshSlots.settingsPluginsTab.typed<SettingsOwner, Widget>();
    final entries = widget.slots.entries(slot);
    final active = entries.any((entry) => entry.id == selected)
        ? selected
        : entries.firstOrNull?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Wrap(
            spacing: 4,
            children: [
              for (final entry in entries)
                DshButton(
                  size: DshButtonSize.sm,
                  variant: entry.id == active
                      ? DshButtonVariant.toolbar
                      : DshButtonVariant.ghost,
                  onPressed: () => setState(() => selected = entry.id),
                  child: Text(entry.label ?? entry.id),
                ),
            ],
          ),
        ),
        if (active != null)
          Expanded(
            child:
                widget.slots.renderOnly(slot, active, const SettingsOwner()) ??
                const SizedBox(),
          ),
      ],
    );
  }
}
