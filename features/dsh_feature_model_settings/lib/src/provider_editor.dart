import 'dart:async';

import 'package:dsh_client/generated_llm.dart';
import 'package:dsh_client/generated_settings.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'models_section.dart';
import 'model_input.dart';

class ProviderEditor extends StatefulWidget {
  const ProviderEditor({
    super.key,
    required this.store,
    required this.namespace,
    required this.provider,
    required this.displayName,
    required this.path,
    required this.i18n,
    required this.onClose,
    this.declared = false,
    this.creating = false,
    this.defaultBaseURL,
    this.row,
  });
  final ModelsSettingsStore store;
  final SettingsNamespaceView namespace;
  final String provider;
  final String displayName;
  final List<String> path;
  final bool declared;
  final bool creating;
  final String? defaultBaseURL;
  final ModelProviderRow? row;
  final DshI18n i18n;
  final ValueChanged<bool> onClose;
  @override
  State<ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends State<ProviderEditor> {
  late final ProviderSettingsDraft _draft;
  late final TextEditingController _key;
  bool _reveal = false;
  bool _advanced = false;
  bool _fetchOpen = false;
  String _search = '';
  final _capacityTexts = <String, String>{};
  List<LlmDiscoveredModel> _found = [];
  final Set<String> _picked = {};
  String t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('settings.models', key, params: params);
  @override
  void initState() {
    super.initState();
    _key = TextEditingController();
    _draft = ProviderSettingsDraft(
      remotes: widget.store.remotes,
      mirror: widget.store.mirror,
      namespace: widget.namespace,
      provider: widget.provider,
      path: widget.path,
      creating: widget.creating,
      declared: widget.declared,
    );
    if (widget.creating) {
      _draft.draft['api'] = providerProtocols(widget.namespace).firstOrNull;
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    _key.clear();
    _key.dispose();
    super.dispose();
  }

  bool get _blocked =>
      _draft.busy || _draft.discovering || !widget.store.state.value.writable;
  bool get _profileBlocked =>
      _blocked || widget.creating && _draft.profileCommitted;
  bool get _routeTaken =>
      widget.creating &&
      !_draft.profileCommitted &&
      widget.store.state.value.rows.any(
        (r) => r.entry.directory.provider == _draft.provider,
      );
  Future<void> _save() async {
    if (_routeTaken) return;
    final work = _draft.save(writable: widget.store.state.value.writable);
    setState(() {});
    final success = await work;
    if (!mounted) return;
    setState(() {});
    if (success) {
      _key.clear();
      widget.onClose(true);
    }
  }

  Future<void> _discover() async {
    final work = _draft.discover();
    setState(() {});
    final models = await work;
    if (!mounted) return;
    setState(() {
      if (models != null) {
        _found = models;
        _fetchOpen = true;
        _picked.clear();
        final existing = {for (final m in _draft.models) m['id']};
        _picked.addAll(
          models.where((m) => !existing.contains(m.id)).map((m) => m.id),
        );
      }
    });
  }

  void _changeModel(int index, String field, Object? value) {
    final models = _draft.models;
    if (value == null) {
      models[index].remove(field);
    } else {
      models[index][field] = value;
    }
    setState(() => _draft.setField('models', models));
  }

  String _failure(String value) {
    final parts = value.split(':');
    if (parts.length == 2 && int.tryParse(parts[0]) != null) {
      return '${t('model')} ${parts[0]}: ${t(parts[1])}';
    }
    const keys = {
      'conflict',
      'keyBlank',
      'keyIllegalCharacters',
      'customRouteInvalid',
      'customBaseUrlInvalid',
      'customApiUnset',
      'customNeedsModels',
    };
    return keys.contains(value) ? t(value) : value;
  }

  Widget _field(String name, String label, {String? hint}) =>
      SettingsEditorField(
        key: ValueKey('provider-$name-field'),
        id: 'provider-$name',
        label: t(label),
        text: _draft.draft[name] is String ? _draft.draft[name] as String : '',
        hint: hint,
        enabled: !_profileBlocked,
        onChanged: (value) => setState(() => _draft.setField(name, value)),
      );
  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final known = const [
      'llm-deepseek',
      'llm-pi-ai',
    ].contains(widget.namespace.ns);
    final keyFailure = apiKeyFailure(_key.text);
    final keylessNative =
        widget.row?.apiKeyEnv == null &&
        widget.row?.entry.directory.nativeAuth?.env.isEmpty == true &&
        widget.row?.entry.directory.nativeAuth?.oauth == true;
    final row = widget.row;
    final named = row?.apiKeyEnv;
    final endpointEnv = row?.entry.directory.baseURLEnv ?? const <String>[];
    final authRefs = named == null
        ? (row?.entry.directory.nativeAuth?.env ?? const <String>[])
              .where((ref) => !endpointEnv.contains(ref))
              .toList()
        : [named];
    final visibleRefs = authRefs
        .where((ref) => !ref.toLowerCase().contains('oauth'))
        .toList();
    final detected = authRefs
        .where(
          (ref) =>
              row?.credentialChecks?[ref]?.configured == true ||
              ref == named && row?.credential?.configured == true,
        )
        .firstOrNull;
    final missing =
        authRefs.isNotEmpty &&
        authRefs.every(
          (ref) => row?.credentialChecks?[ref]?.configured == false,
        );
    final credentialHint =
        _key.text.isNotEmpty ||
            row?.credential?.source == 'file' ||
            visibleRefs.isEmpty
        ? null
        : t(
            detected == null
                ? missing
                      ? 'keyFallbackMissing'
                      : 'keyFallbackUnchecked'
                : visibleRefs.contains(detected)
                ? 'keyFallbackDetected'
                : 'keyFallbackDetectedHidden',
            {'hint': detected ?? visibleRefs.first},
          );
    final models = _draft.models;
    final failure =
        validateProviderModels(_draft.draft['models']) ??
        (widget.declared
            ? validateModelReasoning(_draft.draft['models'])
            : null);
    final protocols = providerProtocols(widget.namespace);
    return DshDecoratedBox(
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-bg-module-platform'),
        borderRadius: BorderRadius.circular(theme.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.displayName,
              style: theme
                  .textStyle('--dsw-font-s-14')
                  .copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.labelPrimary,
                  ),
            ),
            if (widget.creating)
              SettingsEditorField(
                id: 'provider-route',
                label: t('customRoute'),
                text: _draft.provider,
                enabled: !_profileBlocked,
                hint: t('customRouteHint'),
                onChanged: (v) => setState(() => _draft.provider = v),
              ),
            if (_routeTaken)
              SettingsMessage(t('customRouteTaken'), error: true),
            if (!keylessNative) ...[
              const SizedBox(height: 12),
              Text(
                t('keyInput'),
                style: theme
                    .textStyle('--dsw-font-xxs-12')
                    .copyWith(
                      fontWeight: FontWeight.w500,
                      color: theme.labelSecondary,
                    ),
              ),
              const SizedBox(height: 6),
              ModelSettingsInput(
                key: const ValueKey('provider-api-key'),
                secret: true,
                semanticLabel: t('keyInput'),
                controller: _key,
                obscure: !_reveal,
                enabled: !_blocked,
                placeholder: t(
                  widget.row?.credential?.configured == true
                      ? 'keyPlaceholderSaved'
                      : 'keyPlaceholder',
                ),
                errorText: keyFailure == null ? null : t(keyFailure),
                onChanged: (v) => setState(() {
                  _draft.keyDraft = v;
                  _reveal = false;
                }),
                trailing: _key.text.isEmpty
                    ? null
                    : MergeSemantics(
                        child: Semantics(
                          toggled: _reveal,
                          child: DshButton(
                            variant: DshButtonVariant.ghost,
                            size: DshButtonSize.sm,
                            key: const ValueKey('provider-key-reveal'),
                            semanticLabel: t(_reveal ? 'keyHide' : 'keyReveal'),
                            onPressed: _blocked
                                ? null
                                : () => setState(() => _reveal = !_reveal),
                            child: DshIcon(
                              _reveal ? modelKeyEyeOff : modelKeyEye,
                              color: theme.labelSecondary,
                            ),
                          ),
                        ),
                      ),
              ),
              if (credentialHint != null) SettingsMessage(credentialHint),
              if (widget.row?.credential?.configured == true)
                SettingsMessage(t('credentialConfigured')),
            ],
            DshButton(
              key: const ValueKey('provider-customized'),
              variant: DshButtonVariant.ghost,
              onPressed: _blocked
                  ? null
                  : () => setState(() => _advanced = !_advanced),
              child: Text(t('customized')),
            ),
            if (_advanced || widget.creating) ...[
              if (!known)
                SettingsMessage(t('advancedHint'))
              else ...[
                if (widget.declared)
                  _field(
                    'displayName',
                    'customDisplayName',
                    hint: _draft.provider,
                  ),
                _field(
                  'baseURL',
                  'baseUrl',
                  hint: widget.namespace.ns == 'llm-deepseek'
                      ? t('deepSeekBaseUrl')
                      : widget.defaultBaseURL ?? t('baseUrlDefault'),
                ),
                if (widget.declared && widget.namespace.ns == 'llm-pi-ai') ...[
                  Text(t('customApi')),
                  DshSelectorPill(
                    key: const ValueKey('provider-protocol'),
                    label:
                        _draft.field('api') as String? ?? t('customApiUnset'),
                    onPressed: _profileBlocked
                        ? null
                        : () async {
                            final next = await showDshOptionSheet(
                              context,
                              title: t('customApi'),
                              selectedId: _draft.field('api') as String?,
                              options: [
                                for (final protocol in protocols)
                                  DshOption(id: protocol, label: protocol),
                              ],
                            );
                            if (mounted && next != null) {
                              setState(() => _draft.setField('api', next));
                            }
                          },
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      t('models'),
                      style: theme.textStyle('--dsw-font-s-14'),
                    ),
                    DshButton(
                      key: const ValueKey('reset-provider-models'),
                      variant: DshButtonVariant.ghost,
                      size: DshButtonSize.sm,
                      onPressed:
                          _profileBlocked || !_draft.draft.containsKey('models')
                          ? null
                          : () => setState(() {
                              _capacityTexts.clear();
                              _draft.setField('models', null);
                            }),
                      child: Text(t('resetModels')),
                    ),
                    if (widget.namespace.ns == 'llm-pi-ai')
                      DshButton(
                        key: const ValueKey('fetch-provider-models'),
                        variant: DshButtonVariant.outline,
                        onPressed: _profileBlocked || keyFailure != null
                            ? null
                            : () => unawaited(_discover()),
                        child: Text(
                          t(_draft.discovering ? 'fetching' : 'fetchModels'),
                        ),
                      ),
                  ],
                ),
                if (_fetchOpen) ...[
                  SettingsEditorField(
                    id: 'discovery-search',
                    label: t('fetchSearch'),
                    text: _search,
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  if (_found.isEmpty) SettingsMessage(t('fetchEmpty')),
                  for (final found in _found.where(
                    (m) => '${m.id} ${m.name ?? ''}'.toLowerCase().contains(
                      _search.toLowerCase(),
                    ),
                  ))
                    DshSettingsRow(
                      title: found.name ?? found.id,
                      description: found.id,
                      control: DshSwitch(
                        value: _picked.contains(found.id),
                        label: found.id,
                        onChanged: (selected) => setState(() {
                          if (selected) {
                            _picked.add(found.id);
                          } else {
                            _picked.remove(found.id);
                          }
                        }),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      DshButton(
                        variant: DshButtonVariant.outline,
                        onPressed: () => setState(() {
                          _picked.addAll(_found.map((m) => m.id));
                        }),
                        child: Text(t('fetchSelectAll')),
                      ),
                      DshButton(
                        variant: DshButtonVariant.outline,
                        onPressed: () => setState(_picked.clear),
                        child: Text(t('fetchDeselectAll')),
                      ),
                      DshButton(
                        key: const ValueKey('adopt-provider-models'),
                        variant: DshButtonVariant.outline,
                        onPressed: _profileBlocked
                            ? null
                            : () => setState(() {
                                final byId = {
                                  for (final m in models) m['id']: m,
                                };
                                for (final m in _found.where(
                                  (m) => _picked.contains(m.id),
                                )) {
                                  byId.putIfAbsent(
                                    m.id,
                                    () => {
                                      'id': m.id,
                                      if (m.name != null) 'name': m.name,
                                      if (m.contextWindow != null)
                                        'contextWindow': m.contextWindow,
                                      if (m.maxTokens != null)
                                        'maxTokens': m.maxTokens,
                                      if (m.inputModalities != null)
                                        'input': m.inputModalities!
                                            .map((m) => m.toJson())
                                            .toList(),
                                    },
                                  );
                                }
                                _capacityTexts.clear();
                                _draft.setField('models', byId.values.toList());
                                _fetchOpen = false;
                              }),
                        child: Text(t('fetchAdopt')),
                      ),
                    ],
                  ),
                ],
                if (models.isEmpty) SettingsMessage(t('modelsEmpty')),
                for (var i = 0; i < models.length; i++)
                  SettingsCard(
                    key: ValueKey('provider-model-$i'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final field in const [
                          'id',
                          'name',
                          'contextWindow',
                          'maxTokens',
                        ])
                          SettingsEditorField(
                            key: ValueKey('model-$i-$field-field'),
                            id: 'model-$i-$field',
                            label: t(switch (field) {
                              'id' => 'modelId',
                              'name' => 'modelName',
                              _ => field,
                            }),
                            text:
                                _capacityTexts['$i:$field'] ??
                                (models[i][field] is num
                                    ? formatModelCapacity(
                                        models[i][field] as num,
                                      )
                                    : models[i][field] as String? ?? ''),
                            enabled: !_profileBlocked,
                            onChanged: (v) {
                              if (const [
                                'contextWindow',
                                'maxTokens',
                              ].contains(field)) {
                                _capacityTexts['$i:$field'] = v;
                              }
                              _changeModel(
                                i,
                                field,
                                const [
                                      'contextWindow',
                                      'maxTokens',
                                    ].contains(field)
                                    ? parseModelCapacity(v)
                                    : v.trim().isEmpty && field == 'name'
                                    ? null
                                    : v,
                              );
                            },
                          ),
                        if (widget.declared) ...[
                          for (final modality in ['text', 'image'])
                            DshSettingsRow(
                              description: '',
                              title: t(
                                modality == 'text'
                                    ? 'modelInputText'
                                    : 'modelInputImage',
                              ),
                              control: DshSwitch(
                                value:
                                    (models[i]['input'] is List
                                            ? models[i]['input'] as List
                                            : const ['text'])
                                        .contains(modality),
                                label: t('modelInputTypes'),
                                onChanged: _profileBlocked
                                    ? null
                                    : (selected) {
                                        final inputs = <Object?>{
                                          ...models[i]['input'] is List
                                              ? models[i]['input'] as List
                                              : const ['text'],
                                        };
                                        if (selected) {
                                          inputs.add(modality);
                                        } else {
                                          inputs.remove(modality);
                                        }
                                        _changeModel(
                                          i,
                                          'input',
                                          inputs.toList(),
                                        );
                                      },
                              ),
                            ),
                          ModelReasoningEditor(
                            model: models[i],
                            levels: providerReasoningLevels(widget.namespace),
                            t: t,
                            disabled: _profileBlocked,
                            onChanged: (value) =>
                                _changeModel(i, 'reasoningEfforts', value),
                          ),
                        ],
                        DshButton(
                          variant: DshButtonVariant.ghost,
                          onPressed: _profileBlocked
                              ? null
                              : () {
                                  _capacityTexts.clear();
                                  models.removeAt(i);
                                  setState(
                                    () => _draft.setField('models', models),
                                  );
                                },
                          child: Text(t('removeModel')),
                        ),
                      ],
                    ),
                  ),
                DshButton(
                  key: const ValueKey('add-provider-model'),
                  variant: DshButtonVariant.outline,
                  onPressed: _profileBlocked
                      ? null
                      : () {
                          models.add({'id': ''});
                          setState(() => _draft.setField('models', models));
                        },
                  child: Text(t('addModel')),
                ),
              ],
            ],
            if (failure != null)
              SettingsMessage(
                '${t('model')} ${failure.index + 1}: ${t(failure.key)}',
                error: true,
              ),
            if (widget.creating &&
                _draft.provider.isNotEmpty &&
                _draft.validate() != null &&
                keyFailure == null &&
                failure == null)
              SettingsMessage(_failure(_draft.validate()!), error: true),
            if (_draft.error != null)
              SettingsMessage(_failure(_draft.error!), error: true),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                DshButton(
                  key: const ValueKey('provider-cancel'),
                  variant: DshButtonVariant.outline,
                  onPressed: _draft.busy || _draft.discovering
                      ? null
                      : () => widget.onClose(_draft.profileCommitted),
                  child: Text(t('cancel')),
                ),
                DshButton(
                  key: const ValueKey('provider-save'),
                  variant: DshButtonVariant.primary,
                  onPressed:
                      _blocked ||
                          keyFailure != null ||
                          failure != null ||
                          _routeTaken ||
                          _draft.validate() != null
                      ? null
                      : () => unawaited(_save()),
                  child: Text(
                    t(
                      _draft.busy
                          ? 'applying'
                          : widget.creating
                          ? 'create'
                          : 'apply',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsEditorField extends StatefulWidget {
  const SettingsEditorField({
    super.key,
    required this.id,
    required this.label,
    required this.text,
    required this.onChanged,
    this.hint,
    this.enabled = true,
  });
  final String id;
  final String label;
  final String text;
  final String? hint;
  final bool enabled;
  final ValueChanged<String> onChanged;
  @override
  State<SettingsEditorField> createState() => _SettingsEditorFieldState();
}

class _SettingsEditorFieldState extends State<SettingsEditorField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  @override
  void didUpdateWidget(SettingsEditorField old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text && _controller.text != widget.text) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: context.dsh
              .textStyle('--dsw-font-s-14')
              .copyWith(color: context.dsh.labelPrimary),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: widget.label,
          textField: true,
          child: ModelSettingsInput(
            key: ValueKey(widget.id),
            controller: _controller,
            placeholder: widget.hint,
            enabled: widget.enabled,
            onChanged: widget.onChanged,
          ),
        ),
      ],
    ),
  );
}

