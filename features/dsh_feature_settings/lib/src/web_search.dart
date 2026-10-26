import 'dart:async';

import 'package:dsh_client/generated_credentials.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import 'form_scope.dart';

class WebSearchController {
  WebSearchController(ConfigForms forms, HostRemotes remotes)
    : this.scopes(
        web: forms.get('web'),
        messages: forms.get('web-search-deepseek'),
        api: forms.get('web-deepseek-api'),
        remotes: remotes,
      );
  WebSearchController.scopes({
    required ConfigForm web,
    required ConfigForm messages,
    required ConfigForm api,
    required this.remotes,
  }) : _web = web,
       _messages = messages,
       _api = api {
    selection = SettingsFormModel(
      ConfigFormScope(_web),
      [settingsTextField('searchProvider'), settingsTextField('fetchProvider')],
      [SettingsSecretSpec(field: 'apiKey', write: (text) => _writeKey(text))],
    );
    this.messages = SettingsFormModel(ConfigFormScope(_messages), [
      settingsTextField('baseURL'),
      settingsNumberField('maxUses'),
    ]);
    final number = settingsNumberField('count');
    this.api = SettingsFormModel(ConfigFormScope(_api), [
      settingsTextField('baseURL'),
      SettingsFieldSpec(
        field: 'count',
        format: number.format,
        parse: (text) {
          final write = number.parse(text);
          if (write is! SettingsFieldSet) return write;
          final n = write.value;
          return n is num && n >= 1 && n <= 50 && n == n.truncateToDouble()
              ? write
              : null;
        },
      ),
    ]);
    for (final model in [selection, this.messages, this.api]) {
      _offs.add(
        model.bind(model.shell).subscribe(() {
          _publish();
          if (_ref != _credentialRef) unawaited(readCredential());
        }),
      );
    }
    for (final form in [_web, _messages, _api]) {
      _offs.add(form.subscribe(() => unawaited(readCredential())));
    }
    _subs.add(
      remotes
          .emitted('credentials/reference-updated')
          .listen((_) => unawaited(readCredential())),
    );
    _subs.add(
      remotes.generations.listen((_) {
        _generation++;
        discard();
        credential = null;
        _credentialRef = '';
        unawaited(readCredential());
      }),
    );
    unawaited(readCredential());
  }
  final ConfigForm _web;
  final ConfigForm _messages;
  final ConfigForm _api;
  final HostRemotes remotes;
  late final SettingsFormModel selection;
  late final SettingsFormModel messages;
  late final SettingsFormModel api;
  final changed = Observable(0);
  final List<void Function()> _offs = [];
  final List<StreamSubscription<Object?>> _subs = [];
  CredentialInfo? credential;
  String _credentialRef = '';
  bool _disposed = false;
  int _generation = 0;
  int _read = 0;
  bool get switchAvailable =>
      selection.shell().available && api.shell().available;
  bool get useSearchApi =>
      switchAvailable &&
      selection.field('searchProvider').text == 'deepseek-search-api';
  String get _ref {
    final value =
        (useSearchApi ? _api : _messages).snapshot.value?['apiKeyEnv'];
    return value is String && value.isNotEmpty ? value : 'DEEPSEEK_API_KEY';
  }

  SettingsFormShell get shell {
    final served = [
      messages.shell(),
      selection.shell(),
      api.shell(),
    ].where((s) => s.available);
    return SettingsFormShell(
      available: messages.shell().available,
      writable: served.every((s) => s.writable),
      dirty: served.any((s) => s.dirty),
      invalid: served.any((s) => s.invalid),
      saving: served.any((s) => s.saving),
      failed: served.any((s) => s.failed),
    );
  }

  SettingsFormModel modelOf(String field) => switch (field) {
    'apiKey' => selection,
    'maxUses' => messages,
    'count' => api,
    _ => useSearchApi ? api : messages,
  };
  SettingsFieldState field(String key) => modelOf(key).field(key);
  void edit(String key, String text) => modelOf(key).actions().edit(key, text);
  void reset(String key) => modelOf(key).actions().resetField(key);
  void selectApi(bool enabled) {
    if (_disposed ||
        shell.saving ||
        shell.invalid ||
        shell.failed ||
        !shell.writable) {
      return;
    }
    final base = _web.snapshot.base;
    for (final field in ['searchProvider', 'fetchProvider']) {
      final target = field == 'searchProvider'
          ? (enabled ? 'deepseek-search-api' : 'deepseek-official')
          : (enabled ? 'deepseek-fetch-api' : 'http');
      if (base is Map && base[field] == target) {
        selection.actions().resetField(field);
      } else {
        selection.actions().edit(field, target);
      }
    }
  }

  Future<void> save() async {
    if (_disposed || !shell.available || shell.invalid || shell.saving) return;
    final generation = _generation;
    for (final model in [messages, api, selection]) {
      if (_disposed || generation != _generation) return;
      if (!model.shell().available || !model.shell().dirty) continue;
      await model.save();
      if (model.shell().failed) return;
    }
  }

