import 'package:flutter/widgets.dart';

import 'dsh_code_highlight.dart';
import 'dsh_code_toolbar.dart';
import 'dsh_copy_feedback.dart';
import 'dsh_corners.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// Source split into lines with their colour spans (plain when no highlighter
/// is ambient or the grammar is not there yet).
List<List<DshCodeSpan>> dshCodeLines(
  String code,
  String? lang,
  DshCodeHighlighter? highlighter,
) {
  final highlighted = highlighter?.highlight(code, lang);
  if (highlighted != null) return highlighted;
  return [
    for (final line in code.split('\n')) [DshCodeSpan(line)],
  ];
}

/// dsh's `CodeBlock` in its card form: the toolbar (language, wrap, copy), then
/// the source in `--dsw-font-markdown-code-block`, optionally with a
/// line-number gutter. Used for markdown fences and the file preview's code
/// renderer.
class DshCodeBlock extends StatefulWidget {
  const DshCodeBlock({
    super.key,
    required this.code,
    required this.labels,
    this.lang,
    this.lineNumbers = false,
    this.showHeader = true,
    this.wrap,
  });

  /// The source, verbatim (one trailing newline is trimmed for display).
  final String code;
  final String? lang;
  final DshCodeToolbarLabels labels;

  /// A numbered gutter that does not enter the copied text.
  final bool lineNumbers;
  final bool showHeader;

  /// An owner-controlled wrap preference; null keeps the block's own toggle
  /// (default on, like dsh).
  final bool? wrap;

  @override
  State<DshCodeBlock> createState() => _DshCodeBlockState();
}

class _DshCodeBlockState extends State<DshCodeBlock>
    with DshCopyFeedback, DshHighlightListener {
  bool _wrapped = true;

  @override
  String? get highlightLang => widget.lang;

  String get _trimmed => widget.code.endsWith('\n')
      ? widget.code.substring(0, widget.code.length - 1)
      : widget.code;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final wrapped = widget.wrap ?? _wrapped;
    final trimmed = _trimmed;
    final lines = dshCodeLines(
      trimmed,
      widget.lang,
      DshCodeHighlighting.of(context),
    );
    final style = theme.textStyle('--dsw-font-markdown-code-block');
    final body = DshCodeLines(
      lines: lines,
      style: style,
      wrap: wrapped,
      lineNumbers: widget.lineNumbers,
    );
    return DecoratedBox(
      key: const ValueKey('code-block'),
      decoration: theme.cornerDecoration(
        theme.radiusLg,
        color: theme.color('--dsw-alias-markdown-code-block'),
      ),
      child: theme.clipCorners(
        theme.radiusLg,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showHeader)
              DshCodeToolbar(
                labels: widget.labels,
                lang: widget.lang,
                copied: copied,
                wrapped: wrapped,
                onCopy: () => copyText(trimmed),
                onWrap: widget.wrap == null
                    ? () => setState(() => _wrapped = !_wrapped)
                    : null,
              ),
            DshCodeBody(wrapped: wrapped, child: body),
          ],
        ),
      ),
    );
  }
}

/// The lines of a code surface: one rich text when unnumbered, rows with a
/// right-aligned gutter (`max(2, digits)` characters wide, 12 before the text)
/// when numbered. [firstLine] is the number of the first line.
class DshCodeLines extends StatelessWidget {
  const DshCodeLines({
    super.key,
    required this.lines,
    required this.style,
    required this.wrap,
    this.lineNumbers = false,
    this.firstLine = 1,
    this.highlightedLine,
  });

  final List<List<DshCodeSpan>> lines;
  final TextStyle style;
  final bool wrap;
  final bool lineNumbers;
  final int firstLine;

  /// A 1-based line number to mark (the navigation target).
  final int? highlightedLine;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final foreground = style.copyWith(color: theme.color('--shiki-foreground'));
    if (!lineNumbers) {
      return Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) TextSpan(text: '\n', style: foreground),
              ...dshStyledSpans(context, lines[i], foreground, wrap: wrap),
            ],
          ],
        ),
        softWrap: wrap,
        style: foreground,
        strutStyle: dshStrut(foreground),
      );
    }
    final last = firstLine + lines.length - 1;
    final digits = last.toString().length < 2 ? 2 : last.toString().length;
    final painter = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final gutter = painter.width * digits;
    final number = style.copyWith(
      color: theme.color('--dsw-alias-label-tertiary'),
    );
    final lineHeight = style.height! * style.fontSize!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lines.length; i++)
          DshCodeLine(
            number: firstLine + i,
            spans: lines[i],
            gutter: gutter,
            numberStyle: number,
            textStyle: foreground,
            minHeight: lineHeight,
            wrap: wrap,
            marked: highlightedLine == firstLine + i,
          ),
      ],
    );
  }
}

/// One numbered source line.
class DshCodeLine extends StatelessWidget {
  const DshCodeLine({
    super.key,
    required this.number,
    required this.spans,
    required this.gutter,
    required this.numberStyle,
    required this.textStyle,
    required this.minHeight,
    required this.wrap,
    this.marked = false,
  });

  final int number;
  final List<DshCodeSpan> spans;
  final double gutter;
  final TextStyle numberStyle;
  final TextStyle textStyle;
  final double minHeight;
  final bool wrap;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final text = Text.rich(
      TextSpan(children: dshStyledSpans(context, spans, textStyle, wrap: wrap)),
      softWrap: wrap,
      style: textStyle,
      strutStyle: dshStrut(textStyle),
    );
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: gutter,
          child: DshChromeText(
            '$number',
            textAlign: TextAlign.right,
            softWrap: false,
            style: numberStyle,
          ),
        ),
        const SizedBox(width: 12),
        if (wrap) Expanded(child: text) else text,
      ],
    );
    return ConstrainedBox(
      key: ValueKey('code-line-$number'),
      constraints: BoxConstraints(minHeight: minHeight),
      child: marked
          ? ColoredBox(
              color: theme.color('--dsw-alias-interactive-bg-hover'),
              child: row,
            )
          : row,
    );
  }
}
