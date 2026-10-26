import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_plugin_manager.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

Map<String, Object?> bundle(String name, {bool enabled = false}) => {
  'name': name,
  'official': true,
  'availability': 'profile',
  'enabled': enabled,
  'installed': true,
  'optional': false,
  'removable': true,
  'rows': [
    {'rowId': 'same', 'moduleName': 'module', 'entryId': 'entry'},
  ],
  'overrides': <String>[],
};
Map<String, Object?> outcome(
  String application, {
  Map<String, Object?>? extra,
}) => {
  'changed': application != 'failed',
  'application': application,
  'stage': 'install',
  'target': 'package',
  ...?extra,
};
Future<void> turn() => Future<void>.delayed(Duration.zero);
void main() {
  late FakeHost host;
  late PluginManagerModel model;
  setUp(() {
    host = FakeHost();
    host.handlers['pluginInventory/list'] = (_) => {
      'managementAvailable': true,
      'entries': <Object?>[],
    };
    host.handlers['pluginManager/listBundles'] = (_) => [
      bundle('@demo/dsh-beta'),
      bundle('@demo/dsh-host-alpha'),
    ];
    host.handlers['pluginManager/listPlugins'] = (_) => [
      {
        'entryId': 'entry',
        'moduleName': 'module',
        'enabled': true,
        'fiberPhase': 'active',
        'patchId': 'same',
      },
    ];
    host.handlers['pluginManager/registries'] = (_) => {
      'registry': 'https://private.example/',
      'fallbackRegistries': <String>[],
      'resolved': 'https://registry.npmjs.org/',
    };
    host.handlers['pluginManager/inspect'] = (_) => {
      'status': 'accepted',
      'kind': 'registry',
      'name': 'package',
      'bundle': true,
      'registry': null,
    };
    model = PluginManagerModel(remotes: host.remotes, newId: () => 'request');
  });
  tearDown(() async {
    await model.dispose();
    await host.close();
  });

  test('inventory gates management; rows join by entry identity and cached refresh survives refusal', () async {
    await model.load();
    expect(model.packages.map((p) => p.bundle.name), [
      '@demo/dsh-host-alpha',
      '@demo/dsh-beta',
    ]);
    expect(model.packages.first.rows.single.enabled, isTrue);
    expect(model.packages.first.bundle.enabled, isFalse);
    host.handlers['pluginInventory/list'] = (_) =>
        throw RemoteException('transport/offline', 'offline');
    await model.refresh();
    expect(model.status, PluginManagerStatus.ready);
    expect(model.packages, hasLength(2));
    expect(model.notice?.kind, 'refresh-failed');
    host.handlers['pluginInventory/list'] = (_) => {'entries': <Object?>[]};
    await model.load();
    expect(model.status, PluginManagerStatus.unavailable);
    expect(model.packages, isEmpty);
    expect(host.callsTo('pluginManager/listBundles'), hasLength(1));
  });

  test('changed event during load reruns without cancelling the active install settlement', () async {
    final first = Completer<Object?>();
    var reads = 0;
    host.handlers['pluginManager/listBundles'] = (_) =>
        ++reads == 1 ? first.future : [bundle('new')];
    final loading = model.load();
    await turn();
    host.emit('plugin-manager/changed');
    first.complete([bundle('old')]);
    await loading;
    expect(model.packages.single.bundle.name, 'new');
    final install = Completer<Object?>();
    host.handlers['pluginManager/installBundle'] = (_) => install.future;
    model.installer.show(installSpec: 'package');
    final pending = model.installer.install();
    await turn();
    host.emit('plugin-manager/changed');
    await turn();
    install.complete(
      outcome('applied', extra: {'bundle': 'package', 'version': '1.0'}),
    );
    await pending;
    expect(model.installer.phase, PluginInstallPhase.done);
    expect(model.installer.installed, 'package');
  });

  test('pnpm default null is transmitted distinctly from configured or omitted registry', () async {
    expect(
      const InstallBundleOptions().toJson().containsKey('registry'),
      isFalse,
    );
    expect(InstallBundleOptions.fromJson({'registry': null}).toJson(), {
      'registry': null,
    });
    final install = Completer<Object?>();
    host.handlers['pluginManager/installBundle'] = (_) => install.future;
    model.installer.show(installSpec: 'package');
    await turn();
    model.installer.chooseRegistry(const PluginRegistryChoice.offered(null));
    final pending = model.installer.install();
    await turn();
    expect(host.callsTo('pluginManager/inspect').single.args['options'], {
      'registry': null,
    });
    expect(
      (host.callsTo('pluginManager/installBundle').single.args['options']
          as Map<String, Object?>)['registry'],
      isNull,
    );
    expect(
      (host.callsTo('pluginManager/installBundle').single.args['options']
              as Map<String, Object?>)
          .containsKey('registry'),
      isTrue,
    );
    install.complete(outcome('applied'));
    await pending;
  });

  test('lost result plus absent recovery remains unknown; scripts never auto-approved', () async {
    host.handlers['pluginManager/installBundle'] = (_) =>
        throw RemoteException('transport/lost', 'lost');
    host.handlers['pluginManager/waitForInstall'] = (_) => null;
    model.installer.show(installSpec: 'package');
    await model.installer.install();
    await turn();
    expect(model.installer.phase, PluginInstallPhase.unknown);
    expect(model.installer.installed, isNull);
    model.installer.edit('package');
    host.handlers['pluginManager/installBundle'] = (_) => outcome(
      'failed',
      extra: {
        'error': {'code': 'operation-error'},
        'pendingBuilds': ['native-addon'],
      },
    );
    await model.installer.install();
    expect(model.installer.phase, PluginInstallPhase.failed);
    model.requestBuildApproval();
    final confirm = model.confirmation!;
    expect(confirm.pendingBuilds, ['native-addon']);
    expect(host.callsTo('pluginManager/installBundle'), hasLength(2));
    host.handlers['pluginManager/installBundle'] = (_) => outcome('applied');
    await model.confirm(confirm);
    final options =
        host.callsTo('pluginManager/installBundle').last.args['options']
            as Map<String, Object?>;
    expect(options['approvedBuilds'], ['native-addon']);
    await model.confirm(confirm); // stale confirmation is inert
    expect(host.callsTo('pluginManager/installBundle'), hasLength(3));
  });

  test('cancel overtaking acceptance retries after progress, and applying never reopens cancellation', () async {
    final install = Completer<Object?>();
    host.handlers['pluginManager/installBundle'] = (_) => install.future;
    var cancellations = 0;
    host.handlers['pluginManager/cancelInstall'] = (_) => {
      'status': ++cancellations == 1 ? 'not-running' : 'too-late',
    };
    model.installer.show(installSpec: 'package');
    final pending = model.installer.install();
    await turn();
    await model.installer.cancel();
    expect(model.installer.phase, PluginInstallPhase.unconfirmed);
    host.emit('plugin-manager/install-state', [
      {'requestId': 'foreign', 'phase': 'applying'},
    ]);
    expect(model.installer.phase, PluginInstallPhase.unconfirmed);
    host.emit('plugin-manager/install-state', [
      {'requestId': 'request', 'phase': 'installing'},
    ]);
    await turn();
    expect(cancellations, 2);
    expect(model.installer.phase, PluginInstallPhase.applying);
    host.emit('plugin-manager/install-state', [
      {'requestId': 'request', 'phase': 'installing'},
    ]);
    await model.installer.cancel();
    expect(cancellations, 2);
    expect(model.installer.phase, PluginInstallPhase.applying);
    install.complete(outcome('restart-required'));
    await pending;
    expect(model.installer.restartRequired, isTrue);
  });

  test('late logs settle existing runs only; exact version grants need risk acceptance', () async {
    final install = Completer<Object?>();
    host.handlers['pluginManager/installBundle'] = (_) => install.future;
    model.installer.show(installSpec: 'package');
    final pending = model.installer.install();
    await turn();
    Map<String, Object?> chunk(String id, String text) => {
      'requestId': 'request',
      'jobId': id,
      'argv': ['pnpm', 'add'],
      'cwd': '/synthetic',
      'text': text,
    };
    host.emit('plugin-manager/install-log', [chunk('job', 'first')]);
    install.complete(outcome('applied'));
    await pending;
    host.emit('plugin-manager/install-log', [chunk('job', 'last')]);
    host.emit('plugin-manager/install-log', [chunk('new', 'ignored')]);
    expect(model.installer.runs.single.output, 'firstlast');
    host.handlers['pluginManager/setVersionExemption'] = (_) =>
        outcome('restart-required');
    model.requestVersionExemption([
      const IncompatiblePlugin(
        name: 'package',
        version: '1.0',
        runtimeVersion: '2.0',
        requirements: {'engines.dsh': '^1'},
      ),
    ]);
    final confirm = model.confirmation!;
    await model.confirm(confirm);
    expect(host.callsTo('pluginManager/setVersionExemption'), isEmpty);
    await model.confirm(confirm, acceptRisk: true);
    expect(host.callsTo('pluginManager/setVersionExemption').single.args, {
      'packageVersion': 'package@1.0',
      'runtimeVersion': '2.0',
      'enabled': true,
      'acceptRisk': true,
    });
  });

  test(
    'template examples never execute; inspected registry owns the install plan',
    () async {
      for (final example in [
        'https://github.com/author/dsh-plugin',
        '/Users/name/my-plugin',
      ]) {
        model.installer.show(installSpec: example);
        await model.installer.install();
        expect(model.installer.error, startsWith('template-'));
      }
      expect(host.callsTo('pluginManager/inspect'), isEmpty);
      host.handlers['pluginManager/inspect'] = (_) => {
        'status': 'accepted',
        'kind': 'registry',
        'name': 'package',
        'bundle': true,
        'registry': 'https://answered.example/',
      };
      host.handlers['pluginManager/installBundle'] = (_) =>
          outcome('applied', extra: {'bundle': 'package', 'version': '1.0'});
      model.installer.edit('package');
      await model.installer.install();
      final options =
          host.callsTo('pluginManager/installBundle').single.args['options']
              as Map;
      expect(options['registry'], 'https://answered.example/');
      expect(options['enabled'], isFalse);
      host.handlers['pluginManager/setBundleEnabled'] = (_) =>
          outcome('restart-required', extra: {'restartReason': 'no-hmr'});
      await model.installer.enableInstalled();
      expect(model.notice?.kind, 'restart-required');
      expect(model.notice?.restartReason?.value, 'no-hmr');
    },
  );

  test('GitHub network failure offers mirror recovery without retrying a guessed spec', () async {
    host.handlers['pluginManager/registries'] = (_) => {
      'registry': null,
      'resolved': officialPluginRegistry,
      'fallbackRegistries': [mirrorPluginRegistry],
    };
    host.handlers['pluginRegistryProbe/probe'] = (_) => null;
    host.handlers['pluginManager/inspect'] = (_) => {
      'status': 'accepted',
      'kind': 'git',
      'name': 'package',
      'bundle': true,
      'registry': null,
      'host': 'github.com',
    };
    host.handlers['pluginManager/installBundle'] = (_) => outcome(
      'failed',
      extra: {
        'failedAt': 'spec-host',
        'packageResult': {
          'kind': 'network',
          'exitCode': 1,
          'output': 'Synthetic network failure',
          'truncated': false,
          'logPath': '/synthetic/install.log',
        },
      },
    );
    model.installer.show(installSpec: 'https://github.com/synthetic/plugin');
    await model.installer.install();
    expect(model.installer.githubRecovery?.registry, mirrorPluginRegistry);
    model.installer.recoverGithub();
    expect(model.installer.spec, isEmpty);
    expect(model.installer.registry.registry, mirrorPluginRegistry);
    expect(host.callsTo('pluginManager/installBundle'), hasLength(1));
  });
}
