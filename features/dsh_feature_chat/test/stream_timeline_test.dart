import 'package:dsh_feature_chat/src/stream/scrollbar.dart';
import 'package:dsh_feature_chat/src/stream/timeline.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/timeline_harness.dart';

// Ported from raft-flutter: history_prepend_stability_test,
// history_prepend_during_drag_test, history_load_once_test,
// timeline_scrollbar_drag_test (the engine tests, over plain rows).

Future<void> frames(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

void phone(WidgetTester t, {Size size = const Size(400, 800)}) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Drags toward older history until the harness asks for a page.
Future<void> dragToTop(WidgetTester t, List<int> requests) async {
  for (var k = 0; k < 80 && requests.isEmpty; k++) {
    await t.timedDrag(
      find.byType(DshStreamTimeline),
      const Offset(0, 300),
      const Duration(milliseconds: 80),
    );
    await t.pump(const Duration(milliseconds: 16));
  }
  expect(requests, isNotEmpty);
  // Let the fling come to rest.
  await t.pumpAndSettle();
}

/// The timeline scrollbar's thumb, from its painter's own hit test.
Rect? thumbRect(WidgetTester tester) {
  for (final e
      in find
          .descendant(
            of: find.byType(DshStreamTimeline),
            matching: find.byType(CustomPaint),
          )
          .evaluate()) {
    final painter = (e.widget as CustomPaint).foregroundPainter;
    final box = e.renderObject! as RenderBox;
    if (painter is! ScrollbarPainter || box.size.height < 300) continue;
    double? top, bottom;
    for (var y = 0.0; y < box.size.height; y += .5) {
      final local = Offset(box.size.width - 4, y);
      if (painter.hitTestOnlyThumbInteractive(local, PointerDeviceKind.mouse)) {
        top ??= y;
        bottom = y;
      }
    }
    if (top == null) return null;
    final origin = box.localToGlobal(Offset.zero);
    return Rect.fromLTRB(
      origin.dx + box.size.width - 8,
      origin.dy + top,
      origin.dx + box.size.width,
      origin.dy + bottom! + .5,
    );
  }
  return null;
}

void main() {
  group('history prepend', () {
    for (final tall in [false, true]) {
      testWidgets(
        'tall=$tall: an older page keeps the reading position on every frame',
        (t) async {
          phone(t);
          final requests = <int>[];
          late HarnessState state;
          await t.pumpWidget(
            timelineApp(
              TimelineHarness(
                // Every row taller than the viewport: no row is ever fully
                // visible, so the position can only be judged by its edges.
                count: tall ? 8 : 50,
                heightOf: tall ? (i) => 1000.0 + (i % 3) * 100 : null,
                onLoadOlder: () {
                  requests.add(1);
                  state.setLoading(true);
                },
              ),
            ),
          );
          state = TimelineHarness.of(t);
          await frames(t, 5);
          await dragToTop(t, requests);
          // A row on screen.
          int? reading;
          Rect? before;
          for (var i = 200; i < 250 && reading == null; i++) {
            final r = paintedRow(t, i);
            if (r != null && (tall || r.top > 60)) {
              reading = i;
              before = r;
            }
          }
          expect(reading, isNotNull);
          state.prepend(50);
          state.setLoading(false);
          var moved = 0;
          final log = <String>[];
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 16));
            final now = paintedRow(t, reading!);
            log.add('$i ${now?.top} (was ${before!.top})');
            if (now == null || (now.top - before.top).abs() > .5) moved++;
          }
          expect(state.rows.length, (tall ? 8 : 50) + 50);
          expect(moved, 0, reason: log.join('\n'));
        },
      );
    }

    testWidgets('a page landing mid-drag follows the finger', (t) async {
      phone(t);
      final requests = <int>[];
      late HarnessState state;
      await t.pumpWidget(
        timelineApp(
          TimelineHarness(
            onLoadOlder: () {
              requests.add(1);
              state.setLoading(true);
            },
          ),
        ),
      );
      state = TimelineHarness.of(t);
      await frames(t, 5);
      final gesture = await t.startGesture(
        t.getCenter(find.byType(DshStreamTimeline)),
      );
      for (var k = 0; k < 400 && requests.isEmpty; k++) {
        await gesture.moveBy(const Offset(0, 40));
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(requests, isNotEmpty);
      int? reading;
      for (var i = 200; i < 250 && reading == null; i++) {
        final r = paintedRow(t, i);
        if (r != null && r.top > 100 && r.top < 500) reading = i;
      }
      expect(reading, isNotNull);
      double? last = paintedRow(t, reading!)?.top;
      var bad = 0;
      final log = <String>[];
      for (var step = 0; step < 12; step++) {
        if (step == 3) {
          state.prepend(50);
          state.setLoading(false);
        }
        await gesture.moveBy(const Offset(0, 10));
        await t.pump(const Duration(milliseconds: 16));
        final now = paintedRow(t, reading)?.top;
        log.add('$step top=$now last=$last');
        if (now == null || last == null || (now - last - 10).abs() > 1.5) {
          bad++;
        }
        last = now;
      }
      await gesture.up();
      expect(bad, 0, reason: log.join('\n'));
    });
  });

  group('older pages load once per reach of the top', () {
    testWidgets('layout and a landed page never request the next page', (
      t,
    ) async {
      phone(t);
      final requests = <int>[];
      late HarnessState state;
      await t.pumpWidget(
        timelineApp(
          TimelineHarness(
            onLoadOlder: () {
              requests.add(1);
              state.setLoading(true);
            },
          ),
        ),
      );
      state = TimelineHarness.of(t);
      await frames(t, 10);
      expect(requests, isEmpty, reason: 'opening is not a user reach');
      await dragToTop(t, requests);
      expect(requests, hasLength(1));
      // The page lands; nothing moves the reader, so nothing asks again.
      state.prepend(50);
      state.setLoading(false);
      await frames(t, 30);
      expect(requests, hasLength(1));
      // Moving toward older again is a new reach.
      for (var k = 0; k < 40 && requests.length < 2; k++) {
        await t.timedDrag(
          find.byType(DshStreamTimeline),
          const Offset(0, 300),
          const Duration(milliseconds: 80),
        );
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(requests, hasLength(2));
    });

    testWidgets('scrolling toward newer never asks for history', (t) async {
      phone(t);
      var asked = 0;
      await t.pumpWidget(
        timelineApp(TimelineHarness(onLoadOlder: () => asked++)),
      );
      await frames(t, 5);
      // Up a little (still far from the top), then back down.
      await t.drag(find.byType(DshStreamTimeline), const Offset(0, 300));
      await t.pumpAndSettle();
      await t.drag(find.byType(DshStreamTimeline), const Offset(0, -300));
      await t.pumpAndSettle();
      expect(asked, 0);
    });
  });

  group('keyboard (desktop)', () {
    testWidgets('PageUp near the top asks for a page, once', (t) async {
      phone(t, size: const Size(1280, 800));
      var asked = 0;
      await t.pumpWidget(
        timelineApp(TimelineHarness(wide: true, onLoadOlder: () => asked++)),
      );
      final state = TimelineHarness.of(t);
      await frames(t, 5);
      final position = state.controller.position;
      position.jumpTo(position.minScrollExtent + 300);
      await frames(t, 3);
      // A tap on the blank part of the list focuses it, so keys scroll it.
      await t.tapAt(const Offset(10, 400));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await frames(t, 20);
      expect(asked, 1);
      await t.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await frames(t, 20);
      expect(asked, 1, reason: 'one page per reach');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('following the latest end', () {
    testWidgets('growth and new rows keep the end while the reader is there', (
      t,
    ) async {
      phone(t);
      await t.pumpWidget(timelineApp(TimelineHarness()));
      final state = TimelineHarness.of(t);
      await frames(t, 5);
      final scroll = state.controller;
      expect(scroll.position.pixels, scroll.position.maxScrollExtent);
      state.growLast(400);
      await t.pump();
      expect(scroll.position.pixels, scroll.position.maxScrollExtent);
      state.append(5);
      await t.pump();
      expect(scroll.position.pixels, scroll.position.maxScrollExtent);
      state.growLast(40);
      await t.pump();
      expect(scroll.position.pixels, scroll.position.maxScrollExtent);
    });

    testWidgets('a reader who moved up is left where they are', (t) async {
      phone(t);
      await t.pumpWidget(timelineApp(TimelineHarness()));
      final state = TimelineHarness.of(t);
      await frames(t, 5);
      await t.drag(find.byType(DshStreamTimeline), const Offset(0, 200));
      await t.pumpAndSettle();
      final scroll = state.controller;
      final at = scroll.position.pixels;
      expect(at, lessThan(scroll.position.maxScrollExtent));
      state.growLast(400);
      state.append(5);
      await t.pump();
      expect(scroll.position.pixels, at);
    });

    testWidgets('a short list sits at the top', (t) async {
      phone(t);
      await t.pumpWidget(
        timelineApp(TimelineHarness(count: 3, hasOlder: false)),
      );
      await frames(t, 3);
      final first = paintedRow(t, 200)!;
      expect(first.top, 24, reason: 'below the 24px header, not pushed down');
    });
  });

  group('frame budget', () {
    testWidgets('a long list builds only about a screen of rows', (t) async {
      phone(t);
      DshStreamTimeline.debugRowBuilds = 0;
      await t.pumpWidget(timelineApp(TimelineHarness(first: 0, count: 3000)));
      await frames(t, 3);
      expect(
        DshStreamTimeline.debugRowBuilds,
        lessThan(40),
        reason: '3000 rows, 800px viewport with a 250px cache each side',
      );
      var worst = 0;
      for (var i = 0; i < 30; i++) {
        final before = DshStreamTimeline.debugRowBuilds;
        await t.drag(
          find.byType(DshStreamTimeline),
          const Offset(0, 250),
          touchSlopY: 0,
        );
        await t.pump(const Duration(milliseconds: 16));
        worst = worst < DshStreamTimeline.debugRowBuilds - before
            ? DshStreamTimeline.debugRowBuilds - before
            : worst;
      }
      expect(worst, lessThanOrEqualTo(24));
    });
  });

  group('scrollbar', () {
    testWidgets('a wide window gets the draggable bar', (t) async {
      phone(t, size: const Size(1280, 800));
      await t.pumpWidget(timelineApp(TimelineHarness(wide: true)));
      expect(find.byType(DshTimelineScrollbar), findsOneWidget);
    });

    testWidgets('a touch phone gets no scrollbar (raft-flutter)', (t) async {
      phone(t);
      await t.pumpWidget(timelineApp(TimelineHarness()));
      expect(find.byType(RawScrollbar), findsNothing);
      expect(find.byType(DshTimelineScrollbar), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets(
      'thumb drag from bottom to top: the thumb stays under the pointer, '
      'a far target is re-centered, and holding the top loads one page',
      (t) async {
        phone(t, size: const Size(1280, 800));
        final requests = <int>[];
        late HarnessState state;
        await t.pumpWidget(
          timelineApp(
            TimelineHarness(
              first: 700,
              count: 300,
              wide: true,
              onLoadOlder: () {
                requests.add(1);
                state.setLoading(true);
              },
            ),
          ),
        );
        state = TimelineHarness.of(t);
        await frames(t, 5);
        final scroll = state.controller;
        // Show the bar.
        await t.sendEventToBinding(
          PointerScrollEvent(
            position: t.getCenter(find.byType(DshStreamTimeline)),
            scrollDelta: const Offset(0, -10),
          ),
        );
        await frames(t, 10);
        final start = thumbRect(t)!;
        const grabDy = 10.0;
        var pointer = Offset(start.center.dx, start.top + grabDy);
        final gesture = await t.startGesture(
          pointer,
          kind: PointerDeviceKind.mouse,
        );
        await t.pump(const Duration(milliseconds: 16));
        const steps = 12;
        final travel = start.top - 4;
        final log = <String>[];
        var maxBuilt = 0;
        double? lastPixels;
        for (var i = 0; i < steps; i++) {
          final before = DshStreamTimeline.debugRowBuilds;
          pointer = pointer.translate(0, -travel / steps);
          await gesture.moveTo(pointer);
          await t.pump(const Duration(milliseconds: 16));
          final built = DshStreamTimeline.debugRowBuilds - before;
          final thumb = thumbRect(t)!;
          log.add(
            '$i built=$built thumbTop=${thumb.top} pointer=${pointer.dy}',
          );
          if (built > maxBuilt) maxBuilt = built;
          expect(
            (thumb.top + grabDy - pointer.dy).abs(),
            lessThanOrEqualTo(2),
            reason: log.join('\n'),
          );
          // Toward older only: the model's position never goes back down.
          final y = scroll.position.pixels - scroll.position.minScrollExtent;
          if (lastPixels != null) {
            expect(
              y,
              lessThanOrEqualTo(lastPixels + 1),
              reason: log.join('\n'),
            );
          }
          lastPixels = y;
        }
        expect(maxBuilt, lessThanOrEqualTo(24), reason: log.join('\n'));
        expect(requests, isEmpty);
        // Hold at the top: one page, landing never re-triggers.
        for (var i = 0; i < 6; i++) {
          pointer = pointer.translate(0, -2);
          await gesture.moveTo(pointer);
          await t.pump(const Duration(milliseconds: 16));
        }
        expect(requests, hasLength(1));
        final held = paintedRow(t, 700);
        expect(held, isNotNull);
        state.prepend(50);
        state.setLoading(false);
        await t.pump(const Duration(milliseconds: 16));
        for (var i = 0; i < 20; i++) {
          pointer = pointer.translate(0, -2);
          await gesture.moveTo(pointer);
          await t.pump(const Duration(milliseconds: 16));
          expect(paintedRow(t, 700), held, reason: 'hold $i');
        }
        expect(requests, hasLength(1), reason: 'landing re-triggered a load');
        await gesture.up();
        await frames(t, 30);
        expect(requests, hasLength(1));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  });
}