  Future<void> readCredential() async {
    final ref = _ref;
    if (ref != _credentialRef) {
      _credentialRef = ref;
      credential = null;
      _publish();
    }
    final read = ++_read;
    final generation = _generation;
    try {
      final result = await remotes.credentials.describe([ref]);
      if (_disposed ||
          generation != _generation ||
          read != _read ||
          ref != _ref) {
        return;
      }
      credential = result[ref];
      _publish();
    } on Object {
      /* keep last accepted facts for the same reference */
    }
  }

  Future<bool> _writeKey(String value) async {
    if (_disposed) return false;
    final generation = _generation;
    final ref = _ref;
    await remotes.credentials.set(ref, value);
    if (_disposed || generation != _generation || ref != _ref) return false;
    await readCredential();
    return credential?.configured == true;
  }

  void discard() {
    for (final m in [selection, messages, api]) {
      m.actions().discard();
    }
  }

  void _publish() {
    if (!_disposed) changed.set(changed.value + 1);
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    _read++;
    for (final off in _offs) {
      off();
    }
    for (final s in _subs) {
      await s.cancel();
    }
    for (final m in [selection, messages, api]) {
      m.dispose();
    }
    await changed.dispose();
  }
}

class WebSearchCard extends StatefulWidget {
  const WebSearchCard({
    super.key,
    required this.controller,
    required this.i18n,
    this.openUrl,
  });
  final WebSearchController controller;
  final DshI18n i18n;
  final ValueChanged<Uri>? openUrl;
  @override
  State<WebSearchCard> createState() => _WebSearchCardState();
}

class _WebSearchCardState extends State<WebSearchCard> {
  StreamSubscription<Object?>? sub;
  final keyText = TextEditingController();
  String t(String key) => widget.i18n.t('settings.webSearch', key);
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
    keyText.clear();
    keyText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final shell = c.shell;
    final field = c.useSearchApi ? 'count' : 'maxUses';
    if (keyText.text != c.field('apiKey').text) {
      keyText.text = c.field('apiKey').text;
    }
    Widget valueField(String key, String label, String hint, String invalid) {
      final state = c.field(key);
      return DshSettingsValueField(
        id: 'web-search-$key',
        label: t(label),
        text: state.text,
        overridden: state.overridden,
        invalid: state.invalid,
        overriddenLabel: t('overridden'),
        resetLabel: t('reset'),
        invalidLabel: t(invalid),
        hint: t(hint),
        numeric: key != 'baseURL',
        disabled: !shell.writable || shell.saving,
        onEdit: (value) => c.edit(key, value),
        onReset: () => c.reset(key),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('title'), style: context.dsh.textStyle('--dsw-font-base-16')),
        DshSettingsForm(
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
          children: [
            if (c.switchAvailable)
              DshSettingsRow(
                title: t('useSearchApi'),
                description: t('useSearchApiHint'),
                control: DshSwitch(
                  key: const ValueKey('web-search-api-switch'),
                  value: c.useSearchApi,
                  label: t('useSearchApi'),
                  onChanged:
                      !shell.writable ||
                          shell.saving ||
                          shell.invalid ||
                          shell.failed
                      ? null
                      : c.selectApi,
                ),
              ),
            if (c.switchAvailable && widget.openUrl != null)
              Align(
                alignment: Alignment.centerLeft,
                child: DshButton(
                  variant: DshButtonVariant.ghost,
                  size: DshButtonSize.sm,
                  onPressed: () =>
                      widget.openUrl!(Uri.parse(t('searchGuideUrl'))),
                  child: Text(t('searchGuide')),
                ),
              ),
            Text(t('apiKey'), style: context.dsh.textStyle('--dsw-font-s-14')),
            Material(
              type: MaterialType.transparency,
              child: DshTextField(
                key: const ValueKey('web-search-api-key'),
                controller: keyText,
                obscure: true,
                enabled: c.credential?.writable != false && !shell.saving,
                placeholder: t('apiKeyHint'),
                onChanged: (v) => c.edit('apiKey', v),
              ),
            ),
            Text(
              t(c.credential?.configured == true ? 'apiKeySet' : 'apiKeyUnset'),
              style: context.dsh.textStyle('--dsw-font-xxs-12'),
            ),
            valueField(
              'baseURL',
              c.useSearchApi ? 'searchApiBaseUrl' : 'baseUrl',
              c.useSearchApi ? 'searchApiBaseUrlHint' : 'baseUrlHint',
              'invalidNumber',
            ),
            valueField(
              field,
              field,
              c.useSearchApi ? 'countHint' : 'maxUsesHint',
              c.useSearchApi ? 'invalidCount' : 'invalidNumber',
            ),
          ],
        ),
      ],
    );
  }
}
