import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';

/// Synthetic settings over the actual generated Remote + ConfigForms path.
/// Credential writes retain only configured facts and never the entered value.
class SyntheticModelSettings {
  SyntheticModelSettings(this.host, {bool welcome = true}) {
    void add(
      String ns,
      Map<String, Object?> value, {
      Map<String, Object?>? schema,
    }) {
      views[ns] = nsView(
        ns,
        schema:
            schema ??
            objectSchema({
              for (final key in value.keys) key: {'type': 'any', 'meta': {}},
            }),
        value: value,
        base: _copy(value),
        user: {},
        revision: 1,
      );
    }

    add('llm-pi-ai', {
      'providers': {
        'openai': {
          'apiKeyEnv': 'OPENAI_API_KEY',
          'api': 'openai-completions',
          'models': [
            {'id': 'demo', 'name': 'Demo model', 'contextWindow': 256000},
          ],
        },
      },
    }, schema: providerSchema());
    add('ui-settings', {'enabled': false});
    add('ui-settings-general', {
      'welcomeNoticeVersion': welcome ? 'previous' : '2026-09-28.1',
    });
    add('session-log-deepseek', {'enabled': false});
    add('agent-loop', {'maxParallelToolCalls': 2});
    add('bash-sandbox', {'timeoutMs': 30000, 'maxOutputBytes': 65536});
    add('subagent', {'maxDepth': 1, 'maxActiveSubagents': 2});
    add('subagent-model-selection-settings', {
      'enabled': false,
      'allowedModels': [
        {'provider': 'retired', 'model': 'old'},
      ],
    });
    add('web', {
      'searchProvider': 'deepseek-official',
      'fetchProvider': 'http',
    });
    add('web-search-deepseek', {
      'apiKeyEnv': 'DEEPSEEK_API_KEY',
      'baseURL': 'https://api.example/anthropic/v1',
      'maxUses': 5,
    });
    add('web-deepseek-api', {
      'apiKeyEnv': 'DEEPSEEK_API_KEY',
      'baseURL': 'https://api.example/v1/tools',
      'count': 10,
    });
    host.handlers['settings/describe'] = (_) => {
      'writable': true,
      'hasDocument': false,
      'namespaces': [for (final v in views.values) _copy(v)],
    };
    host.handlers['settings/mutate'] = (args) {
      final ns = args['ns'] as String;
      final view = views[ns]!;
      final revision = args['expectedRevision'];
      if (revision != null && revision != view['revision']) {
        throw RemoteException(
          'settings/conflict',
          'Synthetic revision conflict',
        );
      }
      final user = _copy(view['user'] as Map<String, Object?>);
      for (final op in args['ops'] as List) {
        final path = (op['path'] as List).cast<String>();
        _apply(user, path, op['op'] == 'set', op['value']);
      }
      final value = _merge(view['base'], user);
      final error = SettingsSchema.rehydrate(view['schema']).validate(value);
      if (error != null) throw RemoteException('settings/invalid', error);
      views[ns] = {
        ...view,
        'revision': (view['revision'] as int) + 1,
        'user': user,
        'value': value,
      };
      scheduleMicrotask(() => host.emit('settings/document-updated'));
      return _copy(views[ns]!);
    };
    host.handlers['credentials/describe'] = (args) => {
      for (final ref in args['refs'] as List)
        ref: {
          'configured': configured.contains(ref),
          'writable': true,
          if (configured.contains(ref)) 'source': 'file',
        },
    };
    host.handlers['credentials/set'] = (args) {
      final ref = args['ref'] as String;
      if (ref == 'OPENAI_API_KEY' && refuseKeyOnce) {
        refuseKeyOnce = false;
        throw RemoteException(
          'gateway/refused',
          'Synthetic key save refused; retry.',
        );
      }
      configured.add(ref);
      scheduleMicrotask(
        () => host.emit('credentials/reference-updated', [ref]),
      );
      return null;
    };
    host.handlers['credentials/unset'] = (args) {
      configured.remove(args['ref']);
      scheduleMicrotask(
        () => host.emit('credentials/reference-updated', [args['ref']]),
      );
      return null;
    };
    host.handlers['llm/listProviders'] = (_) => [
      for (final id in _providers.keys)
        {'id': id, 'name': id == 'openai' ? 'OpenAI' : id},
    ];
    host.handlers['llm/listConfigurableProviders'] = (_) => [
      for (final id in {..._providers.keys, 'anthropic'})
        {
          'provider': id,
          'displayName': id == 'openai'
              ? 'OpenAI'
              : id == 'anthropic'
              ? 'Anthropic'
              : id,
          'settingsNs': 'llm-pi-ai',
          'settingsPath': ['providers', id],
          'declared': id != 'openai' && id != 'anthropic',
          'defaultBaseURL': 'https://api.example/v1',
        },
    ];
    host.handlers['llm/discoverModels'] = (_) => [
      {'id': 'demo', 'name': 'Demo model', 'contextWindow': 256000},
      {
        'id': 'vision-demo',
        'name': 'Vision demo',
        'contextWindow': 128000,
        'maxTokens': 32000,
        'inputModalities': ['text', 'image'],
      },
    ];
    host.handlers['session/modelCatalog'] = (_) => {
      'default': {'provider': 'openai', 'model': 'demo'},
      'routableProviders': ['openai'],
      'groups': [
        {
          'id': 'openai',
          'name': 'OpenAI',
          'models': [
            {'id': 'demo', 'name': 'Demo model'},
            {'id': 'vision-demo', 'name': 'Vision demo'},
          ],
        },
      ],
      'failures': [],
    };
  }
  final FakeHost host;
  final views = <String, Map<String, Object?>>{};
  final configured = <String>{};
  bool refuseKeyOnce = true;
  Map<String, Object?> get _providers =>
      ((_copy(
                views['llm-pi-ai']!['value'] as Map<String, Object?>,
              ))['providers']
              as Map)
          .cast<String, Object?>();
  Map<String, Object?> value(String ns) =>
      (views[ns]!['value'] as Map).cast<String, Object?>();
}

