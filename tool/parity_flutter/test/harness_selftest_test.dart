// Always-on self-test of the Flutter provider (runs with a plain `flutter test`, no PARITY_PLAN).
// It proves the harness before anything is compared with the React side: the theme a capture shows is
// the one the case asked for, crops land on the same device pixels Playwright uses, and a real
// capture writes the provider output contract with the pinned fonts.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart' show DshPixelModel, dshPixelModel;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'parity/case_map.dart';

void main() {
  group('theme self-test', () {
    test('resolveParityTheme honours the requested mode, not the platform', () {
      expect(resolveParityTheme('light').brightness, Brightness.light);
      expect(resolveParityTheme('dark').brightness, Brightness.dark);
      expect(
        resolveParityTheme('dark').bgBase,
        isNot(resolveParityTheme('light').bgBase),
      );
      expect(() => resolveParityTheme('sepia'), throwsArgumentError);
    });

    test('verifyCapturedTheme passes the requested theme', () {
      final dark = resolveParityTheme('dark');
      verifyCapturedTheme(
        requested: 'dark',
        inTree: dark,
        expected: dark,
        framePixel: dark.bgBase,
      );
    });

    test('verifyCapturedTheme names the mismatch', () {
      final light = resolveParityTheme('light');
      final dark = resolveParityTheme('dark');
      expect(
        () => verifyCapturedTheme(
          requested: 'dark',
          inTree: light,
          expected: dark,
          framePixel: null,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('requested dark'),
          ),
        ),
      );
      expect(
        () => verifyCapturedTheme(
          requested: 'dark',
          inTree: dark,
          expected: dark,
          framePixel: light.bgBase,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('frame pixel'),
          ),
        ),
      );
      expect(
        () => verifyCapturedTheme(
          requested: 'dark',
          inTree: null,
          expected: dark,
          framePixel: null,
        ),
        throwsStateError,
      );
    });
  });

  test('enclosingPixelRect: CSS px for an emulated reference, device px for a native one', () {
    addTearDown(() => dshPixelModel = DshPixelModel.native);
    dshPixelModel = DshPixelModel.emulated;
    expect(
      enclosingPixelRect(const Rect.fromLTRB(10.4, 296.5, 50.2, 320.1), 3),
      const Rect.fromLTRB(30, 888, 153, 963),
    );
    expect(
      enclosingPixelRect(const Rect.fromLTWH(0, 0, 420, 68), 1),
      const Rect.fromLTWH(0, 0, 420, 68),
    );
    dshPixelModel = DshPixelModel.native;
    // 10.4 * 3 = 31.2 floors to 31, 50.2 * 3 = 150.6 ceils to 151.
    expect(
      enclosingPixelRect(const Rect.fromLTRB(10.4, 296.5, 50.2, 320.1), 3),
      const Rect.fromLTRB(31, 889, 151, 961),
    );
    // 420 * 2.625 = 1102.5 is captured as 1103 device px.
    expect(
      enclosingPixelRect(const Rect.fromLTWH(0, 0, 420, 68), 2.625),
      const Rect.fromLTWH(0, 0, 1103, 179),
    );
  });

  test('ParityLayout reads the shared layout prop', () {
    final layout = ParityLayout.fromJson({
      'direction': 'column',
      'gap': 8,
      'align': 'stretch',
    });
    expect(layout.direction, Axis.vertical);
    expect(layout.gap, 8);
    expect(layout.align, CrossAxisAlignment.stretch);
    expect(ParityLayout.fromJson(null).direction, Axis.horizontal);
  });

  test('the case map maps the core button kind and reasons every gap', () {
    expect(parityCases.keys, contains('button.items'));
    for (final u in parityUncovered.values) {
      expect(u.reason, isNotEmpty);
    }
  });

  group('capture smoke', () {
    late Directory dir;
    late List<ParityFontFace> fonts;
    setUpAll(() async {
      dir = Directory.systemTemp.createTempSync('dsh_parity_selftest');
      fonts = await loadParityFonts(findParityFontsManifest());
    });
    tearDownAll(() => dir.deleteSync(recursive: true));

    for (final (theme, density) in [('light', 1), ('dark', 2)]) {
      testWidgets('captures a button row in $theme at ${density}x', (t) async {
        final entry = <String, dynamic>{
          'key': 'components.button.selftest.row.$theme',
          'case': {
            'id': 'components.button.selftest.row.$theme',
            'kind': 'button.items',
            'theme': theme,
            'locale': 'en',
            'viewport': {'width': 300, 'height': 68, 'density': density},
            'capture': {'flutterKey': 'parity-target', 'crop': 'element'},
          },
          'variant': {
            'id': 'default',
            'name': 'Default',
            'props': {
              'layout': {'direction': 'row', 'gap': 12},
              'items': [
                {'id': 'a', 'label': 'Primary', 'variant': 'primary'},
                {'id': 'b', 'label': 'Ghost'},
              ],
            },
          },
        };
        final meta = await captureParityCase(
          t,
          entry: entry,
          mapping: parityCases['button.items']!,
          fixtures: const {},
          outputDir: dir,
          runInfo: const {},
          fonts: fonts,
        );
        // PNG IHDR: width and height are the big-endian words at bytes 16 and 20.
        final png = File('${dir.path}/${entry['key']}.png').readAsBytesSync();
        final header = ByteData.sublistView(png);
        expect(
          (header.getUint32(16), header.getUint32(20)),
          (300 * density, 68 * density),
        );
        expect(meta['theme'], theme);
        expect((meta['themeResolved'] as Map)['brightness'], theme);
        expect(
          File('${dir.path}/${entry['key']}.metadata.json').existsSync(),
          isTrue,
        );
        final stored = json.decode(
          File('${dir.path}/${entry['key']}.metadata.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        expect((stored['fonts'] as Map)['faces'], isNotEmpty);
        // The text is drawn with the pinned face, not the Ahem test font: a 14px "Primary" is ~52px wide.
        final typography = (stored['typography'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          typography.map((t) => t['text']),
          containsAll(['Primary', 'Ghost']),
        );
      });
    }
  });
}
