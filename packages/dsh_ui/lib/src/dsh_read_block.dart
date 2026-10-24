import 'package:flutter/widgets.dart';

import 'dsh_code_highlight.dart';
import 'dsh_code_toolbar.dart';
import 'dsh_copy_feedback.dart';
import 'dsh_corners.dart';
import 'dsh_diff_block.dart' show DshFoldLabels;
import 'dsh_head_tail_cap.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// Content lines shown before the middle collapses (dsh `DEFAULT_READ_MAX_LINES`).
const int defaultReadMaxLines = 16;

class DshReadLine {
  const DshReadLine(this.number, this.text);
  final int number;
  final String text;
}

class DshReadLabels {
  const DshReadLabels({
    required this.toolbar,
    required this.fold,
    required this.window,
  });
  final DshCodeToolbarLabels toolbar;
  final DshFoldLabels fold;
  final String Function(int shown, int total) window;
}

/// A line-numbered window of a file (dsh `ReadBlock`).
class DshReadBlock extends StatefulWidget {
  const DshReadBlock({
    super.key,
    required this.lines,
    required this.totalLines,
    required this.labels,
    this.label,
    this.lang,
    this.maxLines = defaultReadMaxLines,
  });

  final String? label;
  final List<DshReadLine> lines;
  final int totalLines;
  final String? lang;
  final int maxLines;
  final DshReadLabels labels;

  @override
  State<DshReadBlock> createState() => _DshReadBlockState();
}

class _DshReadBlockState extends State<DshReadBlock>
    with DshCopyFeedback, DshHighlightListener {
  bool _expanded = false;
  bool _wrapped = false;

  @override
  String? get highlightLang => widget.lang;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final w = widget;
    final style = theme.textStyle('--dsw-font-markdown-code-block');
    final digits = w.lines.fold<int>(
      3,
      (d, l) => d > '${l.number}'.length ? d : '${l.number}'.length,
    );
    // `ch`: the advance of "0" in the code font.
    final painter = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final gutter = painter.width * digits;
    final cap = headTailCap(w.lines.length, w.maxLines, _expanded);
    final head = cap.capped ? w.lines.sublist(0, cap.headLines) : w.lines;
    final tail = cap.capped
        ? w.lines.sublist(w.lines.length - cap.tailLines)
        : const <DshReadLine>[];
    final windowed = w.lines.length < w.totalLines;
    final raw = w.lines.map((l) => l.text).join('\n');
    final lineHeight = style.height! * style.fontSize!;
    // Whole-window highlighting keeps multi-line grammar state; the gutter and
    // the copied text stay plain.
    final highlighted = DshCodeHighlighting.of(context)?.highlight(raw, w.lang);
    final foreground = style.copyWith(color: theme.labelPrimary);

    Widget content(int index, DshReadLine l) {
      final spans = highlighted != null && index < highlighted.length
          ? highlighted[index]
          : null;
      if (spans == null) {
        return _wrapped
            ? Expanded(
                child: DshChromeText(
                  dshWrapBreaks(l.text),
                  style: foreground,
                  strutStyle: dshStrut(foreground),
                ),
              )
            : DshChromeText(
                l.text,
                softWrap: false,
                style: foreground,
                strutStyle: dshStrut(foreground),
              );
      }
      final text = Text.rich(
        TextSpan(
          children: dshStyledSpans(context, spans, foreground, wrap: _wrapped),
        ),
        softWrap: _wrapped,
        style: foreground,
        strutStyle: dshStrut(foreground),
      );
      return _wrapped ? Expanded(child: text) : text;
    }

    Widget line(int index, DshReadLine l) => ConstrainedBox(
      constraints: BoxConstraints(minHeight: lineHeight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutter,
            child: DshChromeText(
              '${l.number}',
              textAlign: TextAlign.right,
              softWrap: false,
              style: style.copyWith(
                color: theme.color('--dsw-alias-label-tertiary'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          content(index, l),
        ],
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < head.length; i++) line(i, head[i]),
        if (cap.hidden > 0)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: EdgeInsets.only(left: gutter + 12),
              child: DshChromeText(
                _expanded
                    ? w.labels.fold.collapse
                    : w.labels.fold.expand(cap.hidden),
                key: const ValueKey('read-fold'),
                style: style.copyWith(
                  color: theme.color('--dsw-alias-label-tertiary'),
                ),
              ),
            ),
          ),
        for (var i = 0; i < tail.length; i++)
          line(w.lines.length - tail.length + i, tail[i]),
      ],
    );

    return DshDecoratedBox(
      key: const ValueKey('read-block'),
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
            DshCodeToolbar(
              labels: w.labels.toolbar,
              lang: w.lang,
              title: w.label,
              status: windowed
                  ? w.labels.window(w.lines.length, w.totalLines)
                  : null,
              copied: copied,
              wrapped: _wrapped,
              onCopy: w.lines.isEmpty ? null : () => copyText(raw),
              onWrap: () => setState(() => _wrapped = !_wrapped),
            ),
            DshCodeBody(wrapped: _wrapped, child: body),
          ],
        ),
      ),
    );
  }
}