class ModelReasoningEditor extends StatelessWidget {
  const ModelReasoningEditor({
    super.key,
    required this.model,
    required this.levels,
    required this.t,
    required this.disabled,
    required this.onChanged,
  });
  final Map<String, Object?> model;
  final List<String> levels;
  final String Function(String) t;
  final bool disabled;
  final ValueChanged<Object?> onChanged;
  @override
  Widget build(BuildContext context) {
    final stored = model['reasoningEfforts'];
    final entries = stored is Map
        ? Map<String, Object?>.from(stored)
        : <String, Object?>{};
    final enabled = stored is Map;
    if (levels.isEmpty && !enabled) return const SizedBox.shrink();
    return Column(
      children: [
        DshSettingsRow(
          description: '',
          title: t('modelReasoning'),
          control: DshSwitch(
            label: t('modelReasoning'),
            value: enabled,
            onChanged: disabled
                ? null
                : (value) => onChanged(
                    value
                        ? {
                            for (final level in [
                              'off',
                              'low',
                              'high',
                            ].where(levels.contains))
                              level: level == 'off' ? null : level,
                          }
                        : null,
                  ),
          ),
        ),
        if (enabled) ...[
          for (final entry in entries.entries)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SettingsEditorField(
                    key: ValueKey('effort-${entry.key}'),
                    id: 'effort-${entry.key}',
                    label: entry.key,
                    text: entry.value as String? ?? '',
                    enabled: !disabled,
                    onChanged: (v) => onChanged({
                      ...entries,
                      entry.key: v.trim().isEmpty
                          ? entry.key == 'off'
                                ? null
                                : entry.key
                          : v.trim(),
                    }),
                  ),
                ),
                DshButton(
                  variant: DshButtonVariant.ghost,
                  onPressed: disabled
                      ? null
                      : () {
                          entries.remove(entry.key);
                          onChanged(entries);
                        },
                  child: Text(t('modelReasoningRemove')),
                ),
              ],
            ),
          DshButton(
            variant: DshButtonVariant.outline,
            onPressed: disabled || levels.every(entries.containsKey)
                ? null
                : () {
                    final level = levels.firstWhere(
                      (l) => !entries.containsKey(l),
                    );
                    onChanged({
                      ...entries,
                      level: level == 'off' ? null : level,
                    });
                  },
            child: Text(t('modelReasoningAdd')),
          ),
        ],
      ],
    );
  }
}
