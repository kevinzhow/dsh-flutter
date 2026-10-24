/// Column solve (dsh `columns.client.spec.ts`).
library;

import 'package:dsh_layout/dsh_layout.dart';
import 'package:test/test.dart';

void main() {
  group('clampWidth', () {
    test('clamps into the range and rounds', () {
      expect(clampWidth(250.4, 240, 420), 250);
      expect(clampWidth(100, 240, 420), 240);
      expect(clampWidth(9999, 240, 420), 420);
    });
    test('rounds halves up like JavaScript', () {
      expect(clampWidth(250.5, 240, 420), 251);
      expect(jsRound(-0.5), 0);
    });
  });

  group('computeColumns', () {
    test(
      'gives each edge column its preference when the center has enough room',
      () {
        expect(
          computeColumns(1920, 280, 864),
          const Columns(sidebar: 280, center: 776, rightbar: 864),
        );
      },
    );

    test('keeps only the left rail when both panels are closed', () {
      expect(
        computeColumns(1920, 0, 0),
        const Columns(sidebar: 56, center: 1864, rightbar: 0),
      );
    });

    test('clamps sidebar preferences and limits the right panel to 70% of the frame', () {
      expect(
        computeColumns(3000, 9999, 9999),
        const Columns(sidebar: 420, center: 480, rightbar: 2100),
      );
      expect(
        computeColumns(1920, 1, 1),
        const Columns(sidebar: 264, center: 1356, rightbar: 300),
      );
    });

    for (final (viewport, sidebar, rightbar, center) in [
      (1300.0, 280.0, 620.0, 400.0),
      (1100.0, 280.0, 420.0, 400.0),
      (1120.0, 420.0, 300.0, 400.0),
      (1119.0, 420.0, 0.0, 699.0),
      (1024.0, 420.0, 0.0, 604.0),
      (756.0, 0.0, 300.0, 400.0),
      (755.0, 0.0, 0.0, 699.0),
      (455.0, 0.0, 0.0, 399.0),
      (20.0, 0.0, 0.0, 0.0),
    ]) {
      test(
        'solves frame $viewport and sidebar $sidebar to right $rightbar and center $center',
        () {
          expect(
            computeColumns(viewport, sidebar, 864),
            Columns(
              sidebar: sidebar == 0 ? 56 : sidebar,
              center: center,
              rightbar: rightbar,
            ),
          );
        },
      );
    }

    test(
      'does not reduce the wide sidebar to keep a normal right panel open',
      () {
        expect(
          computeColumns(1024, 420, 500),
          const Columns(sidebar: 420, center: 604, rightbar: 0),
        );
      },
    );

    test('restores a still-open preference when the frame widens', () {
      expect(computeColumns(1100, 280, 864).rightbar, 420);
      expect(computeColumns(1920, 280, 864).rightbar, 864);
    });

    test('leaves a closed right track closed when the frame widens', () {
      expect(computeColumns(755, 0, 0).rightbar, 0);
      expect(computeColumns(1920, 0, 0).rightbar, 0);
    });

    test('hides the closed sidebar entirely where the platform has no rail (macOS, Windows)', () {
      expect(
        computeColumns(1280, 0, 0, 0),
        const Columns(sidebar: 0, center: 1280, rightbar: 0),
      );
      expect(computeColumns(1280, 280, 0, 0).sidebar, 280);
    });
  });
}
