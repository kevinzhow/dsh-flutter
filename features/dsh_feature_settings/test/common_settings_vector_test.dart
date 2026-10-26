import 'dart:convert';
import 'dart:io';

import 'support/script_form.dart';

import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> shell(SettingsFormShell s) => {
  'available': s.available,
  'writable': s.writable,
  'dirty': s.dirty,
  'invalid': s.invalid,
  'saving': s.saving,
  'failed': s.failed,
};
Map<String, Object?> field(SettingsFieldState s) => {
  'text': s.text,
  'overridden': s.overridden,
  'invalid': s.invalid,
};
Map<String, Object?> jsonMap(Object? value) =>
    (value as Map).cast<String, Object?>();
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final fixture = jsonMap(
    jsonDecode(
      File(
        File('test/fixtures/common_settings_behavior.json').existsSync()
            ? 'test/fixtures/common_settings_behavior.json'
            : 'features/dsh_feature_settings/test/fixtures/common_settings_behavior.json',
      ).readAsStringSync(),
    ),
  );
  final expected = jsonMap(fixture['expected']);
  test('Web settings traces replay actual upstream controllers, including partial refusal and credential-only save', () async {
    final traces = <Object?>[];
    for (final item in fixture['web'] as List) {
      final c = jsonMap(item);
      final calls = <Map<String, Object?>>[];
      final keys = <Map<String, Object?>>[];
      final scopes = {
        for (final e in {
          'web': 'web',
          'messages': 'web-search-deepseek',
          'api': 'web-deepseek-api',
        }.entries)
          e.key: ScriptForm(e.value, jsonMap(c[e.key]), calls),
      };
      final host = FakeHost();
      host.handlers['credentials/describe'] = (args) => {
        for (final ref in args['refs'] as List)
          ref: {
            'configured': keys.any((k) => k['ref'] == ref),
            'writable': true,
          },
      };
      host.handlers['credentials/set'] = (args) {
        keys.add(Map.of(args));
        return null;
      };
      final web = WebSearchController.scopes(
        web: scopes['web']!,
        messages: scopes['messages']!,
        api: scopes['api']!,
        remotes: host.remotes,
      );
      final trace = <Object?>[];
      for (final action in [
        {'op': 'initial'},
        ...c['actions'] as List,
      ]) {
        final a = jsonMap(action);
        switch (a['op']) {
          case 'select':
            web.selectApi(a['value'] as bool);
          case 'edit':
            web.edit(a['field'] as String, a['value'] as String);
          case 'reset':
            web.reset(a['field'] as String);
          case 'save':
            await web.save();
          case 'fail':
            scopes[a['scope']]!.refuse = true;
          case 'discard':
            web.discard();
        }
        await settle();
        trace.add(
          jsonDecode(
            jsonEncode({
              'state': {
                ...shell(web.shell),
                'apiSwitchAvailable': web.switchAvailable,
                'apiSwitchBlocked': web.shell.invalid || web.shell.failed,
                'useSearchApi': web.useSearchApi,
                'baseURL': field(web.field('baseURL')),
                'maxUses': field(web.field('maxUses')),
                'count': field(web.field('count')),
                'apiKey': field(web.field('apiKey')),
                'apiKeyConfigured': web.credential?.configured ?? false,
                'apiKeyWritable': web.credential?.writable ?? true,
              },
              'calls': calls,
              'keys': keys,
            }),
          ),
        );
      }
      traces.add(trace);
      await web.dispose();
      await host.close();
    }
    expect(traces, expected['web']);
  });
  test('Subagent allowlist traces retain removed models and match upstream revision conflicts', () async {
    final traces = <Object?>[];
    for (final item in fixture['subagent'] as List) {
      final c = jsonMap(item);
      final calls = <Map<String, Object?>>[];
      final form = ScriptForm(
        'subagent-model-selection-settings',
        jsonMap(c['initial']),
        calls,
      );
      final host = FakeHost();
      host.handlers['session/modelCatalog'] = (_) => c['catalog'];
      final controller = SubagentModelsController(form, host.remotes);
      final trace = <Object?>[];
      for (final action in [
        {'op': 'initial'},
        ...c['actions'] as List,
      ]) {
        final a = jsonMap(action);
        switch (a['op']) {
          case 'enable':
            controller.toggleEnabled(!controller.enabled);
          case 'toggle':
            controller.toggleModel(
              subagentModelKey((
                provider: a['provider'] as String,
                model: a['model'] as String,
              )),
            );
          case 'save':
            await controller.save();
          case 'replace':
            form.replace(jsonMap(a['value']));
          case 'discard':
            controller.discard();
        }
        await settle();
        trace.add(
          jsonDecode(
            jsonEncode({
              'state': {
                ...shell(controller.shell),
                'enabled': controller.enabled,
                'candidates': [
                  for (final row in controller.candidates)
                    {
                      'provider': row.route.provider,
                      'model': row.route.model,
                      'key': row.key,
                      'providerName': row.providerName,
                      'modelName': row.modelName,
                      'available': row.available,
                      'selected': row.selected,
                    },
                ],
                'catalogStatus': controller.catalogStatus,
                'catalogPartial': controller.catalogPartial,
                'conflicted': controller.conflicted,
              },
              'calls': calls,
            }),
          ),
        );
      }
      traces.add(trace);
      await controller.dispose();
      await host.close();
    }
    expect(traces, expected['subagent']);
  });
}
