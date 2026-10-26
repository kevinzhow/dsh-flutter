import 'dart:async';

import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_feature_chat/src/stream/extras.dart';
import 'package:dsh_feature_chat/src/stream/skeleton.dart' show StreamSkeleton;
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_feature_chat/src/stream/reading_anchor.dart' show RowKey;
import 'package:dsh_feature_chat/src/stream/timeline.dart'
    show DshStreamTimeline;
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stream_fixture.dart';

// Adapted from raft-flutter: chat_reading_position_test,
// history_reading_position_view_test, timeline_bottom_button_mounted_test,
// history_memory_latest_end_test (a ChatView over a real Session).

void phone(WidgetTester t, [Size size = const Size(400, 800)]) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

ChatViewState chatState(WidgetTester t) =>
    t.state<ChatViewState>(find.byType(ChatView));

/// A plain drag toward older history (no fling): moves exactly [dy].
Future<void> dragUp(WidgetTester t, double dy) async {
  await t.drag(find.byType(ChatView), Offset(0, dy));
  await t.pump(const Duration(milliseconds: 16));
}

/// A flick toward older history (the finger leaves with velocity).
Future<void> flickUp(WidgetTester t, double dy) async {
  await t.timedDrag(
    find.byType(ChatView),
    Offset(0, dy),
    const Duration(milliseconds: 80),
  );
  await t.pump(const Duration(milliseconds: 16));
}

