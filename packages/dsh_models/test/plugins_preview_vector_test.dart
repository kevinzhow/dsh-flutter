import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/generated_plugin_manager.dart' as wire;
import 'package:dsh_client/generated_plugin_market.dart' as market;
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

void main() {
  final input = jsonDecode(
    File('test/fixtures/plugins_preview.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final expected = input['expected'] as Map<String, dynamic>;
  PluginDiscoverQuery query(Map<String, dynamic> q) => PluginDiscoverQuery(
    text: q['text'] as String,
    category: q['category'] as String?,
    labels: (q['labels'] as List).cast<String>(),
    sort: market.MarketSort.fromJson(q['sort']),
  );
  Map<String, Object?> jsonQuery(PluginDiscoverQuery q) => {
    'text': q.text,
    'category': q.category,
    'labels': q.labels,
    'sort': q.sort.toJson(),
  };
  test('exact upstream package identities, registry normalization and market query policies', () {
    expect(
      (input['names'] as List).cast<String>().map(pluginShortName).toList(),
      expected['shortNames'],
    );
    expect(
      (input['keys'] as List)
          .map(
            (dynamic v) => pluginRegistryKey(
              v['registry'] as String?,
              v['resolved'] as String?,
            ),
          )
          .toList(),
      expected['registryKeys'],
    );
    expect(
      (input['registries'] as List)
          .map(
            (v) => pluginRegistryOffers(
              v == null ? null : wire.PluginRegistries.fromJson(v),
            ),
          )
          .toList(),
      expected['offers'],
    );
    final entries = (input['plugins'] as List)
        .map(wire.PluginInfo.fromJson)
        .toList();
    final packages =
        (input['bundles'] as List)
            .map(
              (b) => ManagedPluginPackage(wire.BundleInfo.fromJson(b), entries),
            )
            .toList()
          ..sort(
            (a, b) =>
                pluginShortName(a.bundle.name)
                    .compareTo(pluginShortName(b.bundle.name)),
          );
    expect([
      for (final p in packages)
        {
          ...p.bundle.toJson()..remove('overrides'),
          'rows': [
            for (final row in p.rows)
              {
                'rowId': row.declaration.rowId,
                'moduleName': row.declaration.moduleName,
                'enabled': row.enabled,
                'phase': row.phase?.value,
                if (row.declaration.meta != null)
                  'meta': row.declaration.meta!.toJson(),
                if (row.declaration.entryId != null)
                  'entryId': row.declaration.entryId,
                if (row.readOnlyReason != null)
                  'readOnlyReason': row.readOnlyReason,
              },
          ],
        },
    ], expected['packages']);
    final metadata = market.MarketIndexMetadata.fromJson(input['metadata']);
    expect(
      (input['queries'] as List)
          .map(
            (dynamic v) => jsonQuery(
              query((v['query'] as Map).cast<String, dynamic>())
                  .withText(v['text'] as String),
            ),
          )
          .toList(),
      expected['queries'],
    );
    expect(
      (input['queries'] as List)
          .map(
            (dynamic v) => jsonQuery(
              query((v['query'] as Map).cast<String, dynamic>())
                  .declared(metadata),
            ),
          )
          .toList(),
      expected['declared'],
    );
    expect(
      (input['phases'] as List)
          .map(
            (name) => PluginInstallPhase.values.byName(name as String).pending,
          )
          .toList(),
      expected['pending'],
    );
  });
  test(
    'cancellation lifecycle matches the original TypeScript controller',
    () async {
      final host = FakeHost();
      host.handlers['pluginManager/registries'] = (_) => {
        'registry': null,
        'resolved': null,
        'fallbackRegistries': <String>[],
      };
      host.handlers['pluginManager/inspect'] = (_) => {
        'status': 'accepted',
        'kind': 'registry',
        'name': 'package',
        'bundle': true,
        'registry': null,
      };
      final install = Completer<Object?>();
      host.handlers['pluginManager/installBundle'] = (_) => install.future;
      var cancels = 0;
      host.handlers['pluginManager/cancelInstall'] = (_) => {
        'status': ++cancels == 1 ? 'not-running' : 'too-late',
      };
      final model = PluginInstaller(
        remotes: host.remotes,
        reload: () async {},
        listedAvailability: (_) => null,
        notify: (_) {},
        newId: () => 'request',
      );
      model.show(installSpec: 'package');
      final running = model.install();
      await Future<void>.delayed(Duration.zero);
      final phases = [model.phase.name];
      await model.cancel();
      phases.add(model.phase.name);
      model.progress({'requestId': 'request', 'phase': 'installing'});
      await Future<void>.delayed(Duration.zero);
      phases.add(model.phase.name);
      model.progress({'requestId': 'request', 'phase': 'installing'});
      await Future<void>.delayed(Duration.zero);
      phases.add(model.phase.name);
      install.complete({
        'changed': true,
        'application': 'restart-required',
        'stage': 'install',
        'target': 'package',
      });
      await running;
      phases.add(model.phase.name);
      expect({'phases': phases, 'calls': cancels}, expected['cancellation']);
      model.dispose();
      await host.close();
    },
  );
}
