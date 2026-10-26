import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/generated.dart' as wire;
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

typedef AllowedModel = ({String provider, String model});
String subagentModelKey(AllowedModel model) =>
    '${model.provider}\u0000${model.model}';
List<AllowedModel> allowedModels(Object? value) => value is List
    ? [
        for (final m in value)
          if (m is Map && m['provider'] is String && m['model'] is String)
            (provider: m['provider'] as String, model: m['model'] as String),
      ]
    : [];

class SubagentModelCandidate {
  const SubagentModelCandidate(
    this.route,
    this.providerName,
    this.modelName,
    this.available,
    this.selected,
  );
  final AllowedModel route;
  final String providerName;
  final String modelName;
  final bool available;
  final bool selected;
  String get key => subagentModelKey(route);
}

List<SubagentModelCandidate> subagentModelCandidates(
  List<wire.ModelProviderGroup> groups,
  List<AllowedModel> stored,
  Set<String> selected,
) {
  final retained = {for (final route in stored) subagentModelKey(route): route};
  final rows = <SubagentModelCandidate>[];
  for (final group in groups) {
    for (final model in group.models) {
      final route = (provider: group.id, model: model.id);
      final key = subagentModelKey(route);
      retained.remove(key);
      rows.add(
        SubagentModelCandidate(
          route,
          group.name,
          model.name,
          true,
          selected.contains(key),
        ),
      );
    }
  }
  rows.addAll([
    for (final e in retained.entries)
      SubagentModelCandidate(
        e.value,
        e.value.provider,
        e.value.model,
        false,
        selected.contains(e.key),
      ),
  ]);
  return rows;
}

bool _sameRoutes(List<AllowedModel> left, List<AllowedModel> right) =>
    left.length == right.length &&
    left.every(
      (m) => right.map(subagentModelKey).contains(subagentModelKey(m)),
    );

class SubagentModelsController {
  SubagentModelsController(this.form, this.remotes) {
    _off = form.subscribe(() {
      if (!saving && _draft != null && form.snapshot.revision != _revision) {
        if (enabled == _currentEnabled && _sameRoutes(desired, _current)) {
          discard();
        } else {
          conflicted = true;
        }
      }
      if (enabled && catalogStatus == 'idle') unawaited(loadCatalog());
      _publish();
    });
    for (final e in ['llm/adapters-updated', 'settings/document-updated']) {
      _subs.add(remotes.emitted(e).listen((_) => refreshCatalog()));
    }
    _subs.add(
      remotes.generations.listen((_) {
        _saveGeneration++;
        saving = false;
        discard();
        _groups = [];
        refreshCatalog();
      }),
    );
    if (enabled) unawaited(loadCatalog());
  }
  final ConfigForm form;
  final HostRemotes remotes;
  final changed = Observable(0);
  late final void Function() _off;
  final List<StreamSubscription<Object?>> _subs = [];
  Map<String, AllowedModel>? _draft;
  bool? _draftEnabled;
  int? _revision;
  List<wire.ModelProviderGroup> _groups = [];
  String catalogStatus = 'idle';
  bool catalogPartial = false;
  bool saving = false;
  bool failed = false;
  bool conflicted = false;
  bool _disposed = false;
  int _catalogGeneration = 0;
  int _saveGeneration = 0;
  bool get _currentEnabled => form.snapshot.value?['enabled'] == true;
  List<AllowedModel> get _current =>
      allowedModels(form.snapshot.value?['allowedModels']);
  bool get enabled => _draftEnabled ?? _currentEnabled;
  List<AllowedModel> get desired => _draft?.values.toList() ?? _current;
  bool get dirty =>
      enabled != _currentEnabled || !_sameRoutes(desired, _current);
  SettingsFormShell get shell => SettingsFormShell(
    available: form.snapshot.status == ConfigFormStatus.ready,
    writable: form.snapshot.writable,
    dirty: dirty,
    invalid: enabled && desired.isEmpty,
    saving: saving,
    failed: failed,
  );
  List<SubagentModelCandidate> get candidates => subagentModelCandidates(
    _groups,
    {
      for (final m in [..._current, ...desired]) subagentModelKey(m): m,
    }.values.toList(),
    desired.map(subagentModelKey).toSet(),
  );
  void _begin() {
    if (_draft != null) return;
    _draft = {for (final m in _current) subagentModelKey(m): m};
    _draftEnabled = _currentEnabled;
    _revision = form.snapshot.revision;
  }

  void toggleEnabled(bool value) {
    if (saving || !form.snapshot.writable || _disposed) return;
    _begin();
    _draftEnabled = value;
    failed = false;
    if (enabled && catalogStatus == 'idle') unawaited(loadCatalog());
    _publish();
  }

  void toggleModel(String key) {
    if (saving || !enabled || !form.snapshot.writable || _disposed) return;
    final rows = candidates.where((r) => r.key == key);
    if (rows.isEmpty) return;
    final row = rows.first;
    _begin();
    if (_draft!.containsKey(key)) {
      _draft!.remove(key);
    } else {
      _draft![key] = row.route;
    }
    failed = false;
    _publish();
  }

  void discard() {
    if (saving) return;
    _draft = null;
    _draftEnabled = null;
    _revision = null;
    failed = false;
    conflicted = false;
    _publish();
  }

