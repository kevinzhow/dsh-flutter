import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_llm.dart';
import 'package:dsh_client/generated_settings.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

void main() {
  test('pinned upstream key, catalog, capacity and mutation policy', () {
    final f = jsonDecode(
      File('test/fixtures/model_settings_behavior.json').readAsStringSync(),
    ) as Map;
    final e = f['expected'] as Map;
    expect([
      for (final v in f['keys'] as List) apiKeyFailure(v as String),
    ], e['keys']);
    expect([
      for (final v in f['refs'] as List) deriveKeyRef(v as String),
    ], e['refs']);
    expect([
      for (final v in f['capacities'] as List)
        switch (parseModelCapacity(v as String)) {
          final num n when n.isNaN => 'NaN',
          final x => x,
        },
    ], e['capacities']);
    expect([
      for (final v in f['formatted'] as List) formatModelCapacity(v as num),
    ], e['formatted']);
    Object? failure(ModelValidationFailure? v) =>
        v == null ? null : {'index': v.index, 'key': v.key};
    expect([
      for (final v in f['models'] as List) failure(validateProviderModels(v)),
    ], e['models']);
    expect([
      for (final v in f['models'] as List) failure(validateModelReasoning(v)),
    ], e['reasoning']);
    expect([
      for (final v in f['ops'] as List)
        [
          for (final op in providerPathOps(
            (v['base'] as List).cast<String>(),
            v['before'],
            Map<String, Object?>.from(v['after'] as Map),
          ))
            op.toJson(),
        ],
    ], e['ops']);
    expect([
      for (final v in f['joins'] as List)
        [
          for (final row in joinProviderDirectory(
            [for (final x in v['live'] as List) LlmProviderInfo.fromJson(x)],
            [
              for (final x in v['directory'] as List)
                LlmConfigurableProvider.fromJson(x),
            ],
          ))
            {...row.directory.toJson(), 'active': row.active},
        ],
    ], e['joins']);
  });

  late FakeHost host;
  late ConfigForms forms;
  late ModelsSettingsStore store;
  setUp(() {
    host = FakeHost();
    host.handlers['settings/describe'] = (_) => describeValue([providerView()]);
    host.handlers['llm/listProviders'] = (_) => [
      {'id': 'openai', 'name': 'OpenAI'},
    ];
    host.handlers['llm/listConfigurableProviders'] = (_) => [
      {
        'provider': 'openai',
        'displayName': 'OpenAI',
        'settingsNs': 'llm-pi-ai',
        'settingsPath': ['providers', 'openai'],
      },
    ];
    host.handlers['credentials/describe'] = (args) => {
      for (final ref in args['refs'] as List)
        ref: {'configured': true, 'writable': true, 'source': 'file'},
    };
    forms = ConfigForms(host.remotes);
    store = ModelsSettingsStore(host.remotes, forms.mirror);
  });
  tearDown(() async {
    await store.dispose();
    await forms.dispose();
    await host.close();
  });

  test('directory is lazy, enriches redacted credentials, and keeps rows on partial failure', () async {
    host.emit('llm/adapters-updated');
    await Future<void>.delayed(Duration.zero);
    expect(host.callsTo('llm/listProviders'), isEmpty);
    await store.load();
    final row = store.state.value.rows.single;
    expect(row.apiKeyEnv, 'OPENAI_API_KEY');
    expect(row.credential?.configured, isTrue);
    expect(row.usable, isTrue);
    host.handlers['credentials/describe'] = (_) =>
        throw RemoteException('gateway/refused', 'cannot describe');
    await store.load();
    expect(store.state.value.status, ModelsSettingsStatus.ready);
    expect(store.state.value.rows, hasLength(1));
    expect(store.state.value.credentialError, 'cannot describe');
    expect(store.state.value.rows.single.credentialChecks, isNull);
    host.handlers['llm/listProviders'] = (_) =>
        throw RemoteException('gateway/refused', 'directory down');
    await store.load();
    expect(store.state.value.status, ModelsSettingsStatus.error);
    expect(store.state.value.rows, hasLength(1));
  });

  test(
    'credential descriptions batch at 64 and stale whole loads follow latest',
    () async {
      host.handlers['llm/listConfigurableProviders'] = (_) => [
        for (var i = 0; i < 130; i++)
          {
            'provider': 'route-$i',
            'displayName': 'Route $i',
            'settingsNs': 'llm-pi-ai',
            'settingsPath': ['providers', 'route-$i'],
          },
      ];
      final old = Completer<Object?>();
      var calls = 0;
      host.handlers['llm/listProviders'] = (_) => ++calls == 1
          ? old.future
          : [
              {'id': 'new', 'name': 'New'},
            ];
      var oldDone = false;
      final first = store.load().then((_) => oldDone = true);
      final second = store.load();
      await second;
      expect(oldDone, isTrue);
      expect(store.state.value.rows.last.entry.directory.provider, 'new');
      expect(
        host
            .callsTo('credentials/describe')
            .map((c) => (c.args['refs'] as List).length),
        [64, 64, 3],
      );
      old.complete([
        {'id': 'old', 'name': 'Old'},
      ]);
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(store.state.value.rows.last.entry.directory.provider, 'new');
    },
  );

  test('profile saves minimal fields and credential retry never repeats committed profile', () async {
    await forms.mirror.ensure();
    final inputKey = ['synthetic', '-', 'value'].join();
    final draft = ProviderSettingsDraft(
      remotes: host.remotes,
      mirror: forms.mirror,
      namespace: SettingsNamespaceView.fromJson(providerView()),
      provider: 'openai',
      path: ['providers', 'openai'],
    );
    draft.setField('baseURL', 'https://gateway.example/v1');
    draft.keyDraft = ' $inputKey ';
    host.handlers['settings/mutate'] = (args) {
      expect(args['expectedRevision'], 7);
      expect(args['ops'], [
        {
          'op': 'set',
          'path': ['providers', 'openai', 'baseURL'],
          'value': 'https://gateway.example/v1',
        },
      ]);
      return providerView(
        revision: 8,
        user: {
          'providers': {
            'openai': {...profile, 'baseURL': 'https://gateway.example/v1'},
          },
        },
      );
    };
    var attempts = 0;
    host.handlers['credentials/set'] = (args) {
      expect(args, {'ref': 'OPENAI_API_KEY', 'value': inputKey});
      if (++attempts == 1) {
        throw RemoteException('gateway/refused', 'could not save $inputKey');
      }
      return null;
    };
    expect(await draft.save(), isFalse);
    expect(draft.error, isNot(contains(inputKey)));
    expect(draft.revision, 8);
    expect(await draft.save(), isTrue);
    expect(host.callsTo('settings/mutate'), hasLength(1));
    expect(host.callsTo('credentials/set'), hasLength(2));
    expect(draft.keyDraft, isEmpty);
    draft.dispose();
  });

  test('conflict never writes credentials; disposed partial save never starts second write', () async {
    await forms.mirror.ensure();
    ProviderSettingsDraft open() =>
        ProviderSettingsDraft(
            remotes: host.remotes,
            mirror: forms.mirror,
            namespace: SettingsNamespaceView.fromJson(providerView()),
            provider: 'openai',
            path: ['providers', 'openai'],
          )
          ..setField('baseURL', 'https://new.example')
          ..keyDraft = 'synthetic';
    final draft = open();
    host.handlers['settings/mutate'] = (_) =>
        throw RemoteException('settings/conflict', 'newer revision');
    expect(await draft.save(), isFalse);
    expect(draft.error, 'conflict');
    expect(host.callsTo('credentials/set'), isEmpty);
    draft.dispose();
    final response = Completer<Object?>();
    host.handlers['settings/mutate'] = (_) => response.future;
    final abandoned = open();
    final saving = abandoned.save();
    abandoned.dispose();
    response.complete(providerView(revision: 8));
    expect(await saving, isFalse);
    expect(host.callsTo('credentials/set'), isEmpty);
  });

  test('blank native profile materializes, discovery stays draft-only and drops late response', () async {
    await forms.mirror.ensure();
    final draft = ProviderSettingsDraft(
      remotes: host.remotes,
      mirror: forms.mirror,
      namespace: SettingsNamespaceView.fromJson(providerView()),
      provider: 'native',
      path: ['providers', 'native'],
    );
    host.handlers['settings/mutate'] = (args) {
      expect(args['ops'], [
        {
          'op': 'set',
          'path': ['providers', 'native'],
          'value': {},
        },
      ]);
      return providerView(
        revision: 8,
        user: {
          'providers': {'native': {}},
        },
      );
    };
    expect(await draft.save(), isTrue);
    expect(host.callsTo('credentials/set'), isEmpty);
    draft.keyDraft = 'synthetic';
    draft.setField('baseURL', 'https://probe.example');
    final response = Completer<Object?>();
    host.handlers['llm/discoverModels'] = (args) {
      expect(args, {
        'settingsNs': 'llm-pi-ai',
        'request': {
          'provider': 'native',
          'baseURL': 'https://probe.example',
          'apiKey': 'synthetic',
        },
      });
      return response.future;
    };
    final discovery = draft.discover();
    draft.setField('baseURL', 'https://edited.example');
    response.complete([
      {'id': 'late'},
    ]);
    expect(await discovery, isNull);
    expect(host.callsTo('credentials/set'), isEmpty);
    draft.dispose();
  });
}

const profile = {
  'apiKeyEnv': 'OPENAI_API_KEY',
  'opaque': {'preserve': true},
};
Map<String, Object?> providerView({
  int revision = 7,
  Map<String, Object?>? user,
}) => nsView(
  'llm-pi-ai',
  schema: objectSchema({
    'providers': {'type': 'any', 'meta': {}},
  }),
  value: {
    'providers': {'openai': profile},
  },
  base: {'providers': {}},
  user:
      user ??
      {
        'providers': {'openai': profile},
      },
  revision: revision,
);
