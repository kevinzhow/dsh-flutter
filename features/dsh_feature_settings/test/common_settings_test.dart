import 'dart:async';

import 'support/script_form.dart';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_settings.dart';
import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeHost host;
  late ConfigForms forms;
  final namespaces = <Map<String, Object?>>[];
  setUp(() {
    host = FakeHost();
    namespaces.clear();
    host.handlers['settings/describe'] = (_) => describeValue(namespaces);
  });
  tearDown(() async {
    await forms.dispose();
    await host.close();
  });
  Future<void> setup(List<Map<String, Object?>> views) async {
    namespaces.addAll(views);
    forms = ConfigForms(host.remotes);
    await forms.mirror.ensure();
    host.handlers['settings/mutate'] = (args) {
      final ns = args['ns'] as String;
      final previous = forms.mirror.namespace(ns)!;
      final user = Map<String, Object?>.from(previous.user as Map);
      for (final op in args['ops'] as List) {
        final field = (op['path'] as List).single as String;
        if (op['op'] == 'set') {
          user[field] = op['value'];
        } else {
          user.remove(field);
        }
      }
      return nsView(
        ns,
        schema: (previous.schema as Map).cast<String, Object?>(),
        value: {...(previous.base as Map).cast<String, Object?>(), ...user},
        base: (previous.base as Map).cast<String, Object?>(),
        user: user,
        revision: previous.revision + 1,
      );
    };
  }

  testWidgets(
    'numeric staging keeps edits on refusal; reset is revision-fenced unset',
    (t) async {
      addTearDown(() async {
        await t.pumpWidget(const SizedBox.shrink());
      });
      await t.runAsync(() => setup([numericView()]));
      final mutations = <Map<String, Object?>>[];
      final form = ScriptForm('agent-loop', {
        'maxParallelToolCalls': 4,
      }, mutations)..refuse = true;
      await t.pumpWidget(
        dshTestApp(
          NumberSettingsCard(
            form: form,
            i18n: const DshI18n(DshLocale.en),
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
          ),
        ),
      );
      await t.pump();
      await t.enterText(
        find.byKey(DshSettingsValueField.inputKey('maxParallelToolCalls')),
        '6',
      );
      expect(mutations, isEmpty);
      host.handlers['settings/mutate'] = (_) =>
          throw RemoteException('settings/conflict', 'changed elsewhere');
      await t.pump();
      await t.tap(find.byKey(DshSettingsForm.saveKey));
      await t.pumpAndSettle();
      expect(find.byKey(DshSettingsForm.failedKey), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(mutations.single['revision'], 3);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'one Subagent save blocks both namespaces while model authorization is invalid',
    (t) async {
      await t.runAsync(() => setup([]));
      host.handlers['session/modelCatalog'] = (_) => {
        'default': {'provider': 'live', 'model': 'new'},
        'routableProviders': ['live'],
        'groups': [
          {
            'id': 'live',
            'name': 'Live',
            'models': [
              {'id': 'new', 'name': 'New'},
            ],
          },
        ],
        'failures': [],
      };
      final limits = FakeConfigForm(
        const ConfigFormSnapshot(
          status: ConfigFormStatus.ready,
          writable: true,
          value: {'maxDepth': 1, 'maxActiveSubagents': 2},
          base: {'maxDepth': 1, 'maxActiveSubagents': 2},
          user: {},
          revision: 3,
        ),
      );
      final modelForm = FakeConfigForm(
        const ConfigFormSnapshot(
          status: ConfigFormStatus.ready,
          writable: true,
          value: {'enabled': false, 'allowedModels': []},
          base: {'enabled': false, 'allowedModels': []},
          user: {},
          revision: 4,
        ),
      );
      final models = SubagentModelsController(modelForm, host.remotes);
      await t.pumpWidget(
        dshTestApp(
          SingleChildScrollView(
            child: SubagentSettingsCard(
              limits: limits,
              models: models,
              i18n: const DshI18n(DshLocale.en),
            ),
          ),
        ),
      );
      await t.enterText(
        find.byKey(DshSettingsValueField.inputKey('maxDepth')),
        '2',
      );
      models.toggleEnabled(true);
      await t.pumpAndSettle();
      expect(find.byKey(DshSettingsForm.saveKey), findsOneWidget);
      final saveButton = find.descendant(
        of: find.byKey(DshSettingsForm.saveKey),
        matching: find.byType(DshButton),
      );
      expect(t.widget<DshButton>(saveButton).onPressed, isNull);
      expect(limits.writes, isEmpty);
      expect(modelForm.writes, isEmpty);
      models.toggleModel(subagentModelKey((provider: 'live', model: 'new')));
      await t.pumpAndSettle();
      modelForm.answer = false;
      await t.ensureVisible(saveButton);
      await t.tap(saveButton);
      await t.pumpAndSettle();
      expect(limits.snapshot.value?['maxDepth'], 2);
      expect(modelForm.snapshot.value?['enabled'], false);
      expect(find.byKey(DshSettingsForm.failedKey), findsOneWidget);
      expect(limits.writes.single.expectedRevision, 3);
      expect(modelForm.writes.single.expectedRevision, 4);
      await t.pumpWidget(const SizedBox.shrink());
      var disposed = false;
      unawaited(models.dispose().then((_) => disposed = true));
      for (var i = 0; i < 6 && !disposed; i++) {
        await t.runAsync(() => Future<void>.delayed(Duration.zero));
        await t.pump();
      }
      expect(disposed, true);
    },
  );
  test('exact subagent limit fields reject decimals, negative zero and unsafe integers', () {
    forms = ConfigForms(host.remotes);
    expect(settingsLimitField('maxDepth', 0).parse('-0'), isNull);
    expect(
      settingsLimitField('maxDepth', 0).parse('0'),
      isA<SettingsFieldSet>(),
    );
    expect(settingsLimitField('maxDepth', 0).parse('1.2'), isNull);
    expect(settingsLimitField('maxDepth', 0).parse('9007199254740992'), isNull);
    expect(settingsLimitField('maxActiveSubagents', 1).parse('0'), isNull);
    expect(
      settingsLimitField('maxActiveSubagents', 1).parse(''),
      isA<SettingsFieldClear>(),
    );
  });
  test('accepted switch stays unchanged while busy, serializes and reports refused writes', () async {
    await setup([enabledView()]);
    final toggle = AcceptedToggle(forms.get('ui-settings'));
    final pending = Completer<Object?>();
    host.handlers['settings/mutate'] = (_) => pending.future;
    final first = toggle.set(true);
    await Future<void>.delayed(Duration.zero);
    await toggle.set(false);
    expect(toggle.form.snapshot.value?['enabled'], false);
    expect(host.callsTo('settings/mutate'), hasLength(1));
    pending.complete(enabledView(enabled: true, revision: 4));
    await first;
    expect(toggle.form.snapshot.value?['enabled'], true);
    expect(toggle.state.value.$2, 'saved');
    host.handlers['settings/mutate'] = (_) =>
        throw RemoteException('gateway/refused', 'read-only');
    await toggle.set(false);
    expect(
      toggle.form.snapshot.value?['enabled'],
      false,
    ); // recovery read is authoritative
    expect(toggle.state.value.$2, 'failed');
    await toggle.dispose();
  });
  testWidgets(
    'actual accepted upload is success; refused upload has no icon and stale completion is fenced',
    (t) async {
      await t.runAsync(() => setup([enabledView()]));
      final toggle = AcceptedToggle(forms.get('ui-settings'));
      addTearDown(toggle.dispose);
      await t.runAsync(() => toggle.set(true));
      await t.pumpWidget(
        dshTestApp(
          SettingsUploadNotice(
            controller: toggle,
            i18n: const DshI18n(DshLocale.en),
          ),
        ),
      );
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      final saved = t.widget<DshToast>(find.byType(DshToast));
      expect(saved.tone, DshToastTone.success);
      expect(
        t.widget<DshIcon>(find.byType(DshIcon)).icon,
        DshIcons.checkCircle,
      );
      expect(toggle.form.snapshot.value?['enabled'], true);
      host.handlers['settings/mutate'] = (_) =>
          throw RemoteException('gateway/refused', 'read-only');
      await t.runAsync(() => toggle.set(false));
      await t.pump();
      await t.pump();
      await t.pump();
      final failed = t.widget<DshToast>(find.byType(DshToast));
      expect(failed.tone, isNull);
      expect(failed.icon, isNull);
      expect(find.byType(DshIcon), findsNothing);
      saved.onDone();
      await t.pump();
      expect(toggle.state.value.$2, 'failed');
      expect(find.byType(DshToast), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
  test('web selection saves section first, blocks invalid/failure switch and retains staged keys', () async {
    await setup(webViews());
    host.handlers['credentials/describe'] = (_) => {
      'DEEPSEEK_API_KEY': {'configured': false, 'writable': true},
    };
    host.handlers['credentials/set'] = (_) => null;
    final web = WebSearchController(forms, host.remotes);
    await Future<void>.delayed(Duration.zero);
    web.selectApi(true);
    web.edit('count', '51');
    expect(web.shell.invalid, true);
    web.selectApi(false);
    expect(web.useSearchApi, true);
    web.edit('count', '12');
    web.edit('baseURL', 'https://api.example/v1/tools');
    await web.save();
    final mutations = host.callsTo('settings/mutate');
    expect(mutations.map((c) => c.args['ns']), ['web-deepseek-api', 'web']);
    expect(
      forms.get('web').snapshot.value?['searchProvider'],
      'deepseek-search-api',
    );
    expect(
      forms.get('web').snapshot.value?['fetchProvider'],
      'deepseek-fetch-api',
    );
    expect(web.shell.dirty, false);
    web.selectApi(false);
    web.edit('maxUses', '3');
    host.handlers['settings/mutate'] = (_) =>
        throw RemoteException('settings/conflict', 'changed');
    await web.save();
    expect(web.shell.failed, true);
    web.selectApi(true);
    expect(web.useSearchApi, false);
    expect(host.callsTo('credentials/set'), isEmpty);
    await web.dispose();
  });
  test('web credential old reference responses never claim new reference configured', () async {
    await setup(webViews());
    final old = Completer<Object?>();
    var reads = 0;
    host.handlers['credentials/describe'] = (args) => ++reads == 1
        ? old.future
        : {
            'ALT_API_KEY': {'configured': false, 'writable': false},
          };
    final web = WebSearchController(forms, host.remotes);
    // Replace with a real wire view; old DEEPSEEK_API_KEY reply must be ignored.
    forms.mirror.acceptView(
      parseView('web-search-deepseek', {
        'apiKeyEnv': 'ALT_API_KEY',
        'baseURL': '',
        'maxUses': 5,
      }),
    );
    await Future<void>.delayed(Duration.zero);
    old.complete({
      'DEEPSEEK_API_KEY': {'configured': true, 'writable': true},
    });
    await Future<void>.delayed(Duration.zero);
    expect(web.credential?.configured, false);
    expect(web.credential?.writable, false);
    await web.dispose();
  });
  test('allowlist retains unavailable choices, blocks empty/conflicted drafts and resets on reconnect', () async {
    await setup([allowlistView()]);
    host.handlers['session/modelCatalog'] = (_) => {
      'default': {'provider': 'live', 'model': 'new'},
      'routableProviders': ['live'],
      'groups': [
        {
          'id': 'live',
          'name': 'Live',
          'models': [
            {'id': 'new', 'name': 'New'},
          ],
        },
      ],
      'failures': [],
    };
    final c = SubagentModelsController(
      forms.get('subagent-model-selection-settings'),
      host.remotes,
    );
    c.toggleEnabled(true);
    await Future<void>.delayed(Duration.zero);
    expect(c.candidates.where((r) => !r.available).single.route, (
      provider: 'retired',
      model: 'old',
    ));
    c.toggleModel(subagentModelKey((provider: 'retired', model: 'old')));
    expect(c.shell.invalid, true);
    await c.save();
    expect(host.callsTo('settings/mutate'), isEmpty);
    c.toggleModel(subagentModelKey((provider: 'live', model: 'new')));
    await c.save();
    expect(c.dirty, false);
    expect(
      forms
          .get('subagent-model-selection-settings')
          .snapshot
          .value?['allowedModels'],
      [
        {'provider': 'live', 'model': 'new'},
      ],
    );
    c.toggleEnabled(false);
    forms.mirror.acceptView(
      parseView('subagent-model-selection-settings', {
        'enabled': true,
        'allowedModels': [
          {'provider': 'retired', 'model': 'old'},
        ],
      }, revision: 10),
    );
    expect(c.conflicted, true);
    await c.save();
    expect(host.callsTo('settings/mutate'), hasLength(1));
    host.gens.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(c.conflicted, false);
    await c.dispose();
  });
}

Map<String, Object?> numericView() => nsView(
  'agent-loop',
  schema: objectSchema({'maxParallelToolCalls': numberNode(defaultValue: 4)}),
  value: {'maxParallelToolCalls': 4},
  base: {'maxParallelToolCalls': 2},
  user: {'maxParallelToolCalls': 4},
  revision: 3,
);
Map<String, Object?> enabledView({bool enabled = false, int revision = 3}) =>
    nsView(
      'ui-settings',
      schema: objectSchema({
        'enabled': {
          'type': 'boolean',
          'meta': {'default': false},
        },
      }),
      value: {'enabled': enabled},
      base: {'enabled': false},
      user: enabled ? {'enabled': true} : {},
      revision: revision,
    );
Map<String, Object?> allowlistView() =>
    simpleView('subagent-model-selection-settings', {
      'enabled': false,
      'allowedModels': [
        {'provider': 'retired', 'model': 'old'},
      ],
    });
Map<String, Object?> simpleView(
  String ns,
  Map<String, Object?> value, {
  int revision = 3,
}) => nsView(
  ns,
  schema: objectSchema({
    for (final key in value.keys) key: {'type': 'any', 'meta': {}},
  }),
  value: value,
  base: value,
  user: {},
  revision: revision,
);
List<Map<String, Object?>> webViews() => [
  simpleView('web', {
    'searchProvider': 'deepseek-official',
    'fetchProvider': 'http',
  }),
  simpleView('web-search-deepseek', {
    'apiKeyEnv': 'DEEPSEEK_API_KEY',
    'baseURL': '',
    'maxUses': 5,
  }),
  simpleView('web-deepseek-api', {
    'apiKeyEnv': 'DEEPSEEK_API_KEY',
    'baseURL': '',
    'count': 10,
  }),
];

SettingsNamespaceView parseView(
  String ns,
  Map<String, Object?> value, {
  int revision = 4,
}) => SettingsNamespaceView.fromJson(simpleView(ns, value, revision: revision));
