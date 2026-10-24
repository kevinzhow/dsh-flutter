// Flutter side of tool/parity-ext/text-baseline-sweep.py: the same "HHHH" blocks as
// tool/parity-ext/probes/text-baseline.mjs, as a plain Text and as DshChromeText, at every density of
// <TEXT_BASELINE_SWEEP_DIR>/combos.json. Skipped unless that variable is set (the sweep script sets it).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = Platform.environment['TEXT_BASELINE_SWEEP_DIR'];
  testWidgets('text baseline sweep', (tester) async {
    await tester.runAsync(() => loadParityFonts(findParityFontsManifest()));
    final cfg = json.decode(
      File('$dir/combos.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final meta = json.decode(
      File('$dir/rows.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    dshPixelModel = cfg['reference'] == 'emulated'
        ? DshPixelModel.emulated
        : DshPixelModel.native;
    addTearDown(() => dshPixelModel = DshPixelModel.native);
    final rows = (meta['rows'] as List).cast<Map<String, dynamic>>();
    final pitch = (meta['pitch'] as num).toDouble();
    for (final dprValue in cfg['dprs'] as List) {
      final dpr = (dprValue as num).toDouble();
      for (final variant in ['plain', 'dsh']) {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = Size(80 * dpr, pitch * rows.length * dpr);
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: const Color(0xFFFFFFFF),
                child: Stack(
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      Positioned(
                        left: 16,
                        top: i * pitch + 4,
                        child: () {
                          final r = rows[i];
                          final style = TextStyle(
                            fontFamily: r['family'] as String,
                            fontSize: (r['size'] as num).toDouble(),
                            height: (r['line'] as num) / (r['size'] as num),
                            leadingDistribution: TextLeadingDistribution.even,
                            fontWeight: (r['weight'] as int) >= 600
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: const Color(0xFF000000),
                          );
                          return variant == 'plain'
                              ? Text('HHHH', style: style, softWrap: false)
                              : DshChromeText(
                                  'HHHH',
                                  style: style,
                                  softWrap: false,
                                );
                        }(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: dpr);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/flutter-$variant-dpr$dprValue.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
    }
  }, skip: dir == null);
}