void main() {
  late StreamFixture fx;

  Future<void> mount(WidgetTester t, StreamFixture fx) async {
    final slots = fx.registry();
    await t.runAsync(fx.open);
    await t.pumpWidget(dshTestApp(fx.view(slots)));
    await settleFrames(t, 10);
  }

  setUp(() {
    fx = StreamFixture();
    streamExtras = false;
  });
  tearDown(() => streamExtras = false);

  testWidgets('a session opens at its newest message', (t) async {
    phone(t);
    await mount(t, fx);
    final state = chatState(t);
    final scroll = state.scrollController!;
    expect(scroll.position.pixels, scroll.position.maxScrollExtent);
    expect(paintedText(t, answerOf(299)), isNotNull);
    expect(state.atBottom, isTrue);
    expect(find.byKey(const ValueKey('chat-to-bottom')), findsNothing);
  });

  testWidgets(
    'dsh web\'s "Loading history…" hint stands in until the session has opened',
    (t) async {
      phone(t);
      final slots = fx.registry();
      await t.pumpWidget(dshTestApp(fx.view(slots)));
      await t.pump();
      expect(find.byKey(const ValueKey('session-loading')), findsOneWidget);
      expect(find.text('Loading history…'), findsOneWidget);
      expect(find.byType(StreamSkeleton), findsNothing);
      expect(find.byKey(const ValueKey('chat-list')), findsNothing);
      await t.runAsync(fx.open);
      await settleFrames(t, 5);
      expect(find.byKey(const ValueKey('session-loading')), findsNothing);
      expect(find.byKey(const ValueKey('chat-list')), findsOneWidget);
    },
  );

  testWidgets('with the extras on, a skeleton stands in instead', (t) async {
    phone(t);
    streamExtras = true;
    final slots = fx.registry();
    await t.pumpWidget(dshTestApp(fx.view(slots)));
    await t.pump();
    expect(find.byType(StreamSkeleton), findsOneWidget);
    expect(find.text('Loading history…'), findsNothing);
  });

  testWidgets('a long session builds only the rows near the screen', (t) async {
    phone(t);
    final big = StreamFixture(turns: 2000, first: 400);
    await mount(t, big);
    // 400 turns are loaded (~2400 nodes); a screen of them is built.
    expect(
      find.textContaining('Answer ', findRichText: true).evaluate().length,
      lessThan(40),
    );
  });

  testWidgets('a streaming answer keeps the latest end in view', (t) async {
    phone(t);
    await mount(t, fx);
    final scroll = chatState(t).scrollController!;
    final es = fx.session.eventSource;
    final turns = fx.turns;
    var seq = turns * eventsPerTurn + 1;
    es.append(
      EventEntry({
        'type': 'turn/start',
        'seq': seq++,
        'time': 1,
        'data': {'turn': turns + 1},
      }),
    );
    es.append(
      EventEntry({
        'type': 'step/start',
        'seq': seq++,
        'time': 1,
        'data': {'turn': turns + 1, 'step': 1},
      }),
    );
    es.append(
      EventEntry({
        'type': 'assistant/live-chunk',
        'seq': seq - 1 + .1,
        'time': 1,
        'data': {
          'attemptId': 'a-live',
          'turn': turns + 1,
          'step': 1,
          'chunk': {'type': 'block-start', 'index': 0, 'blockType': 'text'},
        },
      }, transient: true),
    );
    await t.pump();
    for (var i = 0; i < 12; i++) {
      es.append(
        EventEntry({
          'type': 'assistant/live-chunk',
          'seq': seq - 1 + .2 + i / 100,
          'time': 1,
          'data': {
            'attemptId': 'a-live',
            'turn': turns + 1,
            'step': 1,
            'chunk': {
              'type': 'text-delta',
              'index': 0,
              'text': 'Streaming sentence number $i of the answer.\n\n',
            },
          },
        }, transient: true),
      );
      await t.pump(const Duration(milliseconds: 16));
      expect(
        scroll.position.pixels,
        scroll.position.maxScrollExtent,
        reason: 'chunk $i left the latest end',
      );
      final shown = paintedText(t, 'number $i of');
      expect(shown, isNotNull, reason: 'chunk $i is not on screen');
      expect(shown!.bottom, lessThanOrEqualTo(800));
    }
    expect(
      find.textContaining('number 11', findRichText: true),
      findsOneWidget,
    );
  });

  /// A whole new turn arriving at the latest end.
  void appendTurn(StreamFixture fx, int turn) {
    for (final record in turnRecords(turn)) {
      fx.session.eventSource.append(
        EventEntry(Map<String, Object?>.from(record['event']! as Map)),
      );
    }
  }

  group('reading above the latest end', () {
    testWidgets('new content is counted, not followed; the button returns', (
      t,
    ) async {
      phone(t);
      await mount(t, fx);
      final state = chatState(t);
      final scroll = state.scrollController!;
      await dragUp(t, 300);
      await t.pumpAndSettle();
      expect(state.atBottom, isFalse);
      expect(find.byKey(const ValueKey('chat-to-bottom')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-new-count')), findsNothing);
      final at = scroll.position.pixels;
      final reading = paintedText(t, 'Question');
      expect(reading, isNotNull);

      appendTurn(fx, 300);
      await t.pump();
      await settleFrames(t, 5);
      expect(scroll.position.pixels, at, reason: 'the reader was moved');
      expect(paintedText(t, 'Question'), reading);
      // A turn adds a user message and an answer: two new messages.
      expect(state.newCount, 2);
      // dsh has no count: the control stays the plain chevron.
      expect(find.byKey(const ValueKey('chat-new-count')), findsNothing);
      expect(find.text('2 new'), findsNothing);
      appendTurn(fx, 301);
      await t.pump();
      expect(state.newCount, 4);

      await t.tap(find.byKey(const ValueKey('chat-to-bottom')));
      await t.pumpAndSettle();
      expect(scroll.position.pixels, scroll.position.maxScrollExtent);
      expect(state.atBottom, isTrue);
      expect(state.newCount, 0);
      expect(find.byKey(const ValueKey('chat-to-bottom')), findsNothing);
      expect(paintedText(t, answerOf(301)), isNotNull);
    });

    testWidgets('with the extras on, the control carries the count', (t) async {
      phone(t);
      streamExtras = true;
      await mount(t, fx);
      await dragUp(t, 300);
      await t.pumpAndSettle();
      appendTurn(fx, 300);
      await t.pump();
      expect(find.text('2 new'), findsOneWidget);
      appendTurn(fx, 301);
      await t.pump();
      expect(find.text('4 new'), findsOneWidget);
    });

    testWidgets(
      'a running status row and a new turn arriving leave the reader where they are',
      (t) async {
        phone(t);
        await mount(t, fx);
        await dragUp(t, 300);
        await t.pumpAndSettle();
        final scroll = chatState(t).scrollController!;
        final at = scroll.position.pixels;
        final reading = paintedText(t, 'Question');
        fx.session.handleRunning(true);
        await t.pump();
        appendTurn(fx, 300);
        await t.pump();
        fx.session.handleRunning(false);
        await settleFrames(t, 5);
        expect(scroll.position.pixels, at);
        expect(paintedText(t, 'Question'), reading);
      },
    );

    testWidgets(
      'an existing local echo does not pull an idle desktop reader back to the tail',
      (t) async {
        phone(t, const Size(1280, 800));
        await mount(t, fx);
        await t.runAsync(() => fx.session.prompt('Awaiting admission'));
        await t.pumpAndSettle();
        final state = chatState(t);
        final scroll = state.scrollController!;
        await dragUp(t, 400);
        await t.pumpAndSettle();
        final at = scroll.position.pixels;
        final reading = paintedText(t, 'Question');
        expect(state.atBottom, isFalse);
        expect(reading, isNotNull);
        fx.session.handleRunning(true);
        await t.pumpAndSettle();
        expect(
          scroll.position.pixels,
          at,
          reason: 'a running-state update repeated the old send jump',
        );
        expect(paintedText(t, 'Question'), reading);
        appendTurn(fx, 300);
        await t.pumpAndSettle();
        expect(
          scroll.position.pixels,
          at,
          reason: 'a remote turn repeated the old send jump',
        );
      },
    );

    testWidgets(
      'a remote next-step inbox echo does not count as a new local send',
      (t) async {
        phone(t, const Size(1280, 800));
        await mount(t, fx);
        await dragUp(t, 400);
        await t.pumpAndSettle();
        final state = chatState(t);
        final scroll = state.scrollController!;
        final at = scroll.position.pixels;
        final reading = paintedText(t, 'Question');
        fx.session.projections.apply('inbox', {
          'next-turn': <Object?>[],
          'next-step': [
            {
              'id': 'remote-instruction',
              'source': {'kind': 'user', 'rpcId': 'other-client-request'},
              'content': [
                {'type': 'text', 'text': 'Remote steering instruction'},
              ],
            },
          ],
        }, 2);
        await t.pumpAndSettle();
        expect(
          scroll.position.pixels,
          at,
          reason: 'a remote inbox update moved the reader',
        );
        expect(paintedText(t, 'Question'), reading);
        expect(state.atBottom, isFalse);
      },
    );

    testWidgets(
      'a history page preserves a desktop wheel reader with a pending echo',
      (t) async {
        phone(t, const Size(1280, 800));
        await mount(t, fx);
        await t.runAsync(() => fx.session.prompt('Awaiting history read'));
        await t.pumpAndSettle();
        await t.sendEventToBinding(
          PointerScrollEvent(
            position: t.getCenter(find.byType(DshStreamTimeline)),
            scrollDelta: const Offset(0, -400),
          ),
        );
        await t.pumpAndSettle();
        final state = chatState(t);
        final scroll = state.scrollController!;
        final at = scroll.position.pixels;
        final question = find
            .textContaining('Question', findRichText: true)
            .first;
        final text = t.widget<RichText>(question).text.toPlainText();
        final reading = paintedText(t, text);
        expect(state.atBottom, isFalse);
        expect(reading, isNotNull);
        await t.runAsync(() async {
          unawaited(fx.session.loadOlder());
          await Future<void>.delayed(Duration.zero);
        });
        expect(fx.pages, hasLength(1));
        await fx.landPage(t);
        await t.pumpAndSettle();
        expect(
          scroll.position.pixels,
          at,
          reason: 'loading older history repeated the pending send jump',
        );
        expect(paintedText(t, text), reading);
        expect(state.atBottom, isFalse);
      },
    );

    testWidgets(
      'a new local send from less than one viewport still reaches the new tail',
      (t) async {
        phone(t, const Size(1280, 800));
        await mount(t, fx);
        await dragUp(t, 400);
        await t.pumpAndSettle();
        final scroll = chatState(t).scrollController!;
        await t.runAsync(() => fx.session.prompt('A new short-distance send'));
        await t.pumpAndSettle();
        expect(scroll.position.pixels, scroll.position.maxScrollExtent);
        expect(chatState(t).atBottom, isTrue);
      },
    );

    testWidgets('sending returns to the latest end wherever the reader is', (
      t,
    ) async {
      phone(t);
      await mount(t, fx);
      final scroll = chatState(t).scrollController!;
      for (var i = 0; i < 4; i++) {
        await dragUp(t, 300);
      }
      await t.pumpAndSettle();
      expect(scroll.position.pixels, lessThan(scroll.position.maxScrollExtent));
      await t.runAsync(() => fx.session.prompt('one more thing'));
      await t.pump();
      await t.pumpAndSettle();
      expect(scroll.position.pixels, scroll.position.maxScrollExtent);
      expect(paintedText(t, 'one more thing'), isNotNull);
    });

    testWidgets(
      'the button needs a real distance: bouncing at the end shows none',
      (t) async {
        phone(t);
        await mount(t, fx);
        await dragUp(t, 10);
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('chat-to-bottom')), findsNothing);
      },
    );
  });

  group('older history', () {
    testWidgets(
      'a page is read near the top, the reader stays put, and it asks once',
      (t) async {
        phone(t);
        await mount(t, fx);
        expect(fx.pages, isEmpty, reason: 'opening is not a reach');
        for (var k = 0; k < 60 && fx.pages.isEmpty; k++) {
          await flickUp(t, 300);
        }
        expect(fx.pages, hasLength(1));
        await settleFrames(t, 60);
        // Settle the final fractional-pixel spring correction before measuring
        // an idle reader's position across the page landing.
        await t.pumpAndSettle();
        // dsh: the "Load earlier" control is disabled and reads "Loading…".
        expect(find.byKey(const ValueKey('load-older')), findsOneWidget);
        expect(find.text('Loading…'), findsOneWidget);
        expect(find.byKey(const ValueKey('older-skeleton')), findsNothing);
        // The topmost loaded row on screen.
        final reading = paintedText(t, 'Question');
        expect(reading, isNotNull);
        final text = find
            .textContaining('Question', findRichText: true)
            .evaluate()
            .map((e) => (e.widget as RichText).text.toPlainText())
            .first;
        await fx.landPage(t);
        var moved = 0;
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 16));
          final now = paintedText(t, text);
          if (now == null || (now.top - reading!.top).abs() > .5) moved++;
        }
        expect(
          moved,
          0,
          reason: 'the reading position moved while a page landed',
        );
        expect(find.text('Loading…'), findsNothing);
        expect(fx.pages, hasLength(1), reason: 'the landing asked for more');
        expect(fx.session.snapshot.value.hasMore, isTrue);
      },
    );

    testWidgets(
      'a session shorter than the screen reads pages until it fills',
      (t) async {
        phone(t);
        final small = StreamFixture(turns: 40, first: 1, pageTurns: 1);
        small.answers = {for (var i = 0; i < 40; i++) i: 'Answer $i'};
        await mount(t, small);
        // One short turn does not fill 800px: the view asks for the next page
        // by itself, again and again, and stops once it fills.
        for (var i = 0; i < 30 && small.pages.length < 12; i++) {
          if (small.pages.any((p) => !p.isCompleted)) await small.landPage(t);
          await settleFrames(t, 3);
          if (!small.session.snapshot.value.hasMore) break;
        }
        final scroll = chatState(t).scrollController!;
        expect(
          scroll.position.maxScrollExtent - scroll.position.minScrollExtent,
          greaterThan(0),
        );
        expect(
          small.pages.length,
          lessThan(40),
          reason: 'it kept reading after filling',
        );
      },
    );
  });

  group('reading position', () {
    testWidgets('a session reopens where the reader stopped', (t) async {
      phone(t);
      final slots = fx.registry();
      await t.runAsync(fx.open);
      await t.pumpWidget(dshTestApp(fx.view(slots)));
      await settleFrames(t, 10);
      for (var i = 0; i < 3; i++) {
        await dragUp(t, 300);
      }
      await t.pumpAndSettle();
      final text = find
          .textContaining('Question', findRichText: true)
          .evaluate()
          .map((e) => (e.widget as RichText).text.toPlainText())
          .first;
      final before = paintedText(t, text)!;
      // The reader pauses (the position is saved once scrolling stops), then
      // leaves the session and comes back (the app's navigation).
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpWidget(dshTestApp(const SizedBox()));
      await t.pumpWidget(dshTestApp(fx.view(slots)));
      await settleFrames(t, 10);
      final after = paintedText(t, text);
      expect(after, isNotNull);
      expect(after!.top, closeTo(before.top, 1));
      expect(chatState(t).atBottom, isFalse);
    });

    testWidgets(
      'a window replaced under the reader (the center row gone) keeps the reading position',
      (t) async {
        phone(t);
        await mount(t, fx);
        for (var i = 0; i < 2; i++) {
          await dragUp(t, 300);
        }
        await t.pumpAndSettle();
        final text = find
            .textContaining('Question', findRichText: true)
            .evaluate()
            .map((e) => (e.widget as RichText).text.toPlainText())
            .first;
        final before = paintedText(t, text)!;
        // The host re-baselines: the same window without its newest turn.
        final es = fx.session.eventSource;
        final kept = es.window.entries
            .where((e) => e.seq <= fx.turns * eventsPerTurn - eventsPerTurn)
            .toList();
        es.replace(kept, true);
        await t.pump();
        await settleFrames(t, 10);
        final after = paintedText(t, text);
        expect(after, isNotNull, reason: 'the reader lost their place');
        expect(after!.top, closeTo(before.top, 1));
      },
    );

    testWidgets('a reader at the latest end reopens at the latest end', (
      t,
    ) async {
      phone(t);
      final slots = fx.registry();
      await t.runAsync(fx.open);
      await t.pumpWidget(dshTestApp(fx.view(slots)));
      await settleFrames(t, 10);
      await t.pumpWidget(dshTestApp(const SizedBox()));
      await t.pumpWidget(dshTestApp(fx.view(slots)));
      await settleFrames(t, 10);
      final scroll = chatState(t).scrollController!;
      expect(scroll.position.pixels, scroll.position.maxScrollExtent);
    });
  });

  group('fast scrolling', () {
    /// Pixels of the list's viewport covered by no row, in the middle of the
    /// list (the ends have a header and footer of their own).
    double blank(WidgetTester t) {
      final viewport = t.renderObject<RenderBox>(
        find.byWidgetPredicate((w) => w is Viewport),
      );
      final top = viewport.localToGlobal(Offset.zero).dy;
      final bottom = top + viewport.size.height;
      final spans = <(double, double)>[];
      for (final e
          in find.byWidgetPredicate((w) => w.key is RowKey).evaluate()) {
        final b = e.renderObject;
        if (b is! RenderBox || !b.attached || !b.hasSize) continue;
        final y = b.localToGlobal(Offset.zero).dy;
        spans.add((y, y + b.size.height));
      }
      spans.sort((a, b) => a.$1.compareTo(b.$1));
      var covered = top, gap = 0.0;
      for (final (a, b) in spans) {
        // Rows touch; float noise between neighbours is under a pixel.
        if (a - covered > 1.5) gap += (a - covered).clamp(0, bottom - covered);
        if (b > covered) covered = b;
        if (covered >= bottom) break;
      }
      if (covered < bottom) gap += bottom - covered;
      return gap;
    }

    testWidgets(
      'repeated fast flings both ways never show a blank region and build a bounded number of rows',
      (t) async {
        phone(t);
        await mount(t, fx);
        final scroll = chatState(t).scrollController!;
        DshStreamTimeline.debugRowBuilds = 0;
        var worstBlank = 0.0, worstBuilds = 0, frames = 0;
        for (var k = 0; k < 24; k++) {
          final dy = k.isEven ? 1400.0 : -1400.0;
          await t.fling(find.byType(ChatView), Offset(0, dy), 9000);
          for (var i = 0; i < 45; i++) {
            final before = DshStreamTimeline.debugRowBuilds;
            await t.pump(const Duration(milliseconds: 16));
            frames++;
            final p = scroll.position;
            if (p.extentBefore > 600 && p.extentAfter > 600) {
              final b = blank(t);
              if (b > worstBlank) worstBlank = b;
            }
            final built = DshStreamTimeline.debugRowBuilds - before;
            if (built > worstBuilds) worstBuilds = built;
          }
          // Landed pages are not part of this test: complete them as they
          // are asked for, so history keeps flowing in under the flings.
          while (fx.pages.any((p) => !p.isCompleted)) {
            await fx.landPage(t);
          }
        }
        expect(frames, greaterThan(1000));
        expect(worstBlank, 0, reason: 'a part of the viewport had no row');
        expect(worstBuilds, lessThanOrEqualTo(30));
      },
    );
  });
}
