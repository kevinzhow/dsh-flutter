import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_feature_chat/src/stream/message_actions.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stream_fixture.dart';

// Stream interactions as dsh web has them (ui-chat MessageIconActions,
// ui-primitives MarkdownDelegate, native text selection), with the phone
// adaptation raft-flutter uses (RaftSelectionArea, hover chrome off for a
// coarse pointer).

void size(WidgetTester t, Size s) {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// The text of every clipboard write, newest last.
List<String> watchClipboard(WidgetTester t) {
  final writes = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        writes.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return writes;
}

/// The match painted lowest on screen (tree order is not visual order: the
/// history side of the timeline builds outward).
Finder lowest(WidgetTester t, Finder f) {
  final all = f.evaluate().toList();
  all.sort(
    (a, b) => t
        .getCenter(find.byWidget(b.widget))
        .dy
        .compareTo(t.getCenter(find.byWidget(a.widget)).dy),
  );
  return find.byWidget(all.first.widget);
}

void main() {
  late StreamFixture fx;
  setUp(() => fx = StreamFixture(turns: 20, first: 20));

  Future<void> mount(
    WidgetTester t, {
    ToolHostActions? host,
    SlotRegistry? slots,
  }) async {
    slots ??= fx.registry(host: host);
    await t.runAsync(fx.open);
    await t.pumpWidget(dshTestApp(fx.view(slots)));
    await settleFrames(t, 10);
  }

  group('message actions', () {
    testWidgets('copy writes the message text and shows the check', (t) async {
      size(t, const Size(400, 800));
      final semantics = t.ensureSemantics();
      final writes = watchClipboard(t);
      await mount(t);
      // The newest user message: its copy action sits under the bubble.
      final userCopies = find.descendant(
        of: find.byType(UserBubble),
        matching: find.byKey(const ValueKey('message-copy')),
      );
      expect(userCopies, findsWidgets);
      await t.tap(lowest(t, userCopies));
      await t.pump(const Duration(milliseconds: 50));
      expect(writes.last, questionOf(19));
      expect(find.bySemanticsLabel(RegExp('Copied')), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      expect(find.bySemanticsLabel(RegExp('Copy')), findsWidgets);
      semantics.dispose();
    });

    testWidgets('the closing row copies the answer, without the question', (
      t,
    ) async {
      size(t, const Size(400, 800));
      final writes = watchClipboard(t);
      await mount(t);
      await t.tap(
        lowest(
          t,
          find.descendant(
            of: find.byKey(const ValueKey('turn-copy')),
            matching: find.byKey(const ValueKey('message-copy')),
          ),
        ),
      );
      await t.pump();
      expect(writes.last, answerOf(19));
      expect(writes.last, isNot(contains('Question')));
    });

    testWidgets('each action row carries its message time', (t) async {
      size(t, const Size(400, 800));
      await mount(t);
      final clock = find.byKey(const ValueKey('message-clock'));
      expect(clock, findsWidgets);
      final shown = [
        for (final e in clock.evaluate())
          find
              .descendant(
                of: find.byWidget(e.widget),
                matching: find.byType(RichText),
              )
              .evaluate()
              .map((r) => (r.widget as RichText).text.toPlainText())
              .join(),
      ];
      // Seqs start at 1 and times at 1000 + seq ms: 1970, so the date form.
      expect(shown, everyElement(matches(r'^1970-1-1 \d\d:\d\d$')));
    });

    testWidgets('phones show every row\'s actions (no hover)', (t) async {
      size(t, const Size(400, 800));
      await mount(t);
      expect(find.byKey(const ValueKey('message-copy')), findsWidgets);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('message-copy')),
          matching: find.byType(AnimatedOpacity),
        ),
        findsNothing,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets(
      'desktop: earlier rows reveal their actions on hover, the newest keeps them',
      (t) async {
        size(t, const Size(1280, 800));
        await mount(t);
        double opacityOf(String text) {
          final row = find
              .ancestor(of: find.text(text), matching: find.byType(HoverReveal))
              .first;
          return t
              .widget<AnimatedOpacity>(
                find
                    .descendant(of: row, matching: find.byType(AnimatedOpacity))
                    .first,
              )
              .opacity;
        }

        // Page up to an earlier user message.
        await t.drag(find.byType(ChatView), const Offset(0, 500));
        await settleFrames(t, 5);
        // A user message that is inside the window (the cache extent builds
        // rows just beyond it too).
        final inView = find.textContaining('Question').evaluate().where((e) {
          final y = t.getCenter(find.byWidget(e.widget)).dy;
          return y > 60 && y < 740;
        });
        final label = (inView.first.widget as Text).data!;
        final earlier = find.text(label);
        expect(earlier, findsOneWidget);
        expect(opacityOf(label), 0);
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(t.getCenter(earlier));
        await t.pump(const Duration(milliseconds: 200));
        expect(opacityOf(label), 1);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  });

  group('message column', () {
    // dsh web: `.column` is `min(content width, scroll width - 64)`, centred in
    // the scroll body that is left of the 2px margin and the scrollbar gutter
    // (`ChatView.module.css`, `ConversationRoot.module.css`).
    testWidgets(
      'a wide pane scales the column to 64% of it, centred like dsh web',
      (t) async {
        size(t, const Size(1280, 800));
        await mount(t);
        final bubble = lowest(t, find.byType(UserBubble));
        // Content width 64% of 1280 = 819.2; 1280 - 2 - 5 = 1273 to centre on:
        // the column is x 226.9 .. 1046.1.
        expect(t.getTopRight(bubble).dx, closeTo(1046.1, 0.5));
      },
    );

    testWidgets('a phone keeps 32px each side of the column', (t) async {
      size(t, const Size(400, 800));
      await mount(t);
      final bubble = lowest(t, find.byType(UserBubble));
      // No gutter on a touch phone: 400 - 2 = 398, column 334 from x 32.
      expect(t.getTopRight(bubble).dx, closeTo(366, 0.5));
    });
  });

  group('links', () {
    const docs = 'https://example.com/docs';
    Future<(List<Uri>, List<(String, int?)>)> openWithLinks(
      WidgetTester t,
    ) async {
      fx.answers = {
        19:
            'See [the docs]($docs), [main](src/main.dart#L12), '
            '[plain](notes/todo.md) and [bad](javascript:alert).',
      };
      final urls = <Uri>[];
      final files = <(String, int?)>[];
      await mount(
        t,
        host: ToolHostActions(
          openUrl: urls.add,
          openFile: (path, {line}) => files.add((path, line)),
        ),
      );
      return (urls, files);
    }

    testWidgets(
      'an http link opens the browser, a file link the preview at its line',
      (t) async {
        size(t, const Size(400, 800));
        final (urls, files) = await openWithLinks(t);
        await t.tapOnText(find.textRange.ofSubstring('the docs'));
        expect(urls.single.toString(), docs);
        await t.tapOnText(find.textRange.ofSubstring('main'));
        expect(files.last, ('src/main.dart', 12));
        await t.tapOnText(find.textRange.ofSubstring('plain'));
        expect(files.last, ('notes/todo.md', null));
        // An unsafe destination is neither a URL nor a file.
        await t.tapOnText(find.textRange.ofSubstring('bad'));
        expect(urls, hasLength(1));
        expect(files, hasLength(2));
      },
    );

    testWidgets('a file link is inert while the answer is still streaming', (
      t,
    ) async {
      size(t, const Size(400, 800));
      final files = <String>[];
      final urls = <Uri>[];
      await t.pumpWidget(
        dshTestApp(
          DshMarkdown(
            'a [file](x/y.dart#L3) and [web](https://example.com)',
            streaming: true,
            onOpenUrl: urls.add,
            onOpenFile: (p, {line}) => files.add(p),
          ),
        ),
      );
      await t.tapOnText(find.textRange.ofSubstring('file'));
      await t.tapOnText(find.textRange.ofSubstring('web'));
      expect(files, isEmpty);
      expect(urls, hasLength(1));
    });

    test('parseFileLink follows dsh: paths, line fragments, nothing else', () {
      expect(parseFileLink('a/b.dart'), (path: 'a/b.dart', line: null));
      expect(parseFileLink('a/b.dart#L24'), (path: 'a/b.dart', line: 24));
      expect(parseFileLink('a/b.dart#L24-L30'), (path: 'a/b.dart', line: 24));
      expect(parseFileLink('a%20b.dart'), (path: 'a b.dart', line: null));
      expect(parseFileLink('C:\\x\\y.txt'), isNotNull);
      for (final bad in [
        'https://example.com',
        'mailto:a@b.c',
        '//host/share',
        '#frag',
        'a.dart?x=1',
        'a.dart#L0',
        'a.dart#L5-L2',
        'a.dart#top',
        '%E0%A4%A',
        '',
      ]) {
        expect(parseFileLink(bad), isNull, reason: bad);
      }
    });
  });

  group('selection', () {
    testWidgets(
      'phone: a long press selects text with the platform toolbar, a touch outside the list clears it',
      (t) async {
        size(t, const Size(400, 800));
        final writes = watchClipboard(t);
        final slots = fx.registry();
        await t.runAsync(fx.open);
        await t.pumpWidget(
          dshTestApp(
            Column(
              children: [
                Expanded(child: fx.view(slots)),
                const SizedBox(height: 60, key: ValueKey('below-the-list')),
              ],
            ),
          ),
        );
        await settleFrames(t, 10);
        await t.longPress(find.text('Question 19'));
        await t.pump();
        expect(find.text('Copy'), findsOneWidget);
        await t.tap(find.text('Copy'));
        await t.pump();
        expect(writes.last, anyOf('Question', '19', 'Question 19'));
        await t.longPress(find.text('Question 19'));
        await t.pump();
        expect(find.text('Copy'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('below-the-list')));
        await t.pump();
        expect(find.text('Copy'), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'desktop: a mouse drag selects across messages and Ctrl+C copies it',
      (t) async {
        size(t, const Size(1280, 800));
        final writes = watchClipboard(t);
        await mount(t);
        final from =
            t.getTopLeft(find.text('Question 19')) + const Offset(1, 1);
        final to =
            t.getBottomRight(find.text('Answer 19')) - const Offset(1, 1);
        final mouse = await t.startGesture(from, kind: PointerDeviceKind.mouse);
        await mouse.moveTo(to);
        await mouse.up();
        await t.pump();
        await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.keyC);
        await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await t.pump();
        expect(writes, isNotEmpty);
        expect(writes.last, contains('Question 19'));
        expect(writes.last, contains('Answer 19'));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  });

  group('collapsing', () {
    testWidgets('a reasoning row you opened stays open after it scrolls away', (
      t,
    ) async {
      size(t, const Size(400, 800));
      final big = StreamFixture(turns: 80, first: 80);
      big.reasoning = {79: 'I weighed the two options carefully.'};
      fx = big;
      await mount(t);
      expect(find.text('I weighed the two options carefully.'), findsNothing);
      await t.tap(find.text('Think'));
      await settleFrames(t, 5);
      expect(find.text('I weighed the two options carefully.'), findsOneWidget);
      // Far enough that the row is no longer built, then back.
      for (var i = 0; i < 10; i++) {
        await t.drag(find.byType(ChatView), const Offset(0, 600));
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('I weighed the two options carefully.'), findsNothing);
      for (var i = 0; i < 12; i++) {
        await t.drag(find.byType(ChatView), const Offset(0, -600));
        await t.pump(const Duration(milliseconds: 16));
      }
      await settleFrames(t, 20);
      expect(find.text('I weighed the two options carefully.'), findsOneWidget);
    });
  });
}
