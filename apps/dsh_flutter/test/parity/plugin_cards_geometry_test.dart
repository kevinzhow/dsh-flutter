import 'dart:io';

import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cases/plugin_cards.dart';
import 'helpers/plugin_card_fixture.dart';

void main() {
  late Directory output;
  late List<ParityFontFace> fonts;
  setUpAll(() async {
    output = Directory.systemTemp.createTempSync('plugin_card_geometry_');
    fonts = await loadParityFonts(findParityFontsManifest());
  });
  tearDownAll(() => output.deleteSync(recursive: true));

  for (final sample in [
    (id: 'default', state: 'press', theme: 'light', locale: 'en', density: 1.0),
    (id: 'default', state: 'focus', theme: 'dark', locale: 'en', density: 1.0),
    (
      id: 'no-description',
      state: 'idle',
      theme: 'light',
      locale: 'en',
      density: 1.0,
    ),
    (
      id: 'long-tags',
      state: 'idle',
      theme: 'dark',
      locale: 'zh-CN',
      density: 2.625,
    ),
    (
      id: 'metadata-error',
      state: 'idle',
      theme: 'light',
      locale: 'en',
      density: 1.0,
    ),
    (
      id: 'image-failed',
      state: 'idle',
      theme: 'dark',
      locale: 'en',
      density: 1.0,
    ),
  ]) {
    testWidgets('actual Card inner measurement ${sample.id}/${sample.state}', (
      t,
    ) async {
      final scenario = pluginCardScenarios[sample.id]!;
      final package = scenario['package'] as Map;
      final key =
          'components.plugin-card.geometry-${sample.id}-${sample.state}.${sample.theme}';
      Rect? observedBeforeScreenshot;
      final base = pluginCardCases['plugin-cards.manager']!;
      final metadata = await captureParityCase(
        t,
        entry: {
          'key': key,
          'case': {
            'id': key,
            'kind': 'plugin-cards.manager',
            'theme': sample.theme,
            'locale': sample.locale,
            'viewport': {
              'width': 390,
              'height': 900,
              'density': sample.density,
            },
            'capture': {'crop': 'viewport'},
          },
          'variant': {
            'id': 'default',
            'name': sample.state,
            'props': {'scenarioId': sample.id, 'scenario': scenario},
            'interactions': [
              if (sample.state != 'idle')
                {
                  'type': sample.state == 'focus'
                      ? 'focus-by-tab'
                      : sample.state,
                  'target': 'plugin-card-${package['name']}',
                },
            ],
          },
        },
        mapping: ParityCase(
          widgets: base.widgets,
          build: base.build,
          framed: base.framed,
          geometryProbe: base.geometryProbe,
          notes: base.notes,
          settle: base.settle,
          interact: (tester, ctx) async {
            observedBeforeScreenshot = tester.getRect(
              find.byKey(ValueKey('plugin-card-${package['name']}')),
            );
          },
        ),
        fixtures: const {},
        outputDir: output,
        runInfo: const {},
        fonts: fonts,
        framed: base.framed,
      );
      final geometry = metadata['componentGeometry'] as Map;
      expect(geometry['schema'], 'dsh-plugin-card-geometry/1');
      expect(geometry['status'], 'measured');
      expect(geometry['cardCount'], 1);
      final actual = observedBeforeScreenshot!;
      expect((geometry['card'] as Map)['bounds'], [
        actual.left,
        actual.top,
        actual.width,
        actual.height,
      ]);
      expect(
        (geometry['innerCard'] as Map)['bounds'],
        (geometry['card'] as Map)['bounds'],
      );
      expect(
        (geometry['action'] as Map)['bounds'],
        (geometry['card'] as Map)['bounds'],
      );
      expect((geometry['coordinateBasis'] as Map)['rounding'], 'none');
      expect(
        (geometry['coordinateBasis'] as Map)['devicePixelRatio'],
        sample.density,
      );
      expect(
        (geometry['switch'] as Map)['checked'],
        package['enabled'].toString(),
      );
      expect((geometry['switch'] as Map)['disabled'], false);
      expect((geometry['title'] as Map)['text'], isNotEmpty);
      expect((geometry['title'] as Map)['widgetType'], 'DshChromeText');
      expect(
        (geometry['title'] as Map)['measurement'],
        contains('outer render/line box'),
      );
      expect(
        (((geometry['title'] as Map)['bounds'] as List)[2] as num) <
            (((geometry['action'] as Map)['bounds'] as List)[2] as num),
        isTrue,
      );
      expect(
        (geometry['geometrySemantics'] as Map)['action'],
        contains('whole-card pseudo-element'),
      );
      expect(
        (geometry['geometrySemantics'] as Map)['glyphInkBounds'],
        'not sampled',
      );
      expect((geometry['artworkFrame'] as Map)['bounds'], hasLength(4));
      if (sample.state == 'press') {
        // The actual release opens detail after the PNG and probe. Geometry
        // still describes the list card, not that later route/view.
        expect(find.byType(DshPluginCard), findsNothing);
        expect(geometry['focusedTitle'], isTrue);
      }
      if (sample.state == 'focus') {
        expect(geometry['focusedTitle'], isTrue);
        expect(geometry['titleFocusVisible'], isTrue);
        expect((geometry['titleOutline'] as Map)['bounds'], hasLength(4));
      }
      if (sample.id == 'no-description') {
        expect(geometry['description'], isNull);
        expect(geometry['metadataError'], isNull);
        expect(geometry['tags'], isEmpty);
      }
      if (sample.id == 'long-tags') {
        final tags = geometry['tags'] as List;
        expect(tags, hasLength(4));
        expect(tags.every((tag) => (tag as Map)['bounds'] is List), isTrue);
        final width =
            ((geometry['artworkFrame'] as Map)['bounds'] as List)[2] as double;
        expect(width, isNot(width.roundToDouble()));
      }
      if (sample.id == 'metadata-error') {
        expect(
          (geometry['metadataError'] as Map)['text'],
          contains('Synthetic metadata diagnostic\nwith a second line'),
        );
      }
      if (sample.id == 'image-failed') {
        expect(geometry['imageConfigured'], isTrue);
        expect(
          geometry['artworkKind'],
          'native default/fallback artwork widget',
        );
        expect((geometry['artwork'] as Map)['bounds'], hasLength(4));
      }
    });
  }
}
