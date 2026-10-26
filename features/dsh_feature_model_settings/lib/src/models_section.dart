import 'dart:async';

import 'package:dsh_client/generated_settings.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'provider_editor.dart';

class ModelsSection extends StatefulWidget {
  const ModelsSection({
    super.key,
    required this.store,
    required this.i18n,
    this.slots,
  });
  final ModelsSettingsStore store;
  final DshI18n i18n;
  final SlotRegistry? slots;
  @override
  State<ModelsSection> createState() => _ModelsSectionState();
}

class _ModelsSectionState extends State<ModelsSection> {
  StreamSubscription<ModelsSettingsSnapshot>? _sub;
  StreamSubscription<String>? _slotSub;
  String? _editing;
  bool _adding = false;
  bool _custom = false;
  String? _error;
  String? _removing;
  String t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('settings.models', key, params: params);
  @override
  void initState() {
    super.initState();
    _sub = widget.store.state.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _slotSub = widget.slots?.changes.listen((name) {
      if (mounted &&
          (name == DshSlots.modelsProviderCard.name ||
              name == DshSlots.modelsFooter.name)) {
        setState(() {});
      }
    });
    unawaited(widget.store.load());
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_slotSub?.cancel());
    super.dispose();
  }

  void _close(bool changed) {
    if (!mounted) return;
    setState(() {
      _editing = null;
      _adding = false;
      _custom = false;
    });
    if (changed) unawaited(widget.store.load());
  }

  Future<void> _remove(ModelProviderRow row) async {
    final d = row.entry.directory;
    final managed =
        row.apiKeyEnv == deriveKeyRef(d.provider) &&
        row.credential?.configured == true &&
        row.credential?.writable == true;
    final accepted = await showDshDialog<bool>(
      context,
      label: t('deleteTitle', {'provider': d.displayName}),
      builder: (dialogContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('deleteTitle', {'provider': d.displayName})),
            SettingsMessage(
              t(
                managed
                    ? 'deleteDescriptionWithCredential'
                    : 'deleteDescription',
                {'provider': d.displayName},
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                DshButton(
                  variant: DshButtonVariant.outline,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(t('cancel')),
                ),
                DshButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(t('deleteConfirm', {'provider': d.displayName})),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _removing = d.provider;
      _error = null;
    });
    try {
      final generation = widget.store.remotes.currentGeneration();
      if (managed) await widget.store.remotes.credentials.unset(row.apiKeyEnv!);
      if (widget.store.disposed ||
          !identical(generation, widget.store.remotes.currentGeneration())) {
        return;
      }
      final answer = await widget.store.remotes.settings.mutate(d.settingsNs, [
        SettingsPathOpViewUnset(path: d.settingsPath),
      ]);
      widget.store.mirror.acceptView(answer);
      await widget.store.load();
    } on Object catch (error) {
      if (mounted) setState(() => _error = settingsError(error));
    } finally {
      if (mounted) setState(() => _removing = null);
    }
  }

  Widget _editor(ModelProviderRow row) {
    final d = row.entry.directory;
    final namespace = widget.store.state.value.namespaces[d.settingsNs];
    if (namespace == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProviderEditor(
          key: ValueKey('provider-editor-${d.provider}'),
          store: widget.store,
          namespace: namespace,
          provider: d.provider,
          displayName: d.displayName,
          path: d.settingsPath,
          declared: d.declared == true,
          defaultBaseURL: d.defaultBaseURL,
          row: row,
          i18n: widget.i18n,
          onClose: _close,
        ),
        _extras(row),
      ],
    );
  }

  Widget _extras(ModelProviderRow row) =>
      widget.slots?.renderOnly(
        DshSlots.modelsProviderCard.typed<ModelsProviderCardOwner, Widget>(),
        row.entry.directory.settingsNs,
        ModelsProviderCardOwner(
          provider: row.entry,
          configured: row.configured,
          keyConfigured: row.apiKeyEnv == null
              ? row.derivedCredential?.configured == true
              : row.credential?.configured == true,
        ),
      ) ??
      const SizedBox.shrink();
  @override
  Widget build(BuildContext context) {
    final state = widget.store.state.value;
    final theme = context.dsh;
    final rows = state.rows;
    final addable = rows
        .where(
          (r) =>
              !r.configured &&
              r.entry.directory.settingsNs.isNotEmpty &&
              r.entry.directory.provider != 'deepseek-account',
        )
        .toList();
    final pi = state.namespaces['llm-pi-ai'];
    final anyUsable = rows.any((r) => r.usable);
    return SingleChildScrollView(
      key: const ValueKey('models-section'),
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('title'),
                style: theme
                    .textStyle('--dsw-font-base-16')
                    .copyWith(color: theme.labelPrimary),
              ),
              const SizedBox(height: 12),
              Text(
                t('intro'),
                style: theme
                    .textStyle('--dsw-font-s-14')
                    .copyWith(color: theme.color('--dsw-alias-label-tertiary')),
              ),
              if (!state.writable && state.status == ModelsSettingsStatus.ready)
                SettingsMessage(t('readOnly')),
              if (state.error != null ||
                  state.credentialError != null ||
                  _error != null) ...[
                SettingsMessage(
                  state.error ?? state.credentialError ?? _error!,
                  error: true,
                ),
                DshButton(
                  onPressed: () => unawaited(widget.store.load()),
                  child: Text(t('retry')),
                ),
              ],
              if (state.status == ModelsSettingsStatus.loading && rows.isEmpty)
                SettingsMessage(widget.i18n.t('common', 'loading')),
              const SizedBox(height: 24),
              for (final row in rows)
                if (row.configured ||
                    row.entry.active ||
                    row.entry.directory.settingsPath.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SettingsCard(
                      child:
                          _editing == row.entry.directory.provider ||
                              !anyUsable &&
                                  row.entry.directory.settingsPath.isEmpty &&
                                  row.entry.directory.provider !=
                                      'deepseek-account' &&
                                  row.credential?.configured != true
                          ? _editor(row)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    Text(
                                      row.entry.directory.displayName,
                                      style: theme
                                          .textStyle('--dsw-font-s-14')
                                          .copyWith(
                                            fontWeight: FontWeight.w500,
                                            color: theme.labelPrimary,
                                          ),
                                    ),
                                    Wrap(
                                      spacing: 4,
                                      children: [
                                        if (state.namespaces.containsKey(
                                              row.entry.directory.settingsNs,
                                            ) &&
                                            row.entry.directory.provider !=
                                                'deepseek-account')
                                          DshButton(
                                            key: ValueKey(
                                              'edit-provider-${row.entry.directory.provider}',
                                            ),
                                            variant: DshButtonVariant.outline,
                                            onPressed:
                                                _editing != null ||
                                                    _removing != null ||
                                                    _adding
                                                ? null
                                                : () => setState(
                                                    () => _editing = row
                                                        .entry
                                                        .directory
                                                        .provider,
                                                  ),
                                            child: Text(t('edit')),
                                          ),
                                        if (row.removable)
                                          DshButton(
                                            key: ValueKey(
                                              'remove-provider-${row.entry.directory.provider}',
                                            ),
                                            variant: DshButtonVariant.outline,
                                            onPressed:
                                                !state.writable ||
                                                    _removing != null
                                                ? null
                                                : () => unawaited(_remove(row)),
                                            child: Text(t('remove')),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (row.entry.directory.error != null)
                                  SettingsMessage(
                                    row.entry.directory.error!,
                                    error: true,
                                  ),
                                if (row.apiKeyEnv != null)
                                  SettingsMessage(
                                    t(
                                      row.credential?.configured == true
                                          ? 'credentialConfigured'
                                          : 'credentialMissing',
                                    ),
                                  ),
                                if (row.accountAvailable)
                                  SettingsMessage(t('accountSignedIn')),
                                _extras(row),
                              ],
                            ),
                    ),
                  ),
              if (_adding)
                SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          DshButton(
                            variant: _custom
                                ? DshButtonVariant.outline
                                : DshButtonVariant.primary,
                            onPressed: () => setState(() {
                              _custom = false;
                              _editing = null;
                            }),
                            child: Text(t('addCatalog')),
                          ),
                          DshButton(
                            variant: _custom
                                ? DshButtonVariant.primary
                                : DshButtonVariant.outline,
                            onPressed:
                                pi == null || providerProtocols(pi).isEmpty
                                ? null
                                : () => setState(() {
                                    _custom = true;
                                    _editing = null;
                                  }),
                            child: Text(t('addCustom')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_custom && pi != null)
                        ProviderEditor(
                          key: const ValueKey('custom-provider-editor'),
                          store: widget.store,
                          namespace: pi,
                          provider: '',
                          displayName: t('addCustom'),
                          path: const [],
                          declared: true,
                          creating: true,
                          i18n: widget.i18n,
                          onClose: _close,
                        )
                      else if (_editing != null &&
                          addable.any(
                            (r) => r.entry.directory.provider == _editing,
                          ))
                        _editor(
                          addable.firstWhere(
                            (r) => r.entry.directory.provider == _editing,
                          ),
                        )
                      else ...[
                        for (final row in addable)
                          DshButton(
                            key: ValueKey(
                              'add-provider-${row.entry.directory.provider}',
                            ),
                            variant: DshButtonVariant.ghost,
                            onPressed: () => setState(
                              () => _editing = row.entry.directory.provider,
                            ),
                            child: Text(row.entry.directory.displayName),
                          ),
                        if (addable.isEmpty)
                          SettingsMessage(t('addCatalogExhausted')),
                        DshButton(
                          variant: DshButtonVariant.outline,
                          onPressed: () => _close(false),
                          child: Text(t('cancel')),
                        ),
                      ],
                    ],
                  ),
                ),
              if (!_adding)
                DshButton(
                  key: const ValueKey('add-model-provider'),
                  variant: DshButtonVariant.outline,
                  onPressed: !state.writable || _editing != null
                      ? null
                      : () => setState(() => _adding = true),
                  child: Text(t('add')),
                ),
              ...?widget.slots?.renderList(
                DshSlots.modelsFooter.typed<SettingsOwner, Widget>(),
                const SettingsOwner(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DshDecoratedBox(
    decoration: BoxDecoration(
      color: context.dsh.color('--dsw-alias-settings-card-fill'),
      borderRadius: BorderRadius.circular(context.dsh.radiusXl),
      border: Border.all(
        color: context.dsh.color('--dsw-alias-settings-card-stroke'),
        width: .5,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: child,
    ),
  );
}

class SettingsMessage extends StatelessWidget {
  const SettingsMessage(this.text, {super.key, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Semantics(
      liveRegion: error,
      child: Text(
        text,
        style: context.dsh
            .textStyle('--dsw-font-xxs-12')
            .copyWith(
              color: error
                  ? context.dsh.color('--dsw-alias-state-error-primary')
                  : context.dsh.color('--dsw-alias-label-tertiary'),
            ),
      ),
    ),
  );
}
