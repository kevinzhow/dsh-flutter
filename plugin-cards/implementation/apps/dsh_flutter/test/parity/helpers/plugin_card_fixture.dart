import 'dart:convert';

import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';

import 'plugins_preview_fixture.dart';

/// Single synthetic data source shared by Dart, the plan builder and the actual
/// published-bundle browser host. No native asset/file reads are needed.
const pluginCardScenarioJson = r'''
{
  "schema": "dsh-plugin-card-scenarios/1",
  "basePackage": {
    "name": "@synthetic/card-default", "official": false,
    "availability": "profile", "installed": true, "enabled": true,
    "optional": false, "removable": true, "version": "1.0.0",
    "meta": {
      "title": {"en": "Synthetic plugin", "zh": "合成插件"},
      "description": {"en": "A synthetic package for loaded-card checks.", "zh": "用于已加载卡片核对的合成扩展包。"}
    },
    "rows": [], "overrides": []
  },
  "scenarios": [
    {"id": "default", "package": {}, "expected": {"enabled": true, "locked": false, "tagKeys": []}},
    {"id": "no-description", "package": {"name": "@synthetic/card-no-description", "meta": {"title": {"en": "No description", "zh": "没有说明"}}}, "expected": {"enabled": true, "locked": false, "tagKeys": []}},
    {"id": "long-tags", "package": {
      "name": "@deepseek-ai/dsh-experimental-synthetic-card", "availability": "missing", "enabled": false,
      "error": {"code": "operation-error", "diagnostic": "Synthetic unavailable files"},
      "installTarget": {"spec": "@synthetic/card@2.0.0", "version": "2.0.0"},
      "meta": {
        "title": {"en": "A deliberately long localized synthetic plugin title with adjacent status tags", "zh": "带有相邻状态标签的故意加长本地化合成插件标题用于核对自然换行"},
        "description": {"en": "A deliberately long synthetic description that must retain the source single-line clamp while the title and tags wrap naturally.", "zh": "这是一段故意加长的合成说明，应当保留原版单行截断，同时允许标题和状态标签自然换行。"}
      }
    }, "expected": {"enabled": false, "locked": false, "tagKeys": ["statusBeta", "statusProblem", "statusMissingFiles", "statusUpdateAvailable"]}},
    {"id": "problem-enabled", "package": {"name": "@synthetic/card-problem-enabled", "error": {"code": "operation-error", "diagnostic": "Synthetic enabled package failure"}}, "expected": {"enabled": true, "locked": false, "tagKeys": ["statusProblem"]}},
    {"id": "metadata-error", "package": {"name": "@synthetic/card-metadata-error", "meta": {"title": {"en": "Metadata error", "zh": "元数据错误"}, "description": {"en": "The metadata diagnostic owns its own line.", "zh": "元数据诊断保留独立文本行。"}, "error": "Synthetic metadata diagnostic\nwith a second line"}}, "expected": {"enabled": true, "locked": false, "tagKeys": [], "metadataError": true}},
    {"id": "busy", "busy": true, "package": {"name": "@synthetic/card-busy"}, "expected": {"enabled": true, "locked": true, "tagKeys": []}},
    {"id": "read-only", "package": {"name": "@synthetic/card-read-only", "readOnlyReason": "management-required"}, "expected": {"enabled": true, "locked": true, "tagKeys": []}},
    {"id": "error-disabled", "package": {"name": "@synthetic/card-error-disabled", "enabled": false, "error": {"code": "operation-error", "diagnostic": "Synthetic disabled package failure"}}, "expected": {"enabled": false, "locked": true, "tagKeys": ["statusProblem"]}},
    {"id": "missing-recovery", "package": {"name": "@synthetic/card-missing-recovery", "availability": "missing", "installed": false, "enabled": false, "error": {"code": "operation-error", "diagnostic": "Synthetic missing package"}, "installTarget": {"spec": "@synthetic/card@2.0.0", "version": "2.0.0"}}, "expected": {"enabled": false, "locked": false, "tagKeys": ["statusProblem", "statusNotInstalled"]}},
    {"id": "refused-toggle", "refuseToggle": true, "package": {"name": "@synthetic/card-refused-toggle"}, "expected": {"enabled": true, "locked": false, "tagKeys": []}},
    {"id": "image-failed", "package": {"name": "@synthetic/card-image-failed", "meta": {"title": {"en": "Failed artwork", "zh": "加载失败的图像"}, "description": {"en": "Invalid data PNG falls back without a network request.", "zh": "无效的数据图像直接回退，不发起网络请求。"}, "icon": "data:image/png;base64,AAAA"}}, "expected": {"enabled": true, "locked": false, "tagKeys": []}}
  ]
}
''';

final Map<String, Map<String, Object?>> pluginCardScenarios = () {
  final data = jsonDecode(pluginCardScenarioJson) as Map<String, dynamic>;
  if (data['schema'] != 'dsh-plugin-card-scenarios/1') {
    throw StateError('Unexpected loaded-card fixture schema');
  }
  final base = (data['basePackage'] as Map).cast<String, Object?>();
  return {
    for (final raw in data['scenarios'] as List)
      (raw as Map)['id'] as String: {
        ...raw.cast<String, Object?>(),
        'package': {
          ...base,
          ...(raw['package'] as Map).cast<String, Object?>(),
        },
      },
  };
}();

/// Offline business adapter around the existing real manager fixture. Page,
/// card, switch, navigation and model actions remain the actual implementations.
class SyntheticPluginCardFixture {
  SyntheticPluginCardFixture(this.scenario) {
    _package = Map<String, Object?>.from(
      (scenario['package'] as Map).cast<String, Object?>(),
    );
    enabled = _package['enabled'] as bool;
    host.handlers['pluginManager/listBundles'] = (_) => [
      {..._package, 'enabled': enabled},
    ];
    host.handlers['pluginManager/listPlugins'] = (_) => <Object?>[];
    host.handlers['pluginInventory/list'] = (_) => {
      'managementAvailable': true,
      'entries': <Object?>[],
      'agentPresets': <Object?>[],
    };
    host.handlers['pluginManager/setBundleEnabled'] = (args) {
      attempts++;
      requestedValues.add(args['enabled'] as bool);
      if (scenario['refuseToggle'] == true) {
        refusals++;
        return {
          'changed': false,
          'application': 'failed',
          'stage': 'enable',
          'target': packageName,
          'error': {
            'code': 'operation-error',
            'diagnostic': 'Synthetic toggle refused',
          },
        };
      }
      enabled = args['enabled'] as bool;
      return {
        'changed': true,
        'application': 'applied',
        'stage': 'enable',
        'target': packageName,
      };
    };
    if (scenario['busy'] == true) manager.busy.add(packageName);
  }

  factory SyntheticPluginCardFixture.fromId(String id) =>
      SyntheticPluginCardFixture(
        pluginCardScenarios[id] ??
            (throw ArgumentError.value(id, 'id', 'Unknown card scenario')),
      );

  final Map<String, Object?> scenario;
  final _base = SyntheticPluginsPreview();
  late final Map<String, Object?> _package;
  late bool enabled;
  int attempts = 0, refusals = 0;
  final requestedValues = <bool>[];
  FakeHost get host => _base.host;
  PluginManagerModel get manager => _base.manager;
  PluginMarketModel get market => _base.market;
  String get packageName => _package['name'] as String;
  Future<void> load() => manager.load();
  Future<void> dispose() => _base.dispose();
}