  Future<void> save() async {
    if (_disposed ||
        !shell.available ||
        !shell.writable ||
        !dirty ||
        shell.invalid ||
        saving) {
      return;
    }
    if (_draft != null && form.snapshot.revision != _revision) {
      conflicted = true;
      _publish();
      return;
    }
    final generation = _saveGeneration;
    final target = desired;
    final targetEnabled = enabled;
    saving = true;
    failed = false;
    conflicted = false;
    _publish();
    try {
      await form.mutate([
        SetOp(['enabled'], targetEnabled),
        SetOp(
          ['allowedModels'],
          [
            for (final m in target) {'provider': m.provider, 'model': m.model},
          ],
        ),
      ], expectedRevision: _revision);
    } on Object {
      /* judge against the accepted facts */
    }
    if (_disposed || generation != _saveGeneration) return;
    saving = false;
    failed = _currentEnabled != targetEnabled || !_sameRoutes(_current, target);
    if (!failed) discard();
    _publish();
  }

  void refreshCatalog() {
    if (_disposed) return;
    _catalogGeneration++;
    catalogStatus = 'idle';
    catalogPartial = false;
    if (enabled) {
      unawaited(loadCatalog());
    } else {
      _publish();
    }
  }

  Future<void> loadCatalog() async {
    if (_disposed || catalogStatus == 'loading') return;
    final generation = _catalogGeneration;
    catalogStatus = 'loading';
    _publish();
    try {
      final catalog = await remotes.session.modelCatalog();
      if (_disposed || generation != _catalogGeneration) return;
      _groups = catalog.groups;
      catalogPartial = catalog.failures.isNotEmpty;
      catalogStatus = 'ready';
    } on Object {
      if (!_disposed && generation == _catalogGeneration) {
        catalogStatus = 'error';
      }
    }
    _publish();
  }

  void _publish() {
    if (!_disposed) changed.set(changed.value + 1);
  }

  Future<void> dispose() async {
    _disposed = true;
    _catalogGeneration++;
    _saveGeneration++;
    _off();
    for (final s in _subs) {
      await s.cancel();
    }
    await changed.dispose();
  }
}

class SubagentModelsCard extends StatefulWidget {
  const SubagentModelsCard({
    super.key,
    required this.controller,
    required this.i18n,
    this.embedded = false,
    this.combinedShell,
  });
  final SubagentModelsController controller;
  final DshI18n i18n;
  final bool embedded;
  final SettingsFormShell? combinedShell;
  @override
  State<SubagentModelsCard> createState() => _SubagentModelsCardState();
}

class _SubagentModelsCardState extends State<SubagentModelsCard> {
  StreamSubscription<Object?>? sub;
  String t(String key) => widget.i18n.t('settings.subagent', key);
  @override
  void initState() {
    super.initState();
    sub = widget.controller.changed.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(sub?.cancel());
    widget.controller.discard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final shell = widget.combinedShell ?? c.shell;
    final fields = <Widget>[
      Text(
        t('subagentModelSelectionTitle'),
        style: context.dsh.textStyle('--dsw-font-base-16'),
      ),
      DshSettingsRow(
        title: t('subagentModelSelectionToggle'),
        description: t('subagentModelSelectionChoose'),
        control: DshSwitch(
          key: const ValueKey('subagent-model-selection-enabled'),
          label: t('subagentModelSelectionToggle'),
          value: c.enabled,
          onChanged: !shell.writable || shell.saving ? null : c.toggleEnabled,
        ),
      ),
      if (c.conflicted) Text(t('subagentModelSelectionConflict')),
      if (!c.enabled) Text(t('subagentModelSelectionOff')),
      if (c.enabled) ...[
        if (c.catalogStatus == 'loading')
          Text(t('subagentModelSelectionLoading')),
        if (c.catalogStatus == 'error') ...[
          Text(t('subagentModelSelectionLoadFailed')),
          DshButton(
            onPressed: () => unawaited(c.loadCatalog()),
            child: Text(t('subagentModelSelectionRetry')),
          ),
        ],
        if (c.catalogPartial) Text(t('subagentModelSelectionPartial')),
        if (c.candidates.isEmpty && c.catalogStatus == 'ready')
          Text(t('subagentModelSelectionEmpty')),
        for (final row in c.candidates)
          DshSettingsRow(
            title: '${row.providerName} / ${row.modelName}',
            description: row.available
                ? row.route.model
                : t('subagentModelSelectionUnavailable'),
            control: DshSwitch(
              key: ValueKey(
                'subagent-model-${jsonEncode([row.route.provider, row.route.model])}',
              ),
              value: row.selected,
              label: '${row.providerName} / ${row.modelName}',
              onChanged: !shell.writable || shell.saving
                  ? null
                  : (_) => c.toggleModel(row.key),
            ),
          ),
        if (shell.invalid) Text(t('subagentModelSelectionRequired')),
      ],
      if (c.conflicted)
        DshButton(
          variant: DshButtonVariant.outline,
          onPressed: c.discard,
          child: Text(widget.i18n.t('common', 'cancel')),
        ),
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: fields,
      );
    }
    return DshSettingsForm(
      labels: DshSettingsFormLabels(
        unavailable: t('unavailable'),
        readOnly: t('readOnly'),
        saveFailed: t('saveFailed'),
        save: t('save'),
        saving: t('saving'),
      ),
      state: shell,
      onSave: () => unawaited(c.save()),
      onDiscard: c.discard,
      children: fields,
    );
  }
}
