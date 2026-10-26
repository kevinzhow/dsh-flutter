import 'dart:async';

import 'package:dsh_client/generated_plugin_inventory.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'common.dart';

class PluginInventorySection extends StatefulWidget {
  const PluginInventorySection({
    super.key,
    required this.remotes,
    required this.i18n,
  });
  final HostRemotes remotes;
  final DshI18n i18n;
  @override
  State<PluginInventorySection> createState() => _PluginInventorySectionState();
}

class _PluginInventorySectionState extends State<PluginInventorySection> {
  PluginInventorySnapshot? snapshot;
  bool loading = true, failed = false;
  String search = '';
  String? preset;
  int generation = 0;
  StreamSubscription<Object?>? _events, _generations;
  String t(String key, [Map<String, Object?> p = const {}]) =>
      widget.i18n.t('settings.pluginInventory', key, params: p);
  @override
  void initState() {
    super.initState();
    _events = widget.remotes
        .emitted('plugin-manager/changed')
        .listen((_) => unawaited(_load()));
    _generations = widget.remotes.generations.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  Future<void> _load() async {
    final ticket = ++generation;
    try {
      final value = await widget.remotes.pluginInventory.list();
      if (!mounted || ticket != generation) return;
      setState(() {
        snapshot = value;
        loading = false;
        failed = false;
        if (!(value.agentPresets ?? const <AgentPresetPluginGroup>[]).any(
          (p) => p.id == preset,
        )) {
          preset =
              (value.agentPresets ?? const <AgentPresetPluginGroup>[])
                  .where((p) => p.isDefault)
                  .firstOrNull
                  ?.id ??
              (value.agentPresets ?? const <AgentPresetPluginGroup>[])
                  .firstOrNull
                  ?.id;
        }
      });
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    unawaited(_events?.cancel());
    unawaited(_generations?.cancel());
    super.dispose();
  }

  bool matches(String module, String? entry, Object? title) =>
      '$module ${entry ?? ''} ${pluginText(title, widget.i18n)}'
          .toLowerCase()
          .contains(search.toLowerCase());
  @override
  Widget build(BuildContext context) {
    final value = snapshot;
    final selected = value?.agentPresets
        ?.where((p) => p.id == preset)
        .firstOrNull;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pluginHeading(context, widget.i18n.t('settings.plugins', 'title')),
          const SizedBox(height: 16),
          PluginInput(
            value: search,
            label: t('search'),
            onChanged: (text) => setState(() => search = text),
          ),
          const SizedBox(height: 16),
          if (loading) pluginStatus(context, t('loading')),
          if (failed) ...[
            pluginStatus(context, t('error')),
            DshButton(
              onPressed: () => unawaited(_load()),
              child: Text(t('retry')),
            ),
          ],
          if (value != null) ...[
            if (value.agentPresets?.isNotEmpty == true) ...[
              pluginHeading(context, t('presetTitle')),
              pluginStatus(context, t('presetSubtitle')),
              Wrap(
                spacing: 4,
                children: [
                  for (final group
                      in (value.agentPresets ??
                          const <AgentPresetPluginGroup>[]))
                    DshButton(
                      size: DshButtonSize.sm,
                      variant: group.id == preset
                          ? DshButtonVariant.toolbar
                          : DshButtonVariant.ghost,
                      onPressed: () => setState(() => preset = group.id),
                      child: Text(_presetName(group)),
                    ),
                ],
              ),
              if (selected?.broken != null)
                pluginStatus(context, selected!.broken!),
              if (selected != null)
                for (final row in selected.rows)
                  if (matches(row.moduleName, row.entryId, row.meta?.title))
                    _row(
                      context,
                      row.moduleName,
                      row.entryId,
                      row.meta?.title,
                      row.meta?.description,
                      row.enabled,
                      row.fiberPhase?.value,
                      condition: row.condition,
                    ),
              const SizedBox(height: 24),
            ],
            pluginHeading(context, t('globalTitle')),
            pluginStatus(context, t('globalSubtitle')),
            const SizedBox(height: 8),
            if (value.entries.isEmpty) pluginStatus(context, t('empty')),
            for (final row in value.entries)
              if (matches(row.moduleName, row.entryId, row.meta?.title))
                _row(
                  context,
                  row.moduleName,
                  row.entryId,
                  row.meta?.title,
                  row.meta?.description,
                  row.enabled,
                  row.fiberPhase?.value,
                ),
          ],
        ],
      ),
    );
  }

  String _presetName(AgentPresetPluginGroup group) {
    final base =
        group.name ??
        (const ['standard', 'ptc', 'minimal', 'cordis'].contains(group.id)
            ? widget.i18n.t(
                'settings.agentPreset',
                'preset${group.id[0].toUpperCase()}${group.id.substring(1)}Name',
              )
            : group.id);
    return group.broken != null
        ? t('presetOptionBroken', {'name': base})
        : group.isDefault
        ? t('presetOptionDefault', {'name': base})
        : base;
  }

  Widget _row(
    BuildContext context,
    String module,
    String? entry,
    Object? title,
    Object? description,
    Object? enabled,
    String? phase, {
    String? condition,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: pluginCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pluginText(title, widget.i18n, pluginShortName(module))),
          pluginStatus(context, pluginText(description, widget.i18n)),
          if (entry != null) pluginStatus(context, entry),
          pluginStatus(context, module),
          pluginStatus(
            context,
            t(
              enabled == 'conditional'
                  ? 'conditionalTag'
                  : enabled == true
                  ? 'enabledTag'
                  : 'disabledTag',
            ),
          ),
          pluginStatus(
            context,
            t(switch (phase) {
              'pending' => 'pending',
              'loading' => 'loadingPhase',
              'active' => 'active',
              'failed' => 'failed',
              'unloading' => 'unloading',
              _ => 'unobserved',
            }),
          ),
          if (condition != null)
            pluginStatus(context, '${t('condition')}: $condition'),
        ],
      ),
    ),
  );
}
