// The helpers that keep dsh_ui's pixels where Chromium puts them (docs/parity.md): corner shape, picture fitting,
// the break table of wrapped code and the baseline nudge.
import 'dart:typed_data';

import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _png(int width, int height) {
  final data = ByteData(33);
  final bytes = data.buffer.asUint8List();
  bytes.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  data.setUint32(8, 13);
  bytes.setAll(12, 'IHDR'.codeUnits);
  data.setUint32(16, width);
  data.setUint32(20, height);
  return bytes;
}

void main() {
  group('image size', () {
    test('reads PNG, GIF and JPEG headers', () {
      expect(dshImageSize(_png(186, 124)), (width: 186, height: 124));
      final gif = Uint8List.fromList([
        ...'GIF89a'.codeUnits,
        40, 0, 30, 0, //
        0, 0, 0, 0,
      ]);
      expect(dshImageSize(gif), (width: 40, height: 30));
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, // SOI, APP0 (length 4)
        0xFF, 0xC0, 0, 11, 8, 1, 0x2C, 0, 0xC8, 3, 0, 0, // SOF0: 200 x 300
      ]);
      expect(dshImageSize(jpeg), (width: 200, height: 300));
      expect(dshImageSize(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('decode target: just large enough for the frame, never upscaled', () {
      // 1000x500 into a 100x100 cover box: scale by the height.
      expect(
        dshDecodeTarget(
          (width: 1000, height: 500),
          const Size(100, 100),
          DshImageFit.cover,
        ),
        (width: null, height: 100),
      );
      // contain: scale by the width.
      expect(
        dshDecodeTarget(
          (width: 1000, height: 500),
          const Size(100, 100),
          DshImageFit.contain,
        ),
        (width: 100, height: null),
      );
      expect(
        dshDecodeTarget(
          (width: 50, height: 50),
          const Size(100, 100),
          DshImageFit.cover,
        ),
        (width: null, height: null),
      );
    });

    test('Chromium snaps the picture rectangle to whole CSS pixels', () {
      // a 93x62 picture in a 62 box starts at -15, not -15.5.
      final a = dshSnappedAlignment(
        box: const Size(62, 62),
        source: (width: 186, height: 124),
        fit: DshImageFit.cover,
      );
      expect((62 - 93) * (a.x + 1) / 2, closeTo(-15, 1e-9));
      expect(a.y, 0);
    });
  });

  group('wrapped code', () {
    test('breaks follow the Chromium table', () {
      String visible(String s) => s.replaceAll('​', '|').replaceAll('⁠', '');
      // a break is allowed after a space and before `{`, never between `}` and a backtick; words are left alone.
      expect(visible(dshWrapBreaks('a, {b}`c')), 'a, |{b}`c');
      expect(visible(dshWrapBreaks('a b')), 'a |b');
      expect(dshWrapBreaks('x').length, 1);
      // the first character of the next run takes part
      expect(dshWrapBreaks(',', next: '{').codeUnits.last, 0x200B);
      expect(dshWrapBreaks('}', next: '`').codeUnits.last, 0x2060);
    });
  });

  group('corner shape', () {
    test(
      'the superellipse outline is inside the circle of the same radius',
      () {
        const rect = Rect.fromLTWH(0, 0, 100, 100);
        final circle = dshSuperellipsePath(rect, 20, 1);
        final curve = dshSuperellipsePath(rect, 20, 1.5);
        // the corner pixel between the two curves: outside the circle, inside the superellipse
        expect(circle.contains(const Offset(5, 5)), isFalse);
        expect(curve.contains(const Offset(5, 5)), isTrue);
        expect(curve.contains(const Offset(50, 50)), isTrue);
        expect(curve.getBounds(), rect);
      },
    );

    testWidgets('the theme reads --dsw-corner-shape', (t) async {
      late DshThemeData theme;
      await t.pumpWidget(
        dshTestApp(
          Builder(
            builder: (context) {
              theme = context.dsh;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(dshCornerCurvature(theme), 1.5);
      expect(theme.cornerBorder(16).curvature, 1.5);
    });
  });

  group('baseline nudge', () {
    test('a style without a fixed line height needs none', () {
      expect(dshBaselineNudge(const TextStyle(fontSize: 14), 2), 0);
    });
  });
}
