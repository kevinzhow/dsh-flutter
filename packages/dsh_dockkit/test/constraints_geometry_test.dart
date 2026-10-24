// Interaction limits and drag geometry (dsh `constraints.client.spec.ts`,
// `geometry.client.spec.ts`).
import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Split the root pane repeatedly until the docked grid holds [count] panes.
LayoutState grid(int count) {
  final minter = IdMinter();
  var state = createInitialState(minter, seedTab);
  while (dockPaneCount(state) < count) {
    state = applyOp(
      state,
      SplitOp(
        paneId: state.activePaneId,
        axis: SplitAxis.row,
        direction: SplitDirection.after,
        newPaneId: minter.pane(),
        newSplitId: minter.split(),
      ),
    ).state;
  }
  return state;
}

double sum(List<double> v) => v.reduce((a, b) => a + b);

void main() {
  group('pane cap', () {
    test('allows splitting up to four docked panes and no further', () {
      expect(maxDockPanes, 4);
      expect(canSplit(createInitialState(IdMinter(), seedTab)), isTrue);
      expect(dockPaneCount(grid(4)), 4);
      expect(canSplit(grid(4)), isFalse);
      expect(canSplit(grid(3)), isTrue);
    });

    test('ignores floating panes when counting the grid', () {
      final minter = IdMinter();
      final state = createInitialState(minter, seedTab);
      final guide = getPane(state, state.rootId).tabs.first;
      final floated = applyOp(
        state,
        FloatOp(
          tabId: guide,
          newPaneId: minter.float(),
          rect: const FloatRect(0, 0, 10, 10),
        ),
      ).state;
      expect(floated.floats, hasLength(1));
      expect(dockPaneCount(floated), 1);
      expect(canSplit(floated), isTrue);
    });
  });

  group('dock regions', () {
    test('offers five regions', () {
      expect(dockZones.map((z) => z.name).toList()..sort(), [
        'bottom',
        'center',
        'left',
        'right',
        'top',
      ]);
    });

    test('reads the centre of a pane as a move, not a split', () {
      expect(zoneAt(0.5, 0.5), DockZone.center);
      expect(zoneSplit(DockZone.center), isNull);
    });

    test('reads each edge band as its own region', () {
      expect(zoneAt(0.05, 0.5), DockZone.left);
      expect(zoneAt(0.95, 0.5), DockZone.right);
      expect(zoneAt(0.5, 0.05), DockZone.top);
      expect(zoneAt(0.5, 0.95), DockZone.bottom);
    });

    test('takes the closest edge in a corner', () {
      expect(zoneAt(0.02, 0.10), DockZone.left);
      expect(zoneAt(0.10, 0.02), DockZone.top);
    });

    test('maps regions to the split they create', () {
      expect(zoneSplit(DockZone.left), (
        axis: SplitAxis.row,
        direction: SplitDirection.before,
      ));
      expect(zoneSplit(DockZone.right), (
        axis: SplitAxis.row,
        direction: SplitDirection.after,
      ));
      expect(zoneSplit(DockZone.top), (
        axis: SplitAxis.column,
        direction: SplitDirection.before,
      ));
      expect(zoneSplit(DockZone.bottom), (
        axis: SplitAxis.column,
        direction: SplitDirection.after,
      ));
    });
  });

  group('divider clamping', () {
    test("honours an embedder's twenty-percent minimum", () {
      expect(clampSizes([0.01, 0.99], 0.2), [0.2, 0.8]);
      expect(clampSizes([0.99, 0.01], 0.2), [0.8, 0.2]);
      expect(clampSizes([0.5, 0.5], 0.2), [0.5, 0.5]);
    });

    test('keeps sizes summing to one', () {
      final sizes = clampSizes([0.6, 0.4]);
      expect(sum(sizes), closeTo(1, 1e-9));
      expect(sizes[0], closeTo(0.6, 1e-9));
    });

    test('lifts a pane dragged under the minimum', () {
      final sizes = clampSizes([0.01, 0.99]);
      expect(sizes[0], greaterThanOrEqualTo(minPaneFraction * 0.9));
      expect(sum(sizes), closeTo(1, 1e-9));
    });

    test('accepts unnormalized pixel-like input', () {
      final sizes = clampSizes([300, 100]);
      expect(sizes[0], closeTo(0.75, 1e-9));
      expect(sizes[1], closeTo(0.25, 1e-9));
    });

    test(
      'treats a negative size as zero and shares an all-zero input equally',
      () {
        expect(clampSizes([]), isEmpty);
        final lifted = clampSizes([-1, 1]);
        expect(lifted[0], closeTo(minPaneFraction, 1e-9));
        expect(lifted[1], closeTo(1 - minPaneFraction, 1e-9));
        expect(clampSizes([0, 0]), [0.5, 0.5]);
      },
    );

    test('pins a share that drops under the minimum only after the first pass', () {
      // 0.13 clears the floor until the first pin takes its 0.11 from everyone.
      final sizes = clampSizes([0.01, 0.13, 0.86]);
      expect(sizes[0], closeTo(minPaneFraction, 1e-9));
      expect(sizes[1], closeTo(minPaneFraction, 1e-9));
      expect(sizes[2], closeTo(1 - 2 * minPaneFraction, 1e-9));
    });

    test('never lifts a pane above an equal share when the minimum would not fit them all', () {
      final sizes = clampSizes([
        for (var i = 0; i < 10; i++) i == 0 ? 0.001 : 1.0,
      ]);
      expect(sizes[0], closeTo(0.1, 1e-9));
      expect(sum(sizes), closeTo(1, 1e-9));
    });
  });

  const pane = DockRect(100, 200, 400, 300);

  group('containsPoint', () {
    test('includes the edges and excludes anything outside', () {
      expect(containsPoint(pane, 100, 200), isTrue);
      expect(containsPoint(pane, 500, 500), isTrue);
      expect(containsPoint(pane, 300, 350), isTrue);
      expect(containsPoint(pane, 99, 350), isFalse);
      expect(containsPoint(pane, 300, 501), isFalse);
    });
  });

  group('zoneInRect', () {
    test('reads the middle of a pane as its centre', () {
      expect(zoneInRect(pane, 300, 350), DockZone.center);
    });

    test('reads each edge band as its own region', () {
      expect(zoneInRect(pane, 110, 350), DockZone.left);
      expect(zoneInRect(pane, 490, 350), DockZone.right);
      expect(zoneInRect(pane, 300, 210), DockZone.top);
      expect(zoneInRect(pane, 300, 490), DockZone.bottom);
    });

    test('treats a collapsed rectangle as all centre', () {
      expect(zoneInRect(const DockRect(0, 0, 0, 0), 0, 0), DockZone.center);
    });
  });

  group('insertionIndex', () {
    const tabs = [
      DockRect(0, 0, 100, 30),
      DockRect(100, 0, 100, 30),
      DockRect(200, 0, 100, 30),
    ];

    test('places before a tab while left of its midpoint', () {
      expect(insertionIndex(tabs, 10), 0);
      expect(insertionIndex(tabs, 49), 0);
    });

    test('places after a tab once past its midpoint', () {
      expect(insertionIndex(tabs, 51), 1);
      expect(insertionIndex(tabs, 151), 2);
      expect(insertionIndex(tabs, 400), 3);
    });

    test('places at the start of an empty strip', () {
      expect(insertionIndex(const [], 400), 0);
    });
  });

  group('passedThreshold', () {
    test('ignores travel under the threshold on both axes', () {
      expect(passedThreshold(10, 10, 10, 10), isFalse);
      expect(passedThreshold(10, 10, 10 + dragThreshold - 1, 10), isFalse);
      expect(passedThreshold(10, 10, 10 + dragThreshold, 10), isTrue);
      expect(passedThreshold(10, 10, 10, 10 - dragThreshold), isTrue);
    });
  });

  group('dividerSizes', () {
    test('moves the change between the two neighbours only', () {
      expect(dividerSizes([0.5, 0.5], 0, 0.1), [0.6, 0.4]);
      final three = dividerSizes([0.25, 0.25, 0.5], 1, -0.05);
      expect(three[0], 0.25);
      expect(three[1], closeTo(0.2, 1e-12));
      expect(three[2], closeTo(0.55, 1e-12));
    });

    test('leaves the fractions alone at a boundary that has no pair', () {
      expect(dividerSizes([0.5, 0.5], 1, 0.1), [0.5, 0.5]);
    });
  });

  group('floating rectangles', () {
    const rect = FloatRect(100, 80, 300, 200);
    const min = DockSize(floatMinWidth, floatMinHeight);

    test('moves without changing the size', () {
      expect(movedRect(rect, 25, -15), const FloatRect(125, 65, 300, 200));
    });

    test('resizes from the origin and honours the minimum', () {
      expect(
        resizedRect(rect, 40, 30, min),
        const FloatRect(100, 80, 340, 230),
      );
      expect(
        resizedRect(rect, -1000, -1000, min),
        const FloatRect(100, 80, floatMinWidth, floatMinHeight),
      );
    });

    test('places a new panel with its header under the drop point', () {
      final dropped = floatRectAt(
        400,
        300,
        const DockSize(floatDefaultWidth, floatDefaultHeight),
      );
      expect(dropped.width, floatDefaultWidth);
      expect(dropped.x, lessThan(400));
      expect(dropped.y, lessThan(300));
      final corner = floatRectAt(
        5,
        5,
        const DockSize(floatDefaultWidth, floatDefaultHeight),
      );
      expect((corner.x, corner.y), (0.0, 0.0));
    });
  });

  group('halvesFit, the room rule', () {
    // A pane whose strip shows [fixed] px of controls and one chip box of 60px;
    // the fill takes the rest.
    PaneMeasure measure(double width, double height, double fixed) {
      final strip = DockRect(1, 1, width - 2, 36);
      return PaneMeasure(
        pane: DockRect(0, 0, width, height),
        strip: strip,
        chipsWidth: 60,
        fillWidth: (strip.width - 60 - fixed) < 0
            ? 0
            : strip.width - 60 - fixed,
      );
    }

    test('lets an unmeasured pane split: the rule only blocks on a positive reading', () {
      final fit = halvesFit(measure(0, 0, 104));
      expect((fit.row, fit.column), (true, true));
    });

    test("needs each half to hold the strip's fixed controls plus one minimum chip", () {
      // 520px: halves of 258px inside the borders, against 104 + 100.
      expect(halvesFit(measure(520, 600, 104)).row, isTrue);
      // 208px: halves of 102px, short of 204.
      expect(halvesFit(measure(208, 600, 104)).row, isFalse);
      // The boundary is inclusive: 2 * (204 + 2 borders) = 412; the divider takes no room.
      expect(halvesFit(measure(412, 600, 104)).row, isTrue);
      expect(halvesFit(measure(411, 600, 104)).row, isFalse);
      // A strip with fewer controls needs less: 2 * (144 + 2) = 292.
      expect(halvesFit(measure(291, 600, 44)).row, isFalse);
      expect(halvesFit(measure(292, 600, 44)).row, isTrue);
    });

    test('needs each half to hold the strip plus a minimum body for a column split', () {
      // Halves of h / 2 - 2 against 36 + 48 = 84.
      expect(halvesFit(measure(420, 172, 104)).column, isTrue);
      expect(halvesFit(measure(420, 171, 104)).column, isFalse);
    });

    test("takes the minimums it is given, and the stylesheet's by default", () {
      expect(
        (
          defaultSplitMinimums.divider,
          defaultSplitMinimums.chip,
          defaultSplitMinimums.body,
        ),
        (0.0, 100.0, 48.0),
      );
      const none = SplitMinimums(divider: 0, chip: 0, body: 0);
      expect(halvesFit(measure(208, 600, 104), none).row, isFalse);
      expect(halvesFit(measure(220, 600, 104), none).row, isTrue);
    });
  });
}
