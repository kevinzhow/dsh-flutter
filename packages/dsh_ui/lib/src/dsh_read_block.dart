import 'package:flutter/widgets.dart';

import 'dsh_code_toolbar.dart';
import 'dsh_copy_feedback.dart';
import 'dsh_diff_block.dart' show DshFoldLabels;
import 'dsh_head_tail_cap.dart';
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

class _DshReadBlockState extends State<DshReadBlock> with DshCopyFeedback {
  bool _expanded = false;
  bool _wrapped = false;

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

    Widget line(DshReadLine l) => ConstrainedBox(
      constraints: BoxConstraints(minHeight: lineHeight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutter,
            child: Text(
              '${l.number}',
              textAlign: TextAlign.right,
              style: style.copyWith(
                color: theme.color('--dsw-alias-label-tertiary'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _wrapped
              ? Expanded(
                  child: Text(
                    l.text,
                    style: style.copyWith(color: theme.labelPrimary),
                  ),
                )
              : Text(
                  l.text,
                  softWrap: false,
                  style: style.copyWith(color: theme.labelPrimary),
                ),
        ],
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in head) line(l),
        if (cap.hidden > 0)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: EdgeInsets.only(left: gutter + 12),
              child: Text(
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
        for (final l in tail) line(l),
      ],
    );

    return DecoratedBox(
      key: const ValueKey('read-block'),
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-markdown-code-block'),
        borderRadius: BorderRadius.circular(theme.radiusLg),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.radiusLg),
        child: Column(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
              child: _wrapped
                  ? body
                  : LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                          ),
                          child: IntrinsicWidth(child: body),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
