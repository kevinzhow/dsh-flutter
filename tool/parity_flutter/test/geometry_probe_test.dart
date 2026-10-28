import 'dart:io';
import 'dart:ui' as ui;

import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _entry() => {
  'key': 'components.harness.geometry.light',
  'case': {
    'id': 'components.harness.geometry.light',
    'kind': 'test.geometry',
    'theme': 'light',
    'locale': 'en',
    'viewport': {'width': 160, 'height': 100, 'density': 1},
    'capture': {'crop': 'viewport'},
  },
  'variant': {
    'id': 'default',
    'name': 'held',
    'props': <String, dynamic>{},
    'interactions': [
      {'type': 'press', 'target': 'probe-target'},
    ],
  },
};

class _Model {
  bool held = false, released = false;
  int releases = 0;
}

class _HeldWidget extends StatefulWidget {
  const _HeldWidget(this.model);
  final _Model model;
  @override
  State<_HeldWidget> createState() => _HeldWidgetState();
}

class _HeldWidgetState extends State<_HeldWidget> {
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: GestureDetector(
      key: const ValueKey('probe-target'),
      onTapDown: (_) => setState(() => widget.model.held = true),
      onTapUp: (_) => setState(() {
        widget.model
          ..held = false
          ..released = true
          ..releases = widget.model.releases + 1;
      }),
      onTap: () {},
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.model.held
              ? const Color(0xffcc2233)
              : const Color(0xff2244cc),
        ),
        child: SizedBox(
          width: 90,
          height: 40,
          child: Text(
            widget.model.released
                ? 'released detail'
                : widget.model.held
                ? 'captured press'
                : 'idle',
          ),
        ),
      ),
    ),
  );
}

void main() {
  late Directory output;
  late List<ParityFontFace> fonts;
  setUpAll(() async {
    output = Directory.systemTemp.createTempSync('parity_geometry_probe_');
    fonts = await loadParityFonts(findParityFontsManifest());
  });
  tearDownAll(() => output.deleteSync(recursive: true));

  testWidgets(
    'all probes observe the screenshot before held release navigates',
    (t) async {
      final model = _Model();
      final metadata = await captureParityCase(
        t,
        entry: _entry(),
        mapping: ParityCase(
          widgets: const ['harness unit widget'],
          build: (_) => _HeldWidget(model),
          geometryProbe: (tester, ctx, root) => {
            'held': model.held,
            'released': model.released,
            'text': tester.widget<Text>(find.byType(Text)).data,
          },
        ),
        fixtures: const {},
        outputDir: output,
        runInfo: const {},
        fonts: fonts,
      );
      expect(model.releases, 1);
      expect(model.released, isTrue);
      expect(metadata['componentGeometry'], {
        'held': true,
        'released': false,
        'text': 'captured press',
      });
      expect(
        (metadata['typography'] as List).map((row) => (row as Map)['text']),
        contains('captured press'),
      );
      expect(
        (metadata['styleTokens'] as List).map(
          (row) => (row as Map)['backgroundColor'],
        ),
        contains('#CC2233'),
      );
      final png = File('${output.path}/${_entry()['key']}.png')
          .readAsBytesSync();
      final pixel = await t.runAsync(() async {
        final codec = await ui.instantiateImageCodec(png);
        final image = (await codec.getNextFrame()).image;
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final offset = (50 * image.width + 100) * 4;
        final result = rgba!.buffer.asUint8List(offset, 4).toList();
        image.dispose();
        codec.dispose();
        return result;
      });
      expect(pixel, [0xcc, 0x22, 0x33, 0xff]);
    },
  );

  testWidgets('absent probe preserves metadata shape and identical PNG bytes', (
    t,
  ) async {
    Future<Map<String, dynamic>> capture(ParityGeometryProbe? probe) =>
        captureParityCase(
          t,
          entry: {
            ..._entry(),
            'variant': {
              ..._entry()['variant'] as Map<String, dynamic>,
              'interactions': <Object?>[],
            },
          },
          mapping: ParityCase(
            widgets: const ['harness unit widget'],
            build: (_) => _HeldWidget(_Model()),
            geometryProbe: probe,
          ),
          fixtures: const {},
          outputDir: output,
          runInfo: const {},
          fonts: fonts,
        );
    final plain = await capture(null);
    final pngFile = File('${output.path}/${_entry()['key']}.png');
    final plainPng = pngFile.readAsBytesSync();
    expect(plain, isNot(contains('componentGeometry')));
    await t.pumpWidget(const SizedBox());
    await t.pump();
    final measured = await capture((_, _, _) => {'readOnly': true});
    expect(pngFile.readAsBytesSync(), plainPng);
    expect(measured.remove('componentGeometry'), {'readOnly': true});
    plain.remove('capturedAt');
    measured.remove('capturedAt');
    expect(measured, plain);
  });
}
