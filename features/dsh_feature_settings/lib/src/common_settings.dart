import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'form_scope.dart';
import 'subagent_models.dart';
import 'subagent_settings.dart';
import 'web_search.dart';

typedef NumberSetting = ({
  String field,
  String labelKey,
  String? hintKey,
  int? minimum,
  String? invalid,
});

/// Plugin-owned staged numeric fields. Reset is an unset; saves retain the
/// opening revision fence through the shared SettingsFormModel.
class NumberSettingsCard extends StatefulWidget {
  const NumberSettingsCard({
    super.key,
    required this.form,
    required this.i18n,
    required this.namespace,
    required this.title,
    required this.fields,
  });
  final ConfigForm form;
  final DshI18n i18n;
  final String namespace;
  final String title;
  final List<NumberSetting> fields;
  @override
  State<NumberSettingsCard> createState() => _NumberSettingsCardState();
}

class _NumberSettingsCardState extends State<NumberSettingsCard> {
  late final SettingsFormModel model;
  late final void Function() off;
  String t(String key) => widget.i18n.t(widget.namespace, key);
  @override
  void initState() {
    super.initState();
    model = SettingsFormModel(ConfigFormScope(widget.form), [
      for (final f in widget.fields)
        f.minimum == null
            ? settingsNumberField(f.field)
            : settingsLimitField(f.field, f.minimum!),
    ]);
    off = model.bind(model.shell).subscribe(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    off();
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = model.shell();
    final actions = model.actions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          t(widget.title),
          style: context.dsh
              .textStyle('--dsw-font-base-16')
              .copyWith(color: context.dsh.labelPrimary),
        ),
        const SizedBox(height: 12),
        DshSettingsForm(
          labels: DshSettingsFormLabels(
            unavailable: t('unavailable'),
            readOnly: t('readOnly'),
            saveFailed: t('saveFailed'),
            save: t('save'),
            saving: t('saving'),
          ),
          state: shell,
          onSave: actions.save,
          onDiscard: actions.discard,
          children: [
            for (var i = 0; i < widget.fields.length; i++)
              Builder(
                builder: (context) {
                  final f = widget.fields[i];
                  final state = model.field(f.field);
                  return DshSettingsValueField(
                    id: f.field,
                    label: t(f.labelKey),
                    text: state.text,
                    overridden: state.overridden,
                    invalid: state.invalid,
                    overriddenLabel: t('overridden'),
                    resetLabel: t('reset'),
                    invalidLabel: t(f.invalid ?? 'invalidNumber'),
                    hint: f.hintKey == null ? null : t(f.hintKey!),
                    numeric: true,
                    disabled: !shell.writable || shell.saving,
                    topDivider: i != 0,
                    onEdit: (v) => actions.edit(f.field, v),
                    onReset: () => actions.resetField(f.field),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class AcceptedToggle {
  AcceptedToggle(this.form);
  final ConfigForm form;
  final state = Observable<(bool busy, String? notice, int sequence)>((
    false,
    null,
    0,
  ));
  bool _disposed = false;
  Future<void> set(bool value) async {
    if (_disposed || state.value.$1) return;
    state.set((true, null, state.value.$3));
    var accepted = false;
    try {
      accepted = await form.set('enabled', value);
    } on Object {
      /* accepted snapshot stays visible */
    }
    if (!_disposed) {
      state.set((false, accepted ? 'saved' : 'failed', state.value.$3 + 1));
    }
  }

  void dismiss() {
    if (!_disposed) state.set((state.value.$1, null, state.value.$3));
  }

  Future<void> dispose() async {
    _disposed = true;
    await state.dispose();
  }
}

class AcceptedToggleRow extends StatefulWidget {
  const AcceptedToggleRow({
    super.key,
    required this.controller,
    required this.title,
    required this.description,
    required this.failure,
  });
  final AcceptedToggle controller;
  final String title;
  final String description;
  final String failure;
  @override
  State<AcceptedToggleRow> createState() => _AcceptedToggleRowState();
}

class _AcceptedToggleRowState extends State<AcceptedToggleRow> {
  late final void Function() off;
  StreamSubscription<Object?>? sub;
  @override
  void initState() {
    super.initState();
    off = widget.controller.form.subscribe(_changed);
    sub = widget.controller.state.changes.listen((_) => _changed());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    off();
    unawaited(sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final form = c.form.snapshot;
    return DshSettingsRow(
      title: widget.title,
      description: c.state.value.$2 == 'failed'
          ? widget.failure
          : widget.description,
      alert: c.state.value.$2 == 'failed',
      control: DshSwitch(
        value: form.value?['enabled'] == true,
        label: widget.title,
        onChanged:
            form.status != ConfigFormStatus.ready ||
                !form.writable ||
                c.state.value.$1
            ? null
            : (value) => unawaited(c.set(value)),
      ),
    );
  }
}

class SettingsUploadNotice extends StatelessWidget {
  const SettingsUploadNotice({
    super.key,
    required this.controller,
    required this.i18n,
  });
  final AcceptedToggle controller;
  final DshI18n i18n;
  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: controller.state.changes,
    builder: (context, _) {
      final s = controller.state.value;
      return s.$2 == null
          ? const SizedBox.shrink()
          : DshToast(
              key: ValueKey('upload-notice-${s.$3}'),
              text: i18n.t('settings.sessionLog', s.$2!),
              tone: s.$2 == 'saved' ? DshToastTone.success : null,
              onDone: () {
                if (controller.state.value.$3 == s.$3) controller.dismiss();
              },
            );
    },
  );
}

/// Shared frame over plugin cards. Task16 extends this ledger with marketplace
/// management; settings cards already keep their individual owning namespaces.
class PluginSettingsSection extends StatefulWidget {
  const PluginSettingsSection({super.key, required this.slots});
  final SlotRegistry slots;
  @override
  State<PluginSettingsSection> createState() => _PluginSettingsSectionState();
}

class _PluginSettingsSectionState extends State<PluginSettingsSection> {
  StreamSubscription<String>? sub;
  @override
  void initState() {
    super.initState();
    sub = widget.slots.changes.listen((name) {
      if (name == DshSlots.pluginsItem.name && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in widget.slots.renderList(
          DshSlots.pluginsItem.typed<SettingsOwner, Widget>(),
          const SettingsOwner(),
        ))
          Padding(padding: const EdgeInsets.only(bottom: 24), child: child),
      ],
    ),
  );
}

void Function() registerCommonSettings(
  SlotRegistry slots, {
  required ConfigForms forms,
  required DshI18n Function() i18n,
  required HostRemotes remotes,
  ValueChanged<Uri>? openUrl,
  bool registerPluginsSection = true,
}) {
  final offs = <void Function()>[];
  final general = DshSlots.settingsGeneralItem.typed<SettingsOwner, Widget>();
  final plugin = DshSlots.pluginsItem.typed<SettingsOwner, Widget>();
  final developer = AcceptedToggle(forms.get('ui-settings'));
  final upload = AcceptedToggle(forms.get('session-log-deepseek'));
  if (registerPluginsSection) {
    offs.add(
      slots.register<SettingsOwner, Widget>(
        DshSlots.settingsSection.typed<SettingsOwner, Widget>(),
        (_) => PluginSettingsSection(slots: slots),
        id: 'plugins',
        order: 20,
        label: () => i18n().t('pluginManager', 'title'),
      ),
    );
  }
  for (final spec in [
    (
      ns: 'ui-settings',
      id: 'developer-tools',
      order: 15,
      c: developer,
      locale: 'settings',
    ),
    (
      ns: 'session-log-deepseek',
      id: 'session-log-upload',
      order: 90,
      c: upload,
      locale: 'settings.sessionLog',
    ),
  ]) {
    offs.add(
      forms.whileServed(
        [spec.ns],
        (_) => slots.register<SettingsOwner, Widget>(
          general,
          (_) => AcceptedToggleRow(
            controller: spec.c,
            title: i18n().t(
              spec.locale,
              spec.ns == 'ui-settings' ? 'developerTools.title' : 'title',
            ),
            description: i18n().t(
              spec.locale,
              spec.ns == 'ui-settings'
                  ? 'developerTools.description'
                  : 'description',
            ),
            failure: i18n().t(
              spec.locale,
              spec.ns == 'ui-settings' ? 'developerTools.error' : 'failed',
            ),
          ),
          id: spec.id,
          order: spec.order,
        ),
      ),
    );
  }
  offs.add(
    slots.register<Object?, Widget>(
      DshShellSlots.shellOverlay.typed<Object?, Widget>(),
      (_) => SettingsUploadNotice(controller: upload, i18n: i18n()),
      id: 'session-log-upload-toast',
    ),
  );
  for (final spec in [
    (
      ns: 'agent-loop',
      locale: 'settings.agentLoop',
      titleKey: 'title',
      fields: <NumberSetting>[
        (
          field: 'maxParallelToolCalls',
          labelKey: 'maxParallel',
          hintKey: 'maxParallelHint',
          minimum: null,
          invalid: null,
        ),
      ],
    ),
    for (final ns in ['bash-sandbox', 'pwsh-sandbox'])
      (
        ns: ns,
        locale: 'settings.shell',
        titleKey: 'title',
        fields: <NumberSetting>[
          (
            field: 'timeoutMs',
            labelKey: 'timeoutMs',
            hintKey: 'timeoutMsHint',
            minimum: null,
            invalid: null,
          ),
          (
            field: 'maxOutputBytes',
            labelKey: 'maxOutputBytes',
            hintKey: 'maxOutputBytesHint',
            minimum: null,
            invalid: null,
          ),
        ],
      ),
  ]) {
    offs.add(
      forms.whileServed(
        [spec.ns],
        (_) => slots.register<SettingsOwner, Widget>(
          plugin,
          (_) => NumberSettingsCard(
            form: forms.get(spec.ns),
            i18n: i18n(),
            namespace: spec.locale,
            title: spec.titleKey,
            fields: spec.fields,
          ),
          id: spec.ns,
          label: () => i18n().t(spec.locale, spec.titleKey),
          order: spec.ns == 'subagent'
              ? 10
              : spec.ns == 'agent-loop'
              ? 0
              : 15,
        ),
      ),
    );
  }
  final models = SubagentModelsController(
    forms.get('subagent-model-selection-settings'),
    remotes,
  );
  final web = WebSearchController(forms, remotes);
  offs.add(
    forms.whileServed(
      ['subagent', 'subagent-model-selection-settings'],
      (_) => slots.register<SettingsOwner, Widget>(
        plugin,
        (_) => SubagentSettingsCard(
          limits: forms.get('subagent'),
          models: models,
          i18n: i18n(),
        ),
        id: 'subagent',
        label: () => i18n().t('settings.subagent', 'title'),
        order: 10,
      ),
    ),
  );
  offs.add(
    forms.whileServed(
      ['web-search-deepseek'],
      (_) => slots.register<SettingsOwner, Widget>(
        plugin,
        (_) => WebSearchCard(controller: web, i18n: i18n(), openUrl: openUrl),
        id: 'web-search',
        label: () => i18n().t('settings.webSearch', 'title'),
        order: 20,
      ),
    ),
  );
  return () {
    for (final off in offs.reversed) {
      off();
    }
    unawaited(models.dispose());
    unawaited(web.dispose());
    unawaited(developer.dispose());
    unawaited(upload.dispose());
  };
}
