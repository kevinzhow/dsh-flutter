import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'presets.dart';

void Function() registerAgentPresetFeature(
  SlotRegistry slots, {
  required AgentPresetsModel model,
  required DshI18n Function() i18n,
  required VoidCallback startCreator,
}) {
  final offs = [
    slots.register<SettingsOwner, Widget>(
      DshSlots.settingsSection.typed<SettingsOwner, Widget>(),
      (_) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: AgentPresetSection(
          model: model,
          i18n: i18n(),
          startCreator: startCreator,
        ),
      ),
      id: 'agentPresets',
      order: 20,
      label: () => i18n().t('settings.agentPreset', 'nav'),
    ),
    slots.register<SessionOwner?, Widget>(
      DshSlots.conversationHeroAgentPreset.typed<SessionOwner?, Widget>(),
      (_) => AgentPresetChip(model: model, i18n: i18n()),
    ),
    slots.register<SessionOwner, Widget>(
      DshSlots.conversationSessionHeaderActions.typed<SessionOwner, Widget>(),
      (owner) => _PresetHeader(owner: owner, model: model, i18n: i18n()),
      id: 'agent-preset',
      order: -10,
    ),
  ];
  return () {
    for (final off in offs) {
      off();
    }
  };
}

class _PresetHeader extends StatefulWidget {
  const _PresetHeader({
    required this.owner,
    required this.model,
    required this.i18n,
  });
  final SessionOwner owner;
  final AgentPresetsModel model;
  final DshI18n i18n;
  @override
  State<_PresetHeader> createState() => _PresetHeaderState();
}

class _PresetHeaderState extends State<_PresetHeader> {
  StreamSubscription<int>? sub;
  @override
  void initState() {
    super.initState();
    sub = widget.model.changed.changes.listen((_) {
      if (mounted) setState(() {});
    });
    scheduleMicrotask(() {
      if (mounted) unawaited(widget.model.load());
    });
  }

  @override
  void dispose() {
    unawaited(sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: widget.owner.session.projections.changes,
    builder: (context, _) {
      final id = widget.owner.session.projections.get('agentPreset');
      if (id is! String || id.isEmpty) return const SizedBox.shrink();
      final row = widget.model.rows.where((r) => r.id == id).firstOrNull;
      return Semantics(
        label: widget.i18n.t('settings.agentPreset', 'headerHint'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DshIcon(DshIcons.agentPreset, size: 14),
            const SizedBox(width: 4),
            Text(
              row == null ? id : presetName(row, widget.i18n),
              style: context.dsh.textStyle('--dsw-font-xxs-12'),
            ),
          ],
        ),
      );
    },
  );
}
