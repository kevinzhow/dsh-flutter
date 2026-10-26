import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'parity/helpers/models_settings_fixture.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'root settings wire, accepted coding switch, staged numeric mutation and provider retry',
    (t) async {
      t.view.physicalSize = const Size(1200, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final backend = FakeBackend();
      final fixture = SyntheticModelSettings(backend.host, welcome: false);
      final controller = makeController(backend);
      await t.pumpWidget(WhaleeApp(controller: controller));
      await t.runAsync(() => controller.pair('http://host:18686/?token=abc'));
      await settle(t);
      controller.openSettings(section: 'general');
      await settle(t);
      final coding = find
          .byType(DshSwitch)
          .evaluate()
          .where(
            (e) =>
                (e.widget as DshSwitch).label ==
                controller.i18n.t('settings', 'developerTools.title'),
          );
      expect(coding, hasLength(1));
      await t.ensureVisible(find.byWidget(coding.single.widget));
      await t.tap(find.byWidget(coding.single.widget));
      await settle(t);
      expect(controller.developerTools.enabled.value, true);
      expect(fixture.value('ui-settings')['enabled'], true);
      Navigator.of(controller.navigatorKey.currentContext!).pop();
      await settle(t);
      controller.openSettings(section: 'plugins');
      await settle(t);
      final numeric = find.byKey(
        DshSettingsValueField.inputKey('maxParallelToolCalls'),
      );
      await t.ensureVisible(numeric);
      await t.enterText(numeric, '6');
      await settle(t);
      expect(fixture.value('agent-loop')['maxParallelToolCalls'], 2);
      final save = find.byKey(DshSettingsForm.saveKey).first;
      await t.ensureVisible(save);
      await t.tap(save);
      await settle(t);
      expect(fixture.value('agent-loop')['maxParallelToolCalls'], 6);
      Navigator.of(controller.navigatorKey.currentContext!).pop();
      await settle(t);
      controller.openSettings(section: 'models');
      await settle(t);
      await t.tap(find.byKey(const ValueKey('edit-provider-openai')));
      await settle(t);
      await t.enterText(
        find.byKey(const ValueKey('provider-api-key')),
        'synthetic-key',
      );
      await settle(t);
      await t.tap(find.byKey(const ValueKey('provider-save')));
      await settle(t);
      expect(find.text('Synthetic key save refused; retry.'), findsOneWidget);
      expect(fixture.configured, isEmpty);
      await t.tap(find.byKey(const ValueKey('provider-save')));
      await settle(t);
      expect(fixture.configured, contains('OPENAI_API_KEY'));
      expect(
        find.text(controller.i18n.t('settings.models', 'credentialConfigured')),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await t.runAsync(backend.host.close);
    },
  );
}
