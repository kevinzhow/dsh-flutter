import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_feature_permission_presets/dsh_feature_permission_presets.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> catalogJson({
  List<String> options = const [
    'read-only',
    'workspace-write',
    'danger-full-access',
  ],
  String defaultPreset = 'workspace-write',
  bool auto = false,
}) => {
  'options': [
    for (final o in [...options, if (auto) 'auto'])
      {
        'value': o,
        'name': o,
        if (o == 'workspace-write')
          'description': 'Write inside the workspace.',
      },
  ],
  'defaultOptions': [
    for (final o in options)
      if (o != 'auto') {'value': o, 'name': o},
  ],
  'defaultPreset': defaultPreset,
};

final permissionSchema = objectSchema({'defaultPreset': stringNode});

Map<String, Object?> permissionView({String? preset, int revision = 0}) =>
    nsView(
      'permission',
      schema: permissionSchema,
      value: {'defaultPreset': ?preset},
      base: const {},
      user: {'defaultPreset': ?preset},
      revision: revision,
    );

Future<void> flush([int times = 4]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeHost host;
  late ConfigForms forms;
  late PermissionCatalogDirectory catalog;
  late PermissionDefaultController defaults;
  late FakeGeneration generation;
  var served = true;

  setUp(() {
    served = true;
    host = FakeHost();
    generation = FakeGeneration();
    host.generation = generation;
    host.handlers['settings/describe'] = (_) =>
        describeValue([if (served) permissionView(preset: 'read-only')]);
    host.handlers['permissionPresets/catalog'] = (_) => catalogJson();
    forms = ConfigForms(host.remotes);
    catalog = PermissionCatalogDirectory(host.remotes);
    defaults = PermissionDefaultController(
      mirror: forms.mirror,
      remotes: host.remotes,
      catalog: catalog,
    );
  });

  tearDown(() async {
    await defaults.dispose();
    await catalog.dispose();
    await forms.dispose();
    await host.close();
  });

  group('presentation', () {
    const en = DshI18n(DshLocale.en);
    const zh = DshI18n(DshLocale.zh);

    test('built-in presets get their product label in both languages', () {
      expect(
        displayPermissionPreset('read-only', 'read-only', en),
        'Read Only',
      );
      expect(displayPermissionPreset('read-only', 'Read Only', zh), '仅可查看');
      expect(
        displayPermissionPreset('danger-full-access', 'danger-full-access', zh),
        '完全权限',
      );
    });

    test('a host-renamed preset keeps the host name, title-cased if kebab', () {
      expect(
        displayPermissionPreset('workspace-write', 'Careful', en),
        'Careful',
      );
      expect(
        displayPermissionPreset('ci-sandbox', 'ci-sandbox', en),
        'Ci Sandbox',
      );
      expect(displayPermissionPreset('x', 'Has Spaces', en), 'Has Spaces');
    });
  });

  group('catalog directory', () {
    test('reads the catalog of the live generation at start', () async {
      await flush();
      expect(catalog.value.value?.defaultPreset, 'workspace-write');
      expect(host.callsTo('permissionPresets/catalog'), hasLength(1));
    });

    test('a catalog-changed notice invalidates then refreshes', () async {
      await flush();
      final ticks = <int>[];
      catalog.invalidations.changes.listen(ticks.add);
      host.handlers['permissionPresets/catalog'] = (_) =>
          catalogJson(auto: true);
      host.emit('permission-presets/catalog-changed');
      await flush();
      expect(ticks, [1]);
      expect([
        for (final o in catalog.value.value!.options) o.value,
      ], contains('auto'));
    });

    test('a new generation hard-clears the old value and rereads', () async {
      await flush();
      final next = FakeGeneration();
      host.generation = next;
      final gate = Completer<void>();
      host.handlers['permissionPresets/catalog'] = (_) async {
        await gate.future;
        return catalogJson(defaultPreset: 'read-only');
      };
      host.gens.add(next);
      expect(catalog.value.value, isNull);
      expect(catalog.invalidations.value, 1);
      gate.complete();
      await flush();
      expect(catalog.value.value?.defaultPreset, 'read-only');
    });

    test('a stale generation settlement is dropped', () async {
      final gate = Completer<void>();
      host.handlers['permissionPresets/catalog'] = (_) async {
        await gate.future;
        return catalogJson(defaultPreset: 'read-only');
      };
      await catalog.dispose();
      host.generation = generation;
      catalog = PermissionCatalogDirectory(host.remotes);
      await flush();
      host.generation = FakeGeneration();
      host.gens.add(host.generation);
      gate.complete();
      await flush();
      // The first read settled for the old generation: never published.
      expect(catalog.value.value?.defaultPreset, 'read-only');
      expect(host.callsTo('permissionPresets/catalog'), hasLength(3));
    });

    test('load waits for the active read and fails with its error', () async {
      await catalog.dispose();
      host.handlers['permissionPresets/catalog'] = (_) =>
          throw RemoteException('gateway/internal', 'catalog down');
      catalog = PermissionCatalogDirectory(host.remotes);
      await expectLater(catalog.load(), throwsA(isA<RemoteException>()));
    });

    test('load without a connection fails', () async {
      await catalog.dispose();
      host.generation = null;
      catalog = PermissionCatalogDirectory(host.remotes);
      await expectLater(catalog.load(), throwsA(isA<StateError>()));
    });
  });

  group('default controller', () {
    test('derives the current default and the allowed options', () async {
      await defaults.load();
      final s = defaults.state.value;
      expect(s.status, PermissionRowStatus.ready);
      expect(s.currentValue, 'read-only');
      expect(
        [for (final o in s.options) o.id],
        ['read-only', 'workspace-write', 'danger-full-access'],
      );
      expect(s.writable, isTrue);
    });

    test('an unset default falls back to the catalog default', () async {
      host.handlers['settings/describe'] = (_) =>
          describeValue([permissionView()]);
      await forms.mirror.load();
      await defaults.load();
      expect(defaults.state.value.currentValue, 'workspace-write');
    });

    test(
      'select writes defaultPreset fenced by the revision and folds it',
      () async {
        host.handlers['settings/mutate'] = (args) =>
            permissionView(preset: 'danger-full-access', revision: 1);
        await defaults.load();
        await defaults.select('danger-full-access');
        final call = host.callsTo('settings/mutate').single;
        expect(call.args['ns'], 'permission');
        expect(call.args['expectedRevision'], 0);
        expect(call.args['ops'], [
          {
            'op': 'set',
            'path': ['defaultPreset'],
            'value': 'danger-full-access',
          },
        ]);
        expect(defaults.state.value.currentValue, 'danger-full-access');
        expect(defaults.state.value.status, PermissionRowStatus.ready);
        expect(defaults.state.value.revision, 1);
      },
    );

    test(
      'a refused write reports the host message and keeps the value',
      () async {
        host.handlers['settings/mutate'] = (_) =>
            throw RemoteException('settings/rejected', 'unknown preset');
        await defaults.load();
        await defaults.select('workspace-write');
        expect(defaults.state.value.status, PermissionRowStatus.error);
        expect(defaults.state.value.error, 'unknown preset');
      },
    );

    test('a second select while one is saving is ignored', () async {
      final gate = Completer<void>();
      host.handlers['settings/mutate'] = (_) async {
        await gate.future;
        return permissionView(preset: 'workspace-write', revision: 1);
      };
      await defaults.load();
      final first = defaults.select('workspace-write');
      await defaults.select('danger-full-access');
      expect(host.callsTo('settings/mutate'), hasLength(1));
      expect(defaults.state.value.status, PermissionRowStatus.saving);
      gate.complete();
      await first;
    });

    test('a namespace the host does not serve is unavailable', () async {
      served = false;
      await forms.mirror.load();
      await defaults.load();
      expect(defaults.state.value.status, PermissionRowStatus.unavailable);
    });

    test('a catalog that does not advertise the default is an error', () async {
      host.handlers['permissionPresets/catalog'] = (_) =>
          catalogJson(options: ['workspace-write']);
      await catalog.dispose();
      catalog = PermissionCatalogDirectory(host.remotes);
      defaults = PermissionDefaultController(
        mirror: forms.mirror,
        remotes: host.remotes,
        catalog: catalog,
      );
      await defaults.load();
      expect(defaults.state.value.status, PermissionRowStatus.error);
      expect(defaults.state.value.error, contains('current default'));
    });

    test('read-only hosts report writable false', () async {
      host.handlers['settings/describe'] = (_) =>
          describeValue([permissionView(preset: 'read-only')], writable: false);
      await forms.mirror.load();
      await defaults.load();
      expect(defaults.state.value.writable, isFalse);
    });
  });

  group('settings row', () {
    late SlotRegistry slots;
    var i18n = const DshI18n(DshLocale.en);

    setUp(() {
      i18n = const DshI18n(DshLocale.en);
      slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
    });

    Widget row() => dshTestApp(
      Padding(
        padding: const EdgeInsets.all(16),
        child: PermissionRow(controller: defaults, i18n: i18n),
      ),
      size: const Size(390, 600),
    );

    testWidgets('shows the default and its description, then opens choices', (
      t,
    ) async {
      await t.runAsync(() async {
        await t.pumpWidget(row());
        await flush(8);
      });
      await t.pump();
      expect(find.text('Permission'), findsOneWidget);
      expect(
        find.text('Choose the default permission mode for new sessions'),
        findsOneWidget,
      );
      expect(find.text('Read Only'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('permission-selector')));
      await t.pumpAndSettle();
      expect(find.text('Workspace Write'), findsOneWidget);
      expect(find.text('Full access'), findsOneWidget);
    });

    testWidgets('picking a plain preset writes it', (t) async {
      host.handlers['settings/mutate'] = (_) =>
          permissionView(preset: 'workspace-write', revision: 1);
      await t.runAsync(() async {
        await t.pumpWidget(row());
        await flush(8);
      });
      await t.pump();
      await t.tap(find.byKey(const ValueKey<String>('permission-selector')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('option-workspace-write')));
      await t.pumpAndSettle();
      await t.runAsync(() => flush(6));
      await t.pump();
      expect(host.callsTo('settings/mutate'), hasLength(1));
      expect(find.text('Workspace Write'), findsOneWidget);
    });

    testWidgets('Full access waits for the acknowledgement', (t) async {
      host.handlers['settings/mutate'] = (_) =>
          permissionView(preset: 'danger-full-access', revision: 1);
      await t.runAsync(() async {
        await t.pumpWidget(row());
        await flush(8);
      });
      await t.pump();
      await t.tap(find.byKey(const ValueKey<String>('permission-selector')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('option-danger-full-access')));
      await t.pumpAndSettle();
      expect(find.text('Enable Full access?'), findsOneWidget);
      final confirm = find.byKey(const ValueKey('risk-confirm'));
      await t.tap(confirm);
      await t.pump();
      expect(host.callsTo('settings/mutate'), isEmpty);
      await t.tap(find.byKey(const ValueKey('risk-acknowledge')));
      await t.pump();
      await t.tap(confirm);
      await t.pumpAndSettle();
      await t.runAsync(() => flush(6));
      await t.pump();
      expect(host.callsTo('settings/mutate'), hasLength(1));
      expect(find.text('Full access'), findsOneWidget);
    });

    testWidgets('cancelling the acknowledgement writes nothing', (t) async {
      await t.runAsync(() async {
        await t.pumpWidget(row());
        await flush(8);
      });
      await t.pump();
      await t.tap(find.byKey(const ValueKey<String>('permission-selector')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('option-danger-full-access')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('risk-cancel')));
      await t.pumpAndSettle();
      expect(host.callsTo('settings/mutate'), isEmpty);
      expect(find.text('Read Only'), findsOneWidget);
    });

    testWidgets(
      'a refusal shows the host message in place of the description',
      (t) async {
        host.handlers['settings/mutate'] = (_) =>
            throw RemoteException('settings/rejected', 'read-only profile');
        await t.runAsync(() async {
          await t.pumpWidget(row());
          await flush(8);
        });
        await t.pump();
        await t.tap(find.byKey(const ValueKey<String>('permission-selector')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('option-workspace-write')));
        await t.pumpAndSettle();
        await t.runAsync(() => flush(6));
        await t.pump();
        expect(find.text('read-only profile'), findsOneWidget);
        expect(
          find.text('Choose the default permission mode for new sessions'),
          findsNothing,
        );
      },
    );

    testWidgets('while loading the pill reads Loading and is inert', (t) async {
      final gate = Completer<void>();
      host.handlers['permissionPresets/catalog'] = (_) async {
        await gate.future;
        return catalogJson();
      };
      await t.runAsync(() => catalog.dispose());
      catalog = PermissionCatalogDirectory(host.remotes);
      defaults = PermissionDefaultController(
        mirror: forms.mirror,
        remotes: host.remotes,
        catalog: catalog,
      );
      await t.runAsync(() async {
        await t.pumpWidget(row());
        await flush(4);
      });
      await t.pump();
      expect(find.text('Loading'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('permission-selector')));
      await t.pump();
      expect(find.byKey(const ValueKey('option-sheet')), findsNothing);
      gate.complete();
      await t.runAsync(() => flush(8));
      await t.pump();
      expect(find.text('Read Only'), findsOneWidget);
    });

    testWidgets('a read-only host disables the pill', (t) async {
      host.handlers['settings/describe'] = (_) =>
          describeValue([permissionView(preset: 'read-only')], writable: false);
      await forms.mirror.load();
      await t.runAsync(() async {
        await t.pumpWidget(row());
        await flush(8);
      });
      await t.pump();
      await t.tap(find.byKey(const ValueKey<String>('permission-selector')));
      await t.pump();
      expect(find.byKey(const ValueKey('option-sheet')), findsNothing);
    });

    testWidgets('renders nothing when the host serves no permission settings', (
      t,
    ) async {
      served = false;
      await forms.mirror.load();
      await t.runAsync(() async {
        await t.pumpWidget(row());
        await flush(8);
      });
      await t.pump();
      expect(find.text('Permission'), findsNothing);
    });

    testWidgets('Chinese copy comes from the generated dictionary', (t) async {
      i18n = const DshI18n(DshLocale.zh);
      await t.runAsync(() async {
        await t.pumpWidget(row());
        await flush(8);
      });
      await t.pump();
      expect(find.text('权限'), findsOneWidget);
      expect(find.text('选择新会话的默认权限模式'), findsOneWidget);
      expect(find.text('仅可查看'), findsOneWidget);
    });

    testWidgets('is the first General row', (t) async {
      final feature = registerPermissionPresetsFeature(
        slots,
        remotes: host.remotes,
        forms: forms,
        i18n: () => i18n,
      );
      addTearDown(feature.dispose);
      expect(slots.entries(DshSlots.settingsGeneralItem).single.order, -20);
    });
  });

  group('composer control', () {
    late SlotRegistry slots;
    late SessionOwner owner;
    late PermissionPresetsFeature feature;
    var i18n = const DshI18n(DshLocale.en);

    setUp(() {
      i18n = const DshI18n(DshLocale.en);
      slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      feature = registerPermissionPresetsFeature(
        slots,
        remotes: host.remotes,
        forms: forms,
        i18n: () => i18n,
      );
      owner = testSessionOwner('s1');
    });

    tearDown(() => feature.dispose());

    void project(String? value, [int seq = 1]) {
      if (value == null) return;
      owner.session.projections.apply('permissions', {
        'currentValue': value,
      }, seq);
    }

    Widget seat() => dshTestApp(
      Align(
        alignment: Alignment.centerLeft,
        child: slots.renderSingle(
          DshSlots.conversationInputPermission.typed<SessionOwner, Widget>(),
          owner,
        )!,
      ),
      size: const Size(390, 600),
    );

    Future<void> settleCatalog(WidgetTester t) async {
      await t.runAsync(() => flush(8));
      await t.pump();
    }

    testWidgets('is hidden until the session has a permissions projection', (
      t,
    ) async {
      await t.pumpWidget(seat());
      await settleCatalog(t);
      expect(find.byKey(const ValueKey('permission-chip')), findsNothing);
      project('workspace-write');
      await t.pump();
      expect(find.byKey(const ValueKey('permission-chip')), findsOneWidget);
      expect(find.text('Workspace Write'), findsOneWidget);
    });

    testWidgets('is hidden while the catalog is unavailable', (t) async {
      host.handlers['permissionPresets/catalog'] = (_) =>
          throw RemoteException('gateway/internal', 'down');
      host.emit('permission-presets/catalog-changed');
      project('workspace-write');
      await t.pumpWidget(seat());
      await settleCatalog(t);
      expect(find.byKey(const ValueKey('permission-chip')), findsNothing);
    });

    testWidgets('the chip announces the mode and lists every preset', (
      t,
    ) async {
      project('read-only');
      await t.pumpWidget(seat());
      await settleCatalog(t);
      expect(
        find.bySemanticsLabel('Access mode, current: Read Only'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('permission-chip')));
      await t.pumpAndSettle();
      expect(find.text('Write inside the workspace.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('option-danger-full-access')),
        findsOneWidget,
      );
    });

    testWidgets('a pick submits the /permission command line', (t) async {
      host.handlers['commands/execute'] = (args) => {
        'commandId': 'c1',
        'result': {'kind': 'success', 'text': 'preset workspace-write'},
      };
      project('read-only');
      await t.pumpWidget(seat());
      await settleCatalog(t);
      await t.tap(find.byKey(const ValueKey('permission-chip')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('option-workspace-write')));
      await t.pumpAndSettle();
      await t.runAsync(() => flush(6));
      final call = host.callsTo('commands/execute').single;
      expect(call.args, {
        'agentId': 's1',
        'line': '/permission workspace-write',
        'submittedAttachments': <Object?>[],
      });
      // The chip keeps the projection's value until the host confirms it.
      project('workspace-write', 2);
      await t.pump();
      expect(find.text('Workspace Write'), findsOneWidget);
    });

    testWidgets('Full access and Auto review each need their acknowledgement', (
      t,
    ) async {
      host.handlers['permissionPresets/catalog'] = (_) =>
          catalogJson(auto: true);
      host.emit('permission-presets/catalog-changed');
      host.handlers['commands/execute'] = (_) => {
        'commandId': 'c1',
        'result': {'kind': 'success'},
      };
      project('read-only');
      await t.pumpWidget(seat());
      await settleCatalog(t);
      await t.tap(find.byKey(const ValueKey('permission-chip')));
      await t.pumpAndSettle();
      expect(find.text('EXP'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('option-auto')));
      await t.pumpAndSettle();
      expect(find.text('Enable Auto review (experimental)?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('risk-acknowledge')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('risk-confirm')));
      await t.pumpAndSettle();
      await t.runAsync(() => flush(6));
      expect(
        host.callsTo('commands/execute').single.args['line'],
        '/permission auto',
      );
    });

    testWidgets('a command the host does not know leaves the chip unchanged', (
      t,
    ) async {
      host.handlers['commands/execute'] = (_) => null;
      project('read-only');
      await t.pumpWidget(seat());
      await settleCatalog(t);
      await t.tap(find.byKey(const ValueKey('permission-chip')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('option-workspace-write')));
      await t.pumpAndSettle();
      await t.runAsync(() => flush(6));
      await t.pump();
      expect(find.text('Read Only'), findsOneWidget);
    });

    testWidgets('a custom value shows as is', (t) async {
      project('custom');
      await t.pumpWidget(seat());
      await settleCatalog(t);
      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('Chinese copy comes from the generated dictionary', (t) async {
      i18n = const DshI18n(DshLocale.zh);
      project('workspace-write');
      await t.pumpWidget(seat());
      await settleCatalog(t);
      expect(find.text('工作区内修改'), findsOneWidget);
      expect(find.bySemanticsLabel('访问模式，当前：工作区内修改'), findsOneWidget);
    });
  });
}
