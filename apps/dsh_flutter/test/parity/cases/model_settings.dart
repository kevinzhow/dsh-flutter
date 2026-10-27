import 'dart:async';

import 'package:dsh_client/generated_settings.dart';
import 'package:dsh_feature_model_settings/src/provider_editor.dart';
import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import '../helpers/models_settings_fixture.dart';

final Map<String, ParityCase> modelSettingsCases = {
  for (final f in [
    'provider',
    'custom',
    'agent',
    'shell',
    'limits',
    'web',
    'upload',
  ])
    'model-settings.$f': ParityCase(
      widgets: ['dsh_feature_model_settings:$f', 'dsh_feature_settings:$f'],
      build: (ctx) => _Surface(
        family: f,
        name: ctx.props['name'] as String,
        width: (ctx.props['width'] as num).toDouble(),
        i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
      ),
    ),
};

class _Surface extends StatefulWidget {
  const _Surface({
    required this.family,
    required this.name,
    required this.width,
    required this.i18n,
  });
  final String family, name;
  final double width;
  final DshI18n i18n;
  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  final host = FakeHost();
  late final SyntheticModelSettings fixture;
  late final ConfigForms forms;
  late final ModelsSettingsStore store;
  late final SubagentModelsController models;
  late final WebSearchController web;
  late final AcceptedToggle upload;
  FakeConfigForm form(Map<String, Object?> value, {bool available = true}) =>
      FakeConfigForm(
        ConfigFormSnapshot(
          status: available
              ? ConfigFormStatus.ready
              : ConfigFormStatus.unavailable,
          value: value,
          base: Map.of(value),
          user: widget.name == 'overridden' ? {'timeoutMs': 30000} : {},
          revision: 1,
          writable: widget.name != 'readonly',
        ),
      );
  @override
  void initState() {
    super.initState();
    fixture = SyntheticModelSettings(host, welcome: false);
    forms = ConfigForms(host.remotes);
    store = ModelsSettingsStore(host.remotes, forms.mirror);
    store.state.set(
      ModelsSettingsSnapshot(
        status: ModelsSettingsStatus.ready,
        writable: true,
        namespaces: {
          for (final e in fixture.views.entries)
            e.key: SettingsNamespaceView.fromJson(e.value),
        },
      ),
    );
    models = SubagentModelsController(form({}, available: false), host.remotes);
    web = WebSearchController.scopes(
      web: form({
        'searchProvider': widget.name == 'api'
            ? 'deepseek-search-api'
            : 'deepseek-official',
        'fetchProvider': widget.name == 'api' ? 'deepseek-fetch-api' : 'http',
      }),
      messages: form(fixture.value('web-search-deepseek')),
      api: form(fixture.value('web-deepseek-api')),
      remotes: host.remotes,
    );
    upload = AcceptedToggle(form({'enabled': widget.name == 'on'}));
  }

  @override
  void dispose() {
    unawaited(store.dispose());
    unawaited(models.dispose());
    unawaited(web.dispose());
    unawaited(upload.dispose());
    unawaited(forms.dispose().then((_) => host.close()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.family, i18n = widget.i18n;
    late Widget body;
    switch (f) {
      case 'provider':
      case 'custom':
        body = ProviderEditor(
          store: store,
          namespace: SettingsNamespaceView.fromJson(fixture.views['llm-pi-ai']),
          provider: f == 'custom' ? '' : 'openai',
          displayName: f == 'custom'
              ? i18n.t('settings.models', 'addCustom')
              : 'OpenAI',
          path: const ['providers', 'openai'],
          creating: f == 'custom',
          declared: f == 'custom',
          i18n: i18n,
          onClose: (_) {},
        );
      case 'agent':
        body = NumberSettingsCard(
          form: form({'maxParallelToolCalls': 2}),
          i18n: i18n,
          namespace: 'settings.agentLoop',
          title: 'title',
          fields: const [
            (
              field: 'maxParallelToolCalls',
              labelKey: 'maxParallel',
              hintKey: 'maxParallelHint',
              minimum: null,
              invalid: null,
            ),
          ],
        );
      case 'shell':
        body = NumberSettingsCard(
          form: form({'timeoutMs': 30000, 'maxOutputBytes': 65536}),
          i18n: i18n,
          namespace: 'settings.shell',
          title: 'title',
          fields: const [
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
        );
      case 'limits':
        body = SubagentSettingsCard(
          limits: form({'maxDepth': 1, 'maxActiveSubagents': 2}),
          models: models,
          i18n: i18n,
        );
      case 'web':
        body = WebSearchCard(controller: web, i18n: i18n, openUrl: (_) {});
      case 'upload':
        body = AcceptedToggleRow(
          controller: upload,
          title: i18n.t('settings.sessionLog', 'title'),
          description: i18n.t('settings.sessionLog', 'description'),
          failure: i18n.t('settings.sessionLog', 'failed'),
        );
    }
    return Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: const ValueKey('model-settings-surface'),
        child: SizedBox(
          width: widget.width,
          child: DefaultTextStyle(
            style: context.dsh
                .textStyle('--dsw-font-s-14')
                .copyWith(color: context.dsh.labelPrimary),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [body],
            ),
          ),
        ),
      ),
    );
  }
}
