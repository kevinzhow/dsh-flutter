import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {double width = 584}) => dshTestApp(
  Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: width, child: child),
  ),
);

Finder prose(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is Text && (widget.data ?? widget.textSpan?.toPlainText()) == text,
);

Iterable<TextSpan> spans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* spans(child);
    }
  }
}

const codeLabels = DshCodeToolbarLabels(
  codeLabel: 'Code',
  wrapLabel: 'Wrap',
  unwrapLabel: 'Unwrap',
  copy: 'Copy',
  copied: 'Copied',
);

void main() {
  testWidgets('explanation uses the source collapsed block margins', (t) async {
    await t.pumpWidget(
      host(
        const DshReaderMarkdown(
          '### First\n\nOne paragraph.\n\n### Second\n\nAnother paragraph.',
          exampleLabel: 'Example task',
        ),
      ),
    );
    // PresetGuideDialog.module.css: h3 24px, bottom 10; p 26px,
    // bottom 16; next h3 top 28 (collapsed with the preceding 16).
    expect(t.getRect(prose('First')).top, 0);
    expect(t.getSize(prose('First')).height, 24);
    expect(t.getRect(prose('One paragraph.')).top, 34);
    expect(t.getSize(prose('One paragraph.')).height, 26);
    expect(t.getRect(prose('Second')).top, 88);
    expect(t.getRect(prose('Another paragraph.')).top, 122);
    expect(t.getSize(find.byType(DshReaderMarkdown)).height, 148);
  });

  testWidgets('explanation quote has a filled frame and no left border', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        const DshReaderMarkdown(
          'Before.\n\n> Quoted.\n\nAfter.',
          exampleLabel: 'Example task',
        ),
      ),
    );
    // The source collapses p bottom 16 with quote top 10, then quote
    // bottom 14 with p top 0. Quote padding is 14px by 16px.
    expect(t.getRect(prose('Before.')).top, 0);
    expect(t.getRect(prose('Quoted.')).top, 56);
    expect(t.getRect(prose('Quoted.')).left, 16);
    expect(t.getRect(prose('After.')).top, 110);
    expect(t.getSize(find.byType(DshReaderMarkdown)).height, 136);
    final quote = t.widget<DshDecoratedBox>(find.byType(DshDecoratedBox));
    final decoration = quote.decoration as BoxDecoration;
    expect(decoration.color, isNotNull);
    expect(decoration.border, isNull);
    expect(decoration.borderRadius, BorderRadius.circular(16));
  });

  testWidgets('usage sections match the real heading, tag and quote flow', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        const DshReaderMarkdown(
          '### One\n\n> Task one.\n\nExpected one.\n\n'
          '### Two\n\n> Task two.\n\nExpected two.',
          usage: true,
          exampleLabel: '示例任务',
        ),
      ),
    );
    expect(t.getRect(prose('One')).top, 0);
    expect(t.getRect(prose('Task one.')).top, 44);
    expect(t.getRect(prose('Expected one.')).top, 90);
    expect(t.getSize(prose('Expected one.')).height, 22);
    expect(t.getRect(prose('Two')).top, 140);
    expect(t.getRect(prose('Expected two.')).top, 230);
    expect(t.getSize(find.byType(DshReaderMarkdown)).height, 252);
    expect(t.widgetList<DshTag>(find.byType(DshTag)).map((tag) => tag.tone), [
      DshTagTone.neutral,
      DshTagTone.neutral,
    ]);
    final icons = t.widgetList<DshIcon>(find.byType(DshIcon)).toList();
    expect(icons, hasLength(2));
    expect(icons.every((icon) => icon.size == 12), isTrue);
    expect(prose('示例任务'), findsNWidgets(2));
  });

  testWidgets('usage header wraps the complete tag beneath a long title', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        const DshReaderMarkdown(
          '### A longer title\n\n> Task.',
          usage: true,
          exampleLabel: 'Example task',
        ),
        width: 170,
      ),
    );
    final title = t.getRect(prose('A longer title'));
    final tag = t.getRect(find.byType(DshTag));
    expect(tag.top, title.bottom + 8);
    expect(tag.left, title.left);
    expect(t.takeException(), isNull);
  });

  testWidgets('reader preserves inline styles and actual link callbacks', (
    t,
  ) async {
    Uri? opened;
    await t.pumpWidget(
      host(
        DshReaderMarkdown(
          '**Bold** *italic* `value` [link](https://example.test)',
          exampleLabel: 'Example task',
          onOpenUrl: (url) => opened = url,
        ),
      ),
    );
    final text = t.widget<Text>(prose('Bold italic value link'));
    final all = spans(text.textSpan!).toList();
    expect(
      all.singleWhere((span) => span.text == 'Bold').style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      all.singleWhere((span) => span.text == 'italic').style?.fontStyle,
      FontStyle.italic,
    );
    expect(
      all.singleWhere((span) => span.text == 'value').style?.backgroundColor,
      isNotNull,
    );
    final link = all.singleWhere((span) => span.text == 'link');
    (link.recognizer! as TapGestureRecognizer).onTap!();
    expect(opened, Uri.parse('https://example.test'));
  });

  testWidgets('reader retains selectable Markdown and fenced code cards', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        const DshReaderMarkdown(
          'Selectable.\n\n```dart\nprint(1);\n```',
          exampleLabel: 'Example task',
          selectable: true,
          codeLabels: codeLabels,
        ),
      ),
    );
    expect(find.byType(SelectableText), findsWidgets);
    expect(find.byType(DshCodeBlock), findsOneWidget);
    expect(t.widget<DshCodeBlock>(find.byType(DshCodeBlock)).lang, 'dart');
    expect(find.byKey(const ValueKey('code-copy')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('default Markdown keeps its original styles and code renderer', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        const DshMarkdown(
          '### Heading\n\nBody.\n\n> Quote.\n\n```dart\nprint(1);\n```',
          codeLabels: codeLabels,
        ),
      ),
    );
    final markdown = t.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown.runtimeType, MarkdownBody);
    expect(markdown.styleSheet!.blockSpacing, 8);
    expect(
      (markdown.styleSheet!.blockquoteDecoration! as BoxDecoration).border,
      isNotNull,
    );
    expect(markdown.styleSheet!.p!.fontSize, 14);
    expect(markdown.styleSheet!.p!.height, 24 / 14);
    expect(find.byType(DshCodeBlock), findsOneWidget);
    expect(find.byKey(const ValueKey('code-copy')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
