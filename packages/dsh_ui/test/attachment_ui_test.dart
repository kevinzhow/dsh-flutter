import 'dart:typed_data';

import 'package:dsh_highlight/dsh_highlight.dart';
import 'package:dsh_highlight/dsh_highlight_io.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('file types', () {
    test('classification follows dsh', () {
      expect(dshClassifyFileType('a/b/Report.PDF'), 'pdf');
      expect(dshClassifyFileType('notes.txt'), 'other');
      expect(dshClassifyFileType('LICENSE'), 'other');
      expect(dshClassifyFileType('readme'), 'markdown');
      expect(dshClassifyFileType('x.md'), 'markdown');
      expect(dshClassifyFileType('data.csv'), 'excel');
      expect(dshClassifyFileType('photo.jpeg'), 'image');
      expect(dshClassifyFileType('clip.mp4'), 'video');
      expect(dshClassifyFileType('doc.docx'), 'word');
      expect(dshClassifyFileType('deck.pptx'), 'ppt');
      expect(dshClassifyFileType('index.html'), 'html');
      // every code or configuration file draws the code glyph
      expect(dshClassifyFileType('main.dart'), 'code');
      expect(dshClassifyFileType('Dockerfile'), 'code');
      expect(dshClassifyFileType('CMakeLists.txt'), 'code');
      expect(dshClassifyFileType('app.component.ts'), 'code');
      expect(dshClassifyFileType(r'C:\src\a.py'), 'code');
    });

    test('extension and size text', () {
      expect(dshFileExtension('a/b.tar.GZ'), 'GZ');
      expect(dshFileExtension('noext'), '');
      expect(dshFileExtension('.env'), 'env');
      expect(dshFileSizeText(0), '0B');
      expect(dshFileSizeText(1023), '1023B');
      expect(dshFileSizeText(1536), '1.5KB');
      expect(dshFileSizeText(20 * 1024), '20KB');
      expect(dshFileSizeText(5 * 1024 * 1024), '5.0MB');
      expect(dshFileSizeText(3 * 1024 * 1024 * 1024), '3.0GB');
    });

    testWidgets('every glyph kind paints', (t) async {
      await t.pumpWidget(
        dshTestApp(
          Wrap(
            children: [
              for (final k in [
                'code',
                'excel',
                'folder',
                'html',
                'image',
                'markdown',
                'other',
                'pdf',
                'ppt',
                'video',
                'word',
              ])
                DshFileTypeIcon(key: ValueKey(k), kind: k, size: 28),
            ],
          ),
        ),
      );
      expect(find.byType(DshFileTypeIcon), findsNWidgets(11));
      expect(t.takeException(), isNull);
    });
  });

  group('image fit', () {
    test('a lone image is 240 on its longer edge, clamped, never upscaled', () {
      expect(dshSingleFit(320, 200).width, 240);
      expect(dshSingleFit(320, 200).height, 150);
      expect(dshSingleFit(200, 320).height, 240);
      // aspect clamped to [0.25, 4]
      final wide = dshSingleFit(4000, 100);
      expect((wide.width, wide.height), (240, 60));
      expect(wide.alignment, Alignment.centerLeft);
      final tall = dshSingleFit(100, 4000);
      expect((tall.width, tall.height), (60, 240));
      expect(tall.alignment, Alignment.topCenter);
      // never upscaled past the natural size
      final small = dshSingleFit(60, 30);
      expect((small.width, small.height), (60, 30));
    });
  });

  group('syntax highlighter over the real grammars', () {
    late DshSyntaxHighlighter h;
    setUpAll(() async {
      h = DshSyntaxHighlighter(
        HighlightEngine(FileGrammarSource('../dsh_highlight/assets/grammars')),
      );
      await h.engine.load('typescript');
      await h.engine.load('python');
    });

    test('colours by dsh classes; unknown languages are plain', () {
      final lines = h.highlight('const answer = 42', 'ts')!;
      expect(lines.single.first.text, 'const');
      expect(lines.single.first.token, DshCodeToken.keyword);
      expect(lines.single.any((s) => s.token == DshCodeToken.constant), isTrue);
      expect(h.highlight('x', 'brainfuck'), isNull);
      expect(h.highlight('x', null), isNull);
    });

    test(
      'a language that is not loaded yet answers null and then loads',
      () async {
        expect(h.highlight('print(1)', 'rb'), isNull);
        final loaded = h.loaded.first;
        h.prepare('rb');
        await loaded;
        expect(h.highlight('puts 1', 'rb'), isNotNull);
      },
    );

    test('line count follows the text, even with a trailing newline', () {
      expect(h.highlight('a = 1\n', 'py')!.length, 2);
      expect(h.highlight('a = 1\n\n\n', 'py')!.length, 4);
    });
  });

  group('code surfaces', () {
    late DshSyntaxHighlighter h;
    setUpAll(() async {
      h = DshSyntaxHighlighter(
        HighlightEngine(FileGrammarSource('../dsh_highlight/assets/grammars')),
      );
      await h.engine.load('typescript');
    });

    const labels = DshCodeToolbarLabels(
      codeLabel: 'Code',
      wrapLabel: 'Wrap',
      unwrapLabel: 'No wrap',
      copy: 'Copy',
      copied: 'Copied',
    );

    testWidgets('a code block colours its tokens and numbers its lines', (
      t,
    ) async {
      await t.pumpWidget(
        dshTestApp(
          DshCodeHighlighting(
            highlighter: h,
            child: const DshCodeBlock(
              code: 'const a = 1\nlet b = 2\n',
              lang: 'typescript',
              labels: labels,
              lineNumbers: true,
            ),
          ),
        ),
      );
      expect(find.text('ts'), findsNothing);
      expect(find.text('typescript'), findsOneWidget);
      expect(find.byKey(const ValueKey('code-line-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('code-line-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('code-line-3')), findsNothing);
      final rich = t.widget<RichText>(
        find
            .descendant(
              of: find.byKey(const ValueKey('code-line-1')),
              matching: find.byType(RichText),
            )
            .last,
      );
      final colours = <Color?>{};
      rich.text.visitChildren((s) {
        if (s is TextSpan && s.text != null) colours.add(s.style?.color);
        return true;
      });
      expect(colours.length, greaterThan(1));
    });

    testWidgets('without a highlighter the block is plain monospace', (
      t,
    ) async {
      await t.pumpWidget(
        dshTestApp(
          const DshCodeBlock(
            code: 'const a = 1',
            lang: 'typescript',
            labels: labels,
          ),
        ),
      );
      expect(find.text('const a = 1', findRichText: true), findsOneWidget);
    });

    testWidgets('wrap toggles between wrapped text and a sideways scroller', (
      t,
    ) async {
      await t.pumpWidget(
        dshTestApp(const DshCodeBlock(code: 'a long line', labels: labels)),
      );
      expect(find.byType(SingleChildScrollView), findsNothing);
      await t.tap(find.byKey(const ValueKey('code-wrap')));
      await t.pump();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('file card', () {
    const labels = DshFileCardLabels(
      label: 'Pending files',
      remove: 'Remove',
      uploading: 'Uploading…',
      failed: 'Failed',
      retry: 'Retry',
    );

    Widget card(
      DshFileCardState state, {
      double? progress,
      VoidCallback? onRetry,
    }) => dshTestApp(
      Center(
        child: DshFileCard(
          name: 'report.pdf',
          bytes: 2048,
          state: state,
          progress: progress,
          labels: labels,
          onRemove: () {},
          onRetry: onRetry ?? () {},
          forceRemoveVisible: true,
        ),
      ),
    );

    testWidgets('240 by 64 with the extension and size', (t) async {
      await t.pumpWidget(card(DshFileCardState.ready));
      expect(
        t.getSize(find.byKey(const ValueKey('file-card'))),
        const Size(240, 64),
      );
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('PDF 2.0KB'), findsOneWidget);
    });

    testWidgets('uploading shows the status and a determinate bar', (t) async {
      await t.pumpWidget(card(DshFileCardState.uploading, progress: 0.25));
      await t.pump();
      expect(find.text('Uploading…'), findsOneWidget);
      expect(
        t.widget<DshProgressTrack>(find.byType(DshProgressTrack)).progress,
        0.25,
      );
    });

    testWidgets('an error card retries on tap', (t) async {
      var retries = 0;
      await t.pumpWidget(
        card(DshFileCardState.error, onRetry: () => retries++),
      );
      expect(find.text('Failed'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('file-card-retry')));
      expect(retries, 1);
    });

    testWidgets(
      'the remove badge is hidden without hover on desktop and with a touch screen shown',
      (t) async {
        await t.pumpWidget(
          dshTestApp(
            Center(
              child: DshFileCard(
                name: 'a.txt',
                bytes: 1,
                state: DshFileCardState.ready,
                labels: labels,
                onRemove: () {},
                onRetry: () {},
                forceRemoveVisible: false,
              ),
            ),
          ),
        );
        expect(
          t
              .widget<Opacity>(
                find.descendant(
                  of: find.byKey(const ValueKey('file-card-remove')),
                  matching: find.byType(Opacity),
                ),
              )
              .opacity,
          0,
        );
      },
    );
  });

  testWidgets('the lightbox keeps the bytes it was given', (t) async {
    await t.pumpWidget(
      dshTestApp(
        DshLightbox(
          images: [DshLightboxImage(label: 'x', bytes: Uint8List(0))],
          labels: DshLightboxLabels(
            dialog: 'Preview',
            close: 'Close',
            loadFailed: 'Failed',
            position: (i, n) => '$i / $n',
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('lightbox-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('lightbox-position')), findsNothing);
  });
}
