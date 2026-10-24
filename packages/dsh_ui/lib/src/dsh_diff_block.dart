import 'package:flutter/widgets.dart';

import 'dsh_code_language.dart';
import 'dsh_code_toolbar.dart';
import 'dsh_copy_feedback.dart';
import 'dsh_diff.dart';
import 'dsh_head_tail_cap.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// Body lines before the middle collapses (dsh `DEFAULT_DIFF_MAX_LINES`).
const int defaultDiffMaxLines = 16;

class DshFoldLabels {
  const DshFoldLabels({required this.collapse, required this.expand});
  final String collapse;
  final String Function(int hidden) expand;
}

/// [fill] (a translucent token) over the opaque [under] with the 8-bit
/// premultiplied arithmetic Chromium paints with, so the row lands on the same
/// pixel values as dsh's web client (Skia's float blend is off by one).
Color blendLikeChromium(Color fill, Color under) {
  final a = (fill.a * 255).round();
  int channel(double src, double dst) {
    final s = (src * 255).round();
    final d = (dst * 255).round();
    final premul = (s * a / 255).round();
    final rest = (d * (255 - a) / 255).floor();
    return (premul + rest).clamp(0, 255);
  }

  return Color.from(
    alpha: 1,
    red: channel(fill.r, under.r) / 255,
    green: channel(fill.g, under.g) / 255,
    blue: channel(fill.b, under.b) / 255,
  );
}

/// CSS `saturate(amount)` on an opaque colour, as Chromium's colour matrix
/// computes it (dsh's menu surfaces filter their backdrop with
/// `saturate(150%)` before the translucent fill lands on it).
Color saturateLikeChromium(Color c, double amount) {
  final r = c.r * 255, g = c.g * 255, b = c.b * 255;
  double mix(double a, double bb, double cc) =>
      (a * r + bb * g + cc * b).clamp(0, 255);
  final s = amount;
  return Color.from(
    alpha: 1,
    red:
        mix(
          0.213 + 0.787 * s,
          0.715 - 0.715 * s,
          0.072 - 0.072 * s,
        ).roundToDouble() /
        255,
    green:
        mix(
          0.213 - 0.213 * s,
          0.715 + 0.285 * s,
          0.072 - 0.072 * s,
        ).roundToDouble() /
        255,
    blue:
        mix(
          0.213 - 0.213 * s,
          0.715 - 0.715 * s,
          0.072 + 0.928 * s,
        ).roundToDouble() /
        255,
  );
}

/// A file mutation as an inline diff surface (dsh `DiffBlock`): a toolbar with
/// the language, then the path header, context lines and `-`/`+` rows with
/// their colour bars; the middle folds past [maxLines].
class DshDiffBlock extends StatefulWidget {
  const DshDiffBlock({
    super.key,
    required this.diffs,
    required this.toolbar,
    required this.fold,
    this.maxLines = defaultDiffMaxLines,
  });

  final List<DshDiffHunk> diffs;
  final DshCodeToolbarLabels toolbar;
  final DshFoldLabels fold;
  final int maxLines;

  @override
  State<DshDiffBlock> createState() => _DshDiffBlockState();
}

class _DshDiffBlockState extends State<DshDiffBlock> with DshCopyFeedback {
  bool _expanded = false;
  bool _wrapped = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final rows = buildDiffRows(widget.diffs);
    if (rows.isEmpty) return const SizedBox.shrink();
    final firstLang = dshLanguageForPath(widget.diffs.first.path);
    final lang =
        widget.diffs.every((d) => dshLanguageForPath(d.path) == firstLang)
        ? firstLang
        : null;
    final style = theme.textStyle('--dsw-font-markdown-code-block');
    final lineHeight = style.height! * style.fontSize!;
    final cap = headTailCap(rows.length, widget.maxLines, _expanded);
    final head = cap.capped ? rows.sublist(0, cap.headLines) : rows;
    final tail = cap.capped
        ? rows.sublist(rows.length - cap.tailLines)
        : const <DshDiffRow>[];

    Widget row(DshDiffRow r) {
      final (prefix, color, bg, bar) = switch (r.kind) {
        DshDiffRowKind.del => (
          '- ',
          theme.color('--dsw-alias-state-error-primary'),
          blendLikeChromium(
            theme.color('--dsw-alias-code-diff-deleted'),
            theme.color('--dsw-alias-markdown-code-block'),
          ),
          theme.color('--dsw-alias-state-error-primary'),
        ),
        DshDiffRowKind.add => (
          '+ ',
          theme.color('--dsw-alias-state-success-primary'),
          blendLikeChromium(
            theme.color('--dsw-alias-code-diff-added'),
            theme.color('--dsw-alias-markdown-code-block'),
          ),
          theme.color('--dsw-alias-state-success-primary'),
        ),
        DshDiffRowKind.context => ('  ', theme.labelSecondary, null, null),
        DshDiffRowKind.path => ('', theme.labelSecondary, null, null),
        DshDiffRowKind.gap => (
          '',
          theme.color('--dsw-alias-label-tertiary'),
          null,
          null,
        ),
      };
      Widget text = DshChromeText(
        '$prefix${r.text}',
        softWrap: _wrapped,
        style: style.copyWith(
          color: color,
          fontWeight: r.kind == DshDiffRowKind.path ? FontWeight.w500 : null,
        ),
      );
      text = ConstrainedBox(
        constraints: BoxConstraints(minHeight: lineHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: text,
        ),
      );
      if (bg == null) return text;
      return DshDecoratedBox(
        decoration: BoxDecoration(color: bg),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(color: bar!),
            ),
            text,
          ],
        ),
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final r in head) row(r),
        if (cap.hidden > 0)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: DshChromeText(
                _expanded
                    ? widget.fold.collapse
                    : widget.fold.expand(cap.hidden),
                key: const ValueKey('diff-fold'),
                style: style.copyWith(
                  color: theme.color('--dsw-alias-label-tertiary'),
                ),
              ),
            ),
          ),
        for (final r in tail) row(r),
      ],
    );

    return DshDecoratedBox(
      key: const ValueKey('diff-block'),
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
              labels: widget.toolbar,
              lang: lang,
              copied: copied,
              wrapped: _wrapped,
              onCopy: () => copyText(diffCopyText(rows)),
              onWrap: () => setState(() => _wrapped = !_wrapped),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 20),
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
