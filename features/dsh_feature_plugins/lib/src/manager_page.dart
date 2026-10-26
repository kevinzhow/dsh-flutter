import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_client/generated_plugin_manager.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'common.dart';
import 'market_page.dart';
import 'install_dialog.dart';

const _builtinProfiles = {
  '@deepseek-ai/dsh-base',
  '@deepseek-ai/dsh-web-app',
  '@deepseek-ai/dsh-headless',
  '@deepseek-ai/dsh-sdk-app',
  '@deepseek-ai/dsh-acp-app',
  '@deepseek-ai/dsh-sdk-minimal',
};
const _extensions = [
  '@deepseek-ai/dsh-experimental-agent-team-profile',
  '@deepseek-ai/dsh-experimental-voice-input-bundle',
  '@deepseek-ai/dsh-experimental-auto-review',
  '@deepseek-ai/dsh-experimental-inspector-profile',
];
const _more = [
  '@deepseek-ai/dsh-experimental-tool-worktree',
  '@deepseek-ai/dsh-experimental-cot-translation-bundle',
  '@deepseek-ai/dsh-experimental-terminal-bundle',
  '@deepseek-ai/dsh-experimental-session-search',
  '@deepseek-ai/dsh-experimental-session-titles-bundle',
  '@deepseek-ai/dsh-experimental-badge-skill-bundle',
  '@deepseek-ai/dsh-experimental-ralph-bundle',
  '@deepseek-ai/dsh-experimental-plugin-market-bundle',
  '@deepseek-ai/dsh-subagent-codex',
  '@deepseek-ai/dsh-subagent-claude-code',
];
int _rank(String name) => _extensions.contains(name)
    ? _extensions.indexOf(name)
    : _more.contains(name)
    ? _extensions.length + 1 + _more.indexOf(name)
    : _extensions.length;

class PluginManagerPage extends StatefulWidget {
  const PluginManagerPage({
    super.key,
    required this.model,
    required this.market,
    required this.slots,
    required this.i18n,
  });
  final PluginManagerModel model;
  final PluginMarketModel market;
  final SlotRegistry slots;
  final DshI18n i18n;
  @override
  State<PluginManagerPage> createState() => _PluginManagerPageState();
}

