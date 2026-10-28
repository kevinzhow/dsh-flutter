import 'dart:io';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cases/plugin_cards.dart';
import 'helpers/plugin_card_fixture.dart';

void main() {
  test('compiled scenario data has exactly the source plan branches', () {
    expect(pluginCardScenarios.keys, {
      'default',
      'no-description',
      'long-tags',
      'problem-enabled',
      'metadata-error',
      'busy',
      'read-only',
      'error-disabled',
      'missing-recovery',
      'refused-toggle',
      'image-failed',
    });
    expect(
      (pluginCardScenarios['image-failed']!['package'] as Map)['meta'],
      containsPair('icon', 'data:image/png;base64,AAAA'),
    );
  });

  for (final id in pluginCardScenarios.keys) {
    testWidgets('actual manager scenario $id exposes source state', (t) async {
      t.view.physicalSize = const Size(390, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      SyntheticPluginCardFixture? fixture;
      final scenario = pluginCardScenarios[id]!;
      await t.pumpWidget(
        dshTestApp(
          PluginCardCaptureSurface(
            scenario: scenario,
            i18n: const DshI18n(DshLocale.en),
            onFixture: (value) => fixture = value,
          ),
        ),
      );
      await t.pumpAndSettle();
      final actual = fixture!;
      final expected = scenario['expected'] as Map;
      final card = find.byKey(ValueKey('plugin-card-${actual.packageName}'));
      expect(card, findsOneWidget);
      final control = find.byKey(
        ValueKey('plugin-switch-${actual.packageName}'),
      );
      final switcher = t.widget<DshSwitch>(control);
      expect(switcher.value, expected['enabled']);
      expect(switcher.onChanged == null, expected['locked']);
      const i18n = DshI18n(DshLocale.en);
      for (final key in expected['tagKeys'] as List) {
        expect(
          find.text(i18n.t('pluginManager', key as String)),
          findsOneWidget,
        );
      }
      if (id == 'no-description') {
        expect(t.widget<DshPluginCard>(card).description, isNull);
      }
      if (id == 'metadata-error') {
        expect(
          t.widget<DshPluginCard>(card).metadataError,
          contains('Synthetic metadata diagnostic\nwith a second line'),
        );
      }
      if (expected['locked'] == true || id == 'refused-toggle') {
        await t.tap(control);
        await t.pumpAndSettle();
        expect(actual.attempts, id == 'refused-toggle' ? 1 : 0);
        expect(actual.refusals, id == 'refused-toggle' ? 1 : 0);
        expect(actual.enabled, expected['enabled']);
        expect(find.text(i18n.t('pluginManager', 'backToList')), findsNothing);
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    });
  }

  test('source plan helper remains a single compiled JSON source', () {
    final file = File('test/parity/helpers/plugin_card_fixture.dart');
    final matches = RegExp(
      "const pluginCardScenarioJson = r'''\\n(.*?)\\n''';",
      dotAll: true,
    ).allMatches(file.readAsStringSync());
    expect(matches.length, 1);
    expect(matches.single.group(1)!.trim(), pluginCardScenarioJson.trim());
  });

  for (final brightness in Brightness.values) {
    for (final locale in [DshLocale.en, DshLocale.zh]) {
      for (final width in [390.0, 800.0]) {
        for (final density in [1.0, 2.625]) {
          testWidgets(
            'long localized actual card ${brightness.name}/${locale.name}/$width/$density',
            (t) async {
              t.view.physicalSize = Size(width * density, 900 * density);
              t.view.devicePixelRatio = density;
              addTearDown(t.view.reset);
              await t.pumpWidget(
                dshTestApp(
                  PluginCardCaptureSurface(
                    scenario: pluginCardScenarios['long-tags']!,
                    i18n: DshI18n(locale),
                  ),
                  brightness: brightness,
                ),
              );
              await t.pumpAndSettle();
              final card = t.widget<DshPluginCard>(find.byType(DshPluginCard));
              final metadata =
                  (pluginCardScenarios['long-tags']!['package'] as Map)['meta']
                      as Map;
                expect(card.title, (metadata['title'] as Map)[locale.name]);
              expect(card.tags.length, 4);
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox());
              await t.pumpAndSettle();
            },
          );
        }
      }
    }
  }
}
