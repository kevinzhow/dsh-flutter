import 'package:dsh_feature_plugins/dsh_feature_plugins.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plugins_ui_test.dart' show setup;

const _i18n = DshI18n(DshLocale.en);
String _t(String key, [Map<String, Object?> params = const {}]) =>
    _i18n.t('pluginManager', key, params: params);

Future<FakeHost> _show(
  WidgetTester t, {
  String name = 'synthetic',
  bool enabled = false,
  Map<String, Object?>? error,
  Map<String, Object?>? meta,
  Map<String, Object?> bundlePatch = const {},
}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final host = FakeHost();
  setup(host);
  host.handlers['pluginManager/listBundles'] = (_) => [
    {
      'name': name,
      'official': false,
      'availability': 'profile',
      'installed': true,
      'enabled': enabled,
      'optional': false,
      'removable': true,
      if (error != null) 'error': error,
      if (meta != null) 'meta': meta,
      'rows': <Object?>[],
      'overrides': <Object?>[],
      ...bundlePatch,
    },
  ];
  final model = PluginManagerModel(remotes: host.remotes);
  final market = PluginMarketModel(host.remotes);
  final slots = SlotRegistry();
  for (final slot in DshSlots.all) {
    slots.declare(slot);
  }
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    await t.runAsync(() async {
      await model.dispose();
      await market.dispose();
      await host.close();
    });
  });
  await t.pumpWidget(
    dshTestApp(
      PluginManagerPage(
        model: model,
        market: market,
        slots: slots,
        i18n: _i18n,
      ),
    ),
  );
  await t.pumpAndSettle();
  return host;
}