class _PluginManagerPageState extends State<PluginManagerPage> {
  StreamSubscription<int>? _sub;
  StreamSubscription<String>? _slots;
  String? selected, config;
  bool discover = false, more = false, _installShowing = false;
  PluginManagerModel get model => widget.model;
  String t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('pluginManager', key, params: params);
  @override
  void initState() {
    super.initState();
    _sub = model.changed.changes.listen((_) {
      if (!mounted) return;
      setState(() {});
      if (model.installer.open && !_installShowing) {
        scheduleMicrotask(() {
          if (mounted && model.installer.open && !_installShowing) {
            unawaited(_install(newDialog: false));
          }
        });
      }
    });
    _slots = widget.slots.changes.listen((name) {
      if (name == DshSlots.pluginsItem.name && mounted) setState(() {});
    });
    scheduleMicrotask(model.ensure);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_slots?.cancel());
    super.dispose();
  }

  Future<void> _install({bool newDialog = true}) async {
    if (_installShowing || !mounted) return;
    _installShowing = true;
    try {
      if (newDialog) model.installer.show();
      await showPluginInstall(context, model, widget.i18n);
    } finally {
      _installShowing = false;
    }
  }

  Future<void> _toggle(BundleInfo bundle, bool enabled) async {
    final installing =
        enabled &&
        bundle.availability == BundleInfoAvailability.missing &&
        bundle.installTarget != null;
    final pending = model.setEnabled(bundle.name, enabled);
    if (installing && mounted) unawaited(_install(newDialog: false));
    await pending;
  }

  Future<void> _remove(String name) async {
    model.requestRemoval(name);
    final confirmation = model.confirmation!;
    final yes = await showDshDialog<bool>(
      context,
      label: t('confirmUninstallTitle', {'name': name}),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('confirmUninstallTitle', {'name': name})),
            const SizedBox(height: 12),
            pluginStatus(context, t('confirmUninstallDescription')),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                DshButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t('cancel')),
                ),
                DshButton(
                  variant: DshButtonVariant.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t('confirmUninstall')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (yes == true) {
      await model.confirm(confirmation);
    } else {
      model.cancelConfirmation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final package = model.packages
        .where((p) => p.bundle.name == selected)
        .firstOrNull;
    final pluginSlot = DshSlots.pluginsItem.typed<SettingsOwner, Widget>();
    final configuration = config == null
        ? null
        : widget.slots.renderOnly(pluginSlot, config!, const SettingsOwner());
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const ValueKey('plugin-manager-page'),
        padding: EdgeInsets.fromLTRB(
          (constraints.maxWidth * .04).clamp(24, 48),
          28,
          (constraints.maxWidth * .04).clamp(24, 48),
          48,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        pluginHeading(context, t('title')),
                        pluginStatus(context, t('intro')),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        DshButton(
                          size: DshButtonSize.sm,
                          onPressed: model.refreshing
                              ? null
                              : () => unawaited(model.refresh()),
                          child: Text(t('refresh')),
                        ),
                        DshButton(
                          size: DshButtonSize.sm,
                          variant: DshButtonVariant.primary,
                          onPressed:
                              model.status == PluginManagerStatus.unavailable
                              ? null
                              : () => unawaited(_install()),
                          child: Text(t('addPlugin')),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (selected != null || config != null || more) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DshButton(
                      onPressed: () => setState(() {
                        selected = null;
                        config = null;
                        more = false;
                      }),
                      child: Text(t('backToList')),
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      DshButton(
                        variant: discover
                            ? DshButtonVariant.ghost
                            : DshButtonVariant.toolbar,
                        onPressed: () => setState(() => discover = false),
                        child: Text(t('installedTab')),
                      ),
                      DshButton(
                        variant: discover
                            ? DshButtonVariant.toolbar
                            : DshButtonVariant.ghost,
                        onPressed: () => setState(() => discover = true),
                        child: Text(widget.i18n.t('pluginMarket', 'title')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                if (model.notice case final notice?) ...[
                  _notice(context, notice),
                  const SizedBox(height: 12),
                ],
                if (!model.installer.open && model.installer.requestId != null)
                  DshButton(
                    onPressed: () => unawaited(_install(newDialog: false)),
                    child: Text(t('installViewTask')),
                  ),
                if (configuration != null)
                  configuration
                else if (package != null)
                  _detail(context, package)
                else if (discover && !more && selected == null)
                  PluginMarketPage(
                    model: widget.market,
                    manager: model,
                    i18n: widget.i18n,
                    onInstall: () => unawaited(_install(newDialog: false)),
                  )
                else if (model.status == PluginManagerStatus.loading ||
                    model.status == PluginManagerStatus.idle)
                  pluginStatus(context, t('loading'))
                else if (model.status == PluginManagerStatus.unavailable)
                  pluginStatus(context, t('unavailable'))
                else if (model.status == PluginManagerStatus.error)
                  Column(
                    children: [
                      pluginStatus(context, t('error')),
                      DshButton(
                        onPressed: () => unawaited(model.load()),
                        child: Text(t('retry')),
                      ),
                    ],
                  )
                else
                  _list(context, more, widget.slots.entries(pluginSlot)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(BuildContext context, PluginManagerNotice notice) {
    final text = switch (notice.kind) {
      'refresh-failed' => t('refreshError'),
      'restart-required' => t('restartNotice', {
        'reason': notice.restartReason == null
            ? ''
            : t(switch (notice.restartReason!.value) {
                'no-hmr' => 'restartReasonNoHmr',
                'package-moved' => 'restartReasonPackageMoved',
                'host-module' => 'restartReasonHostModule',
                'unmanaged-plugin' => 'restartReasonUnmanagedPlugin',
                _ => 'restartReasonModuleComparison',
              }),
      }),
      'overridden' => t('overriddenNotice', {'name': notice.target}),
      'cancelled' => t('installCancelled'),
      'install:done' => t('installBackgroundDone'),
      'install:failed' => t('installBackgroundFailed'),
      'install:applying' => t('installBackgroundApplying'),
      'install:unknown' => t('installBackgroundUnknown'),
      'install:unconfirmed' => t('installBackgroundUnconfirmed'),
      _ =>
        notice.error == null
            ? notice.reason ?? t('reasonOperationError')
            : managementErrorText(
                notice.error!.code.value,
                notice.error!.diagnostic,
                widget.i18n,
              ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: pluginStatus(context, text)),
        DshButton(
          size: DshButtonSize.sm,
          onPressed: model.dismissNotice,
          child: Text(t('close')),
        ),
      ],
    );
  }

  Widget _list(
    BuildContext context,
    bool all,
    List<SlotEntryInfo> configurations,
  ) {
    final official =
        model.packages
            .where(
              (p) =>
                  p.bundle.official &&
                  !_builtinProfiles.contains(p.bundle.name) &&
                  (all || !_more.contains(p.bundle.name) || p.bundle.enabled),
            )
            .toList()
          ..sort(
            (a, b) => _rank(a.bundle.name).compareTo(_rank(b.bundle.name)),
          );
    final installed = model.packages
        .where(
          (p) =>
              !p.bundle.official && !_builtinProfiles.contains(p.bundle.name),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!all && configurations.isNotEmpty) ...[
          pluginHeading(context, t('basicTitle')),
          const SizedBox(height: 8),
          _grid([
            for (final entry in configurations)
              pluginCard(
                context,
                child: DshButton(
                  onPressed: () => setState(() => config = entry.id),
                  child: Text(entry.label ?? pluginShortName(entry.id)),
                ),
              ),
          ]),
          const SizedBox(height: 32),
        ],
        if (official.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: pluginHeading(context, t('extensionsTitle'))),
              if (!all)
                DshButton(
                  onPressed: () => setState(() => more = true),
                  child: Text(t('moreAction')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _grid([for (final p in official) _card(context, p)]),
          const SizedBox(height: 32),
        ],
        if (!all) ...[
          pluginHeading(context, t('bundlesTitle')),
          const SizedBox(height: 8),
          if (installed.isEmpty)
            pluginStatus(context, t('empty'))
          else
            _grid([for (final p in installed) _card(context, p)]),
        ],
      ],
    );
  }

  Widget _grid(List<Widget> cards) => LayoutBuilder(
    builder: (context, c) {
      final columns = c.maxWidth >= 640 ? 2 : 1;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final card in cards)
            SizedBox(
              width: (c.maxWidth - (columns - 1) * 12) / columns,
              child: card,
            ),
        ],
      );
    },
  );
  String _title(BundleInfo bundle) =>
      pluginText(bundle.meta?.title, widget.i18n, bundle.name);
  Widget _card(BuildContext context, ManagedPluginPackage package) {
    final b = package.bundle, title = _title(package.bundle);
    return pluginCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DshButton(
                    onPressed: () => setState(() => selected = b.name),
                    semanticLabel: t('openDetail', {'name': title}),
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              DshSwitch(
                value: b.enabled,
                label: t('enableToggle', {'name': title}),
                onChanged:
                    model.busy.contains(b.name) || b.readOnlyReason != null
                    ? null
                    : (value) => unawaited(_toggle(b, value)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          pluginStatus(
            context,
            pluginText(b.meta?.description, widget.i18n, b.description ?? ''),
          ),
          if (b.version != null)
            pluginStatus(context, t('versionTag', {'version': b.version})),
          if (b.error != null)
            pluginStatus(
              context,
              managementErrorText(
                b.error!.code.value,
                b.error!.diagnostic,
                widget.i18n,
              ),
            ),
        ],
      ),
    );
  }

  Widget _detail(BuildContext context, ManagedPluginPackage package) {
    final b = package.bundle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pluginHeading(context, _title(b)),
        const SizedBox(height: 12),
        pluginStatus(
          context,
          pluginText(b.meta?.description, widget.i18n, b.description ?? ''),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          children: [
            DshSwitch(
              value: b.enabled,
              label: t('enableToggle', {'name': _title(b)}),
              onChanged: b.readOnlyReason != null || model.busy.contains(b.name)
                  ? null
                  : (value) => unawaited(_toggle(b, value)),
            ),
            if (b.installTarget != null &&
                b.availability != BundleInfoAvailability.installation)
              DshButton(
                size: DshButtonSize.sm,
                onPressed: model.busy.contains(b.name)
                    ? null
                    : () async {
                        final pending = model.update(b.name);
                        await Future<void>.delayed(Duration.zero);
                        if (mounted && model.installer.open) {
                          unawaited(_install(newDialog: false));
                        }
                        await pending;
                      },
                child: Text(t('update')),
              ),
            if (b.removable)
              DshButton(
                size: DshButtonSize.sm,
                onPressed: model.busy.contains(b.name)
                    ? null
                    : () => unawaited(_remove(b.name)),
                child: Text(t('uninstall')),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (b.error != null)
          pluginStatus(
            context,
            managementErrorText(
              b.error!.code.value,
              b.error!.diagnostic,
              widget.i18n,
            ),
          ),
        pluginHeading(context, t('partsLabel')),
        const SizedBox(height: 8),
        if (package.rows.isEmpty) pluginStatus(context, t('partsEmpty')),
        for (final row in package.rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: pluginCard(
              context,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pluginText(
                            row.declaration.meta?.title,
                            widget.i18n,
                            row.declaration.moduleName,
                          ),
                        ),
                        pluginStatus(context, row.declaration.rowId),
                        pluginStatus(context, row.declaration.moduleName),
                        pluginStatus(
                          context,
                          t(switch (row.phase?.value) {
                            'pending' => 'rowPhasePending',
                            'loading' => 'rowPhaseLoading',
                            'active' => 'rowPhaseActive',
                            'failed' => 'rowPhaseFailed',
                            'unloading' => 'rowPhaseUnloading',
                            _ => 'rowStateIdle',
                          }),
                        ),
                      ],
                    ),
                  ),
                  DshSwitch(
                    value: row.enabled,
                    label: t('partToggle', {'name': row.declaration.rowId}),
                    onChanged:
                        row.declaration.entryId == null ||
                            row.readOnlyReason != null ||
                            model.busy.contains(
                              'row:${row.declaration.entryId}',
                            )
                        ? null
                        : (v) => unawaited(
                            model.setRowEnabled(row.declaration.entryId!, v),
                          ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        pluginHeading(context, t('sourceTitle')),
        const SizedBox(height: 8),
        pluginStatus(context, b.name),
        if (b.source != null) pluginStatus(context, b.source!),
        if (b.version != null)
          pluginStatus(context, '${t('sourceVersion')}: ${b.version}'),
        if (b.installTarget != null)
          pluginStatus(
            context,
            '${t('sourceTargetSpec')}: ${b.installTarget!.spec}',
          ),
      ],
    );
  }
}
