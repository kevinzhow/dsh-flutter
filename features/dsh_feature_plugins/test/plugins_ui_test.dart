import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_plugin_market.dart';
import 'package:dsh_feature_plugins/dsh_feature_plugins.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const i18n = DshI18n(DshLocale.en);
Map<String, Object?> response(String application, {List<String>? builds}) => {
  'changed': true,
  'application': application,
  'stage': 'install',
  'target': 'synthetic',
  if (builds != null) 'pendingBuilds': builds,
};
void setup(FakeHost host) {
  host.handlers['pluginInventory/list'] = (_) => {
    'managementAvailable': true,
    'entries': <Object?>[],
  };
  host.handlers['pluginManager/listBundles'] = (_) => [
    {
      'name': 'synthetic',
      'official': false,
      'availability': 'profile',
      'installed': true,
      'enabled': false,
      'optional': false,
      'removable': true,
      'rows': [
        {'rowId': 'row', 'moduleName': 'plugin-module', 'entryId': 'entry'},
      ],
      'overrides': <String>[],
    },
  ];
  host.handlers['pluginManager/listPlugins'] = (_) => [
    {
      'entryId': 'entry',
      'moduleName': 'plugin-module',
      'enabled': true,
      'fiberPhase': 'active',
      'patchId': 'row',
    },
  ];
  host.handlers['pluginManager/registries'] = (_) => {
    'registry': null,
    'resolved': null,
    'fallbackRegistries': <String>[],
  };
  host.handlers['pluginManager/inspect'] = (_) => {
    'status': 'accepted',
    'kind': 'registry',
    'name': 'synthetic-new',
    'bundle': true,
    'registry': null,
  };
}