void main() {
  testWidgets('ordinary page slots preserve the pre-card layout', (t) async {
    await _show(
      t,
      meta: {'title': 'Synthetic title', 'description': 'Description'},
    );
    List<double> rect(Finder finder) {
      final r = t.getRect(finder);
      return [r.left, r.top, r.width, r.height];
    }

    final geometry = <String, List<double>>{
      'heading': rect(find.text(_t('title'))),
      'refresh': rect(find.byKey(const ValueKey('plugin-refresh'))),
      'tabs': rect(find.byKey(const ValueKey('plugin-manager-tabs'))),
      'group': rect(find.text(_t('bundlesTitle'))),
    };
    await t.tap(
      find.bySemanticsLabel(_t('openDetail', {'name': 'Synthetic title'})),
    );
    await t.pumpAndSettle();
    geometry.addAll({
      'back': rect(find.widgetWithText(DshButton, _t('backToList'))),
      'detailTitle': rect(find.text('Synthetic title')),
      'detailDescription': rect(find.text('Description')),
      'detailSwitch': rect(find.byType(DshSwitch)),
    });
    // Measured by restoring cc9c717c's manager source in this isolated worktree
    // before the migration, with its log retained separately.
    expect(geometry, {
      'heading': [24.0, 28.0, 140.0, 28.0],
      'refresh': [24.0, 118.0, 28.0, 28.0],
      'tabs': [24.0, 164.0, 248.0, 42.0],
      'group': [24.0, 238.0, 342.0, 22.0],
      'back': [24.0, 180.0, 238.0, 36.0],
      'detailTitle': [24.0, 232.0, 342.0, 28.0],
      'detailDescription': [24.0, 272.0, 342.0, 20.0],
      'detailSwitch': [24.0, 308.0, 36.0, 20.0],
    });
  });

  testWidgets(
    'an off errored package cannot enable or open through its switch',
    (t) async {
      final host = await _show(
        t,
        error: {'code': 'operation-error', 'diagnostic': 'Synthetic refusal'},
      );
      var changes = 0;
      host.handlers['pluginManager/setBundleEnabled'] = (_) {
        changes++;
        return <String, Object?>{};
      };
      final switcher = find.byKey(const ValueKey('plugin-switch-synthetic'));
      expect(t.widget<DshSwitch>(switcher).onChanged, isNull);
      await t.tap(switcher);
      await t.pumpAndSettle();
      expect(changes, 0);
      expect(find.text(_t('backToList')), findsNothing);
      expect(find.text(_t('statusProblem')), findsOneWidget);
    },
  );

  testWidgets(
    'metadata errors retain their own diagnostic and permit enabling',
    (t) async {
      await _show(
        t,
        meta: {
          'title': 'Synthetic title',
          'error': 'Synthetic metadata diagnostic',
        },
      );
      expect(
        find.text(
          _t('metadataError', {'error': 'Synthetic metadata diagnostic'}),
        ),
        findsOneWidget,
      );
      expect(
        t
            .widget<DshSwitch>(
              find.byKey(const ValueKey('plugin-switch-synthetic')),
            )
            .onChanged,
        isNotNull,
      );
    },
  );

  testWidgets('loaded card bleeds while heading alignment stays unchanged', (
    t,
  ) async {
    await _show(t);
    final headingX = t.getTopLeft(find.text(_t('title'))).dx;
    expect(headingX, 24);
    expect(
      t.getTopLeft(find.byKey(const ValueKey('plugin-manager-tabs'))).dx,
      24,
    );
    final action = find.bySemanticsLabel(
      _t('openDetail', {'name': 'synthetic'}),
    );
    final bounds = t.getRect(action);
    expect(bounds.left, headingX - 8);
    expect(bounds.right, 390 - headingX + 8);
    await t.tapAt(Offset(bounds.left + 2, bounds.center.dy));
    await t.pumpAndSettle();
    expect(find.text(_t('backToList')), findsOneWidget);
  });

  testWidgets('experimental status wraps naturally beside a long title', (
    t,
  ) async {
    const name = '@deepseek-ai/dsh-experimental-synthetic';
    const title = 'A deliberately long synthetic plugin title with status';
    await _show(
      t,
      name: name,
      meta: {'title': title, 'description': 'Description'},
    );
    expect(find.text(_t('statusBeta')), findsOneWidget);
    final action = find.bySemanticsLabel(_t('openDetail', {'name': title}));
    // The source card grows beyond its icon-driven base height when the title
    // and tag need separate rows; its head has no fixed height.
    expect(t.getSize(action).height, greaterThan(66));
  });

  for (final scenario in [
    (
      name: 'read-only',
      enabled: true,
      patch: <String, Object?>{'readOnlyReason': 'management-required'},
      locked: true,
    ),
    (
      name: 'enabled problem',
      enabled: true,
      patch: <String, Object?>{
        'error': {'code': 'operation-error'},
      },
      locked: false,
    ),
    (
      name: 'missing recovery',
      enabled: false,
      patch: <String, Object?>{
        'availability': 'missing',
        'error': {'code': 'operation-error'},
        'installTarget': {'spec': 'synthetic@2', 'version': '2.0.0'},
      },
      locked: false,
    ),
  ]) {
    testWidgets('source switch predicate: ${scenario.name}', (t) async {
      await _show(t, enabled: scenario.enabled, bundlePatch: scenario.patch);
      expect(
        t
                .widget<DshSwitch>(
                  find.byKey(const ValueKey('plugin-switch-synthetic')),
                )
                .onChanged ==
            null,
        scenario.locked,
      );
    });
  }

  for (final scenario in [
    (
      name: 'new version',
      source: 'synthetic@1',
      target: 'synthetic@2',
      version: '2',
      availability: 'profile',
      removable: true,
      expected: true,
    ),
    (
      name: 'same version',
      source: 'synthetic@1',
      target: 'synthetic@1',
      version: '1',
      availability: 'profile',
      removable: true,
      expected: false,
    ),
    (
      name: 'changed link',
      source: 'link:old',
      target: 'link:new',
      version: '1',
      availability: 'profile',
      removable: true,
      expected: true,
    ),
    (
      name: 'installation',
      source: 'synthetic@1',
      target: 'synthetic@2',
      version: '2',
      availability: 'installation',
      removable: true,
      expected: false,
    ),
    (
      name: 'not removable',
      source: 'synthetic@1',
      target: 'synthetic@2',
      version: '2',
      availability: 'profile',
      removable: false,
      expected: false,
    ),
  ]) {
    testWidgets('source update tag: ${scenario.name}', (t) async {
      await _show(
        t,
        bundlePatch: {
          'version': '1',
          'source': scenario.source,
          'availability': scenario.availability,
          'removable': scenario.removable,
          'installTarget': {
            'spec': scenario.target,
            'version': scenario.version,
          },
        },
      );
      expect(
        find.text(_t('statusUpdateAvailable')),
        scenario.expected ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets(
    'a refused toggle retains accepted state and never opens the card',
    (t) async {
      final host = await _show(t);
      var changes = 0;
      host.handlers['pluginManager/setBundleEnabled'] = (_) {
        changes++;
        return {
          'changed': false,
          'application': 'failed',
          'stage': 'enable',
          'target': 'synthetic',
          'error': {
            'code': 'operation-error',
            'diagnostic': 'Synthetic refusal',
          },
        };
      };
      await t.tap(find.byKey(const ValueKey('plugin-switch-synthetic')));
      await t.pumpAndSettle();
      expect(changes, 1);
      expect(
        t
            .widget<DshSwitch>(
              find.byKey(const ValueKey('plugin-switch-synthetic')),
            )
            .value,
        isFalse,
      );
      expect(find.text(_t('backToList')), findsNothing);
    },
  );
}