Map<String, Object?> _copy(Map<String, Object?> map) =>
    (jsonDecode(jsonEncode(map)) as Map).cast<String, Object?>();
Object? _merge(Object? base, Object? user) => base is Map && user is Map
    ? {
        ...base.cast<String, Object?>(),
        for (final entry in user.entries)
          entry.key as String: _merge(base[entry.key], entry.value),
      }
    : user;
void _apply(
  Map<String, Object?> root,
  List<String> path,
  bool set,
  Object? value,
) {
  if (path.isEmpty) {
    root.clear();
    if (value is Map) root.addAll(value.cast<String, Object?>());
    return;
  }
  var target = root;
  for (final segment in path.take(path.length - 1)) {
    if (target[segment] is! Map) target[segment] = <String, Object?>{};
    target = target[segment] as Map<String, Object?>;
  }
  if (set) {
    target[path.last] = value;
  } else {
    target.remove(path.last);
  }
}

Map<String, Object?> providerSchema() => {
  'uid': 9,
  'refs': {
    '1': {'type': 'string', 'meta': {}},
    '2': {'type': 'const', 'value': 'openai-completions', 'meta': {}},
    '3': {
      'type': 'union',
      'list': [2],
      'meta': {},
    },
    '4': {'type': 'any', 'meta': {}},
    '5': {
      'type': 'array',
      'inner': 4,
      'meta': {'default': []},
    },
    '6': {
      'type': 'object',
      'dict': {'api': 3, 'baseURL': 1, 'apiKeyEnv': 1, 'models': 5},
      'meta': {},
    },
    '8': {'type': 'dict', 'inner': 6, 'sKey': 1, 'meta': {}},
    '9': {
      'type': 'object',
      'dict': {'providers': 8},
      'meta': {},
    },
  },
};