Future<void> pump(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('market categories use pills only when declarations exist', (
    t,
  ) async {
    const url = 'https://market.example/index.json';
    final host = FakeHost();
    final manager = PluginManagerModel(remotes: host.remotes);
    final model = PluginMarketModel(host.remotes)
      ..status = PluginDiscoverStatus.ready
      ..indexes = const [MarketIndexSummary(url: url, title: 'Market')]
      ..selected = url;
    MarketSearchResult result(Map<String, MarketDeclaration> categories) =>
        MarketSearchResult(
          url: url,
          title: 'Market',
          metadata: MarketIndexMetadata(
            categories: categories,
            labels: const {},
            sortKeys: const {},
          ),
          fetchedAt: 1,
          entries: const [],
          total: 0,
          nextOffset: null,
        );
    void setListing(MarketSearchResult value) {
      model.listing = PluginListing(
        url: url,
        query: const PluginDiscoverQuery(),
        status: PluginListingStatus.ready,
        value: value,
      );
      model.changed.set(model.changed.value + 1);
    }

    final empty = result(const {});
    final populated = result(const {
      'tools': MarketDeclaration(title: 'Tools'),
    });
    host.handlers['pluginMarket/search'] = (_) => populated.toJson();
    setListing(empty);
    await t.pumpWidget(
      dshTestApp(
        SingleChildScrollView(
          child: PluginMarketPage(
            model: model,
            manager: manager,
            i18n: i18n,
            onInstall: () {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(DshPill), findsNothing);
    expect(
      find.bySemanticsLabel(i18n.t('pluginMarket', 'categoriesLabel')),
      findsNothing,
    );
    setListing(populated);
    await t.pumpAndSettle();
    final pills = find.byType(DshPill);
    expect(pills, findsNWidgets(2));
    expect(t.widget<DshPill>(pills.first).pressed, isTrue);
    expect(t.widget<DshPill>(pills.last).pressed, isFalse);
    final group = find
        .ancestor(of: pills.first, matching: find.byType(Wrap))
        .first;
    expect(t.widget<Wrap>(group).spacing, DshPillRecipe.categoryGap);
    await t.tap(find.text('Tools'));
    await t.pumpAndSettle();
    expect(model.listing!.query.category, 'tools');
    expect(t.widget<DshPill>(find.byType(DshPill).last).pressed, isTrue);
    await t.tap(find.text(i18n.t('pluginMarket', 'allCategories')));
    await t.pumpAndSettle();
    expect(model.listing!.query.category, isNull);
    await t.pumpWidget(const SizedBox());
    await t.runAsync(() async {
      await manager.dispose();
      await model.dispose();
      await host.close();
    });
  });
  testWidgets(
    'details toggles exact row, uninstall waits for confirmation; lost install remains inspectable',
    (t) async {
      final host = FakeHost();
      setup(host);
      final model = PluginManagerModel(
        remotes: host.remotes,
        newId: () => 'req',
      );
      final market = PluginMarketModel(host.remotes);
      final slots = SlotRegistry();
      for (final slot in DshSlots.all) {
        slots.declare(slot);
      }
      host.handlers['pluginManager/setPluginEnabled'] = (_) =>
          response('restart-required');
      host.handlers['pluginManager/removeBundle'] = (_) => response('applied');
      await t.pumpWidget(
        dshTestApp(
          PluginManagerPage(
            model: model,
            market: market,
            slots: slots,
            i18n: i18n,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(
        find.bySemanticsLabel(
          i18n.t('pluginManager', 'openDetail', params: {'name': 'synthetic'}),
        ),
      );
      await pump(t);
      await t.tap(
        find.bySemanticsLabel(
          i18n.t('pluginManager', 'partToggle', params: {'name': 'row'}),
        ),
      );
      await t.pumpAndSettle();
      expect(host.callsTo('pluginManager/setPluginEnabled').single.args, {
        'id': 'entry',
        'enabled': false,
      });
      final remove = find.text(i18n.t('pluginManager', 'uninstall'));
      await t.ensureVisible(remove);
      await t.tap(remove);
      await t.pumpAndSettle();
      expect(host.callsTo('pluginManager/removeBundle'), isEmpty);
      await t.tap(find.text(i18n.t('pluginManager', 'confirmUninstall')).last);
      await t.pumpAndSettle();
      expect(host.callsTo('pluginManager/removeBundle').single.args, {
        'name': 'synthetic',
      });
      await t.tap(find.text(i18n.t('pluginManager', 'backToList')));
      await pump(t);
      await t.tap(find.text(i18n.t('pluginManager', 'addPlugin')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('plugin-install-spec')),
        'synthetic-new',
      );
      await pump(t);
      host.handlers['pluginManager/installBundle'] = (_) =>
          throw RemoteException('transport/lost', 'lost');
      host.handlers['pluginManager/waitForInstall'] = (_) => null;
      await t.tap(find.text(i18n.t('pluginManager', 'installRun')));
      await t.pumpAndSettle();
      expect(
        find.text(i18n.t('pluginManager', 'installUnknownTitle')),
        findsOneWidget,
      );
      expect(model.installer.phase, PluginInstallPhase.unknown);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await pump(t);
      await t.runAsync(() async {
        await model.dispose();
        await market.dispose();
        await host.close();
      });
    },
  );
  testWidgets(
    'installer requires second explicit approval before native build scripts are sent',
    (t) async {
      final host = FakeHost();
      setup(host);
      final model = PluginManagerModel(remotes: host.remotes);
      final market = PluginMarketModel(host.remotes);
      final slots = SlotRegistry();
      for (final slot in DshSlots.all) {
        slots.declare(slot);
      }
      var calls = 0;
      host.handlers['pluginManager/installBundle'] = (_) => ++calls == 1
          ? response('failed', builds: ['synthetic-addon'])
          : response('applied');
      await t.pumpWidget(
        dshTestApp(
          PluginManagerPage(
            model: model,
            market: market,
            slots: slots,
            i18n: i18n,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text(i18n.t('pluginManager', 'addPlugin')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('plugin-install-spec')),
        'synthetic-new',
      );
      await pump(t);
      await t.tap(find.text(i18n.t('pluginManager', 'installRun')));
      await t.pumpAndSettle();
      final approval = find.text(
        i18n.t('pluginManager', 'installApproveAndRetry'),
      );
      await t.ensureVisible(approval);
      await t.tap(approval);
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('synthetic-addon'), findsOneWidget);
      await t.tap(approval.last);
      await t.pumpAndSettle();
      expect(calls, 2);
      expect(
        (host.callsTo('pluginManager/installBundle').last.args['options']
            as Map)['approvedBuilds'],
        ['synthetic-addon'],
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await pump(t);
      await t.runAsync(() async {
        await model.dispose();
        await market.dispose();
        await host.close();
      });
    },
  );
  testWidgets(
    'read-only inventory works without management or an agent preset roster',
    (t) async {
      final host = FakeHost();
      host.handlers['pluginInventory/list'] = (_) => {
        'entries': [
          {
            'entryId': 'entry',
            'moduleName': 'synthetic-module',
            'enabled': false,
            'fiberPhase': null,
          },
        ],
      };
      await t.pumpWidget(
        dshTestApp(PluginInventorySection(remotes: host.remotes, i18n: i18n)),
      );
      await t.pumpAndSettle();
      expect(find.text('synthetic-module'), findsWidgets);
      expect(host.calls, hasLength(1));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await pump(t);
      await t.runAsync(host.close);
    },
  );
}
