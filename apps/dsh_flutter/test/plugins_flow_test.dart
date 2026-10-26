import 'package:dsh_flutter/src/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'parity/helpers/models_settings_fixture.dart';
import 'parity/helpers/plugins_preview_fixture.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  testWidgets(
    'production Plugins panel and read-only Settings inventory use the current Host after pairing',
    (t) async {
      t.view.physicalSize = const Size(1200, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final backend = FakeBackend();
      SyntheticModelSettings(backend.host, welcome: false);
      final synthetic = SyntheticPluginsPreview();
      for (final entry in synthetic.host.handlers.entries) {
        backend.host.handlers[entry.key] = entry.value;
      }
      backend.host.handlers['schedule/catalog'] = (_) => <Object?>[];
      backend.host.handlers['skills/list'] = (_) => {'skills': <Object?>[]};
      final controller = makeController(backend);
      await t.pumpWidget(WhaleeApp(controller: controller));
      await t.runAsync(
        () => controller.pair('http://host:18686/?token=synthetic'),
      );
      await settle(t);
      controller.layout.controller.selectPanel('plugins');
      await settle(t);
      expect(find.text('Synthetic preview bundle'), findsOneWidget);
      expect(backend.host.callsTo('pluginManager/listBundles'), isNotEmpty);
      controller.openSettings(section: 'plugins');
      await settle(t);
      expect(
        find.text(controller.i18n.t('settings.pluginInventory', 'globalTitle')),
        findsOneWidget,
      );
      expect(find.text('@synthetic/reader'), findsWidgets);
      expect(backend.host.callsTo('pluginManager/setBundleEnabled'), isEmpty);
      expect(backend.host.callsTo('pluginManager/setPluginEnabled'), isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await t.runAsync(() async {
        controller.dispose();
        await synthetic.dispose();
      });
    },
  );
}
