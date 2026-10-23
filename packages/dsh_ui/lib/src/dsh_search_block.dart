import 'package:flutter/widgets.dart';

import 'dsh_copy_feedback.dart';
import 'dsh_head_tail_cap.dart';
import 'theme_access.dart';

const int defaultSearchMaxLines = 16;

class DshSearchMatch {
  const DshSearchMatch(this.lineNumber, this.line);
  final int lineNumber;
  final String line;
}

class DshSearchFile {
  const DshSearchFile(this.path, this.matches);
  final String path;
  final List<DshSearchMatch> matches;
}

class DshSearchLabels {
  const DshSearchLabels({
    required this.pathsSummary,
    required this.matchesSummary,
    required this.copy,
    required this.copied,
    required this.noResults,
    required this.collapse,
    required this.expand,
  });

  final String Function(int shown, int total, bool truncated) pathsSummary;
  final String Function(int shown, int total, int files, bool truncated)
  matchesSummary;
  final String copy;
  final String copied;
  final String noResults;
  final String collapse;
  final String Function(int hidden) expand;
}

sealed class _Row {
  const _Row();
}

class _FileRow extends _Row {
  const _FileRow(this.path, this.count, this.index, this.collapsed);
  final String path;
  final int count;
  final int index;
  final bool collapsed;
}

class _MatchRow extends _Row {
  const _MatchRow(this.lineNumber, this.line, this.fileIndex);
  final int lineNumber;
  final String line;
  final int fileIndex;
}

class _PathRow extends _Row {
  const _PathRow(this.path);
  final String path;
}

/// Grouped grep matches or a glob path list (dsh `SearchBlock`): a summary
/// banner with copy, then rows; per-file groups collapse, the middle folds.
class DshSearchBlock extends StatefulWidget {
  const DshSearchBlock.matches({
    super.key,
    required List<DshSearchFile> this.files,
    required this.truncated,
    required this.total,
    required this.labels,
    this.maxLines = defaultSearchMaxLines,
  }) : paths = null;

  const DshSearchBlock.paths({
    super.key,
    required List<String> this.paths,
    required this.truncated,
    required this.total,
    required this.labels,
    this.maxLines = defaultSearchMaxLines,
  }) : files = null;

  final List<DshSearchFile>? files;
  final List<String>? paths;
  final bool truncated;
  final int total;
  final int maxLines;
  final DshSearchLabels labels;

  @override
  State<DshSearchBlock> createState() => _DshSearchBlockState();
}

class _DshSearchBlockState extends State<DshSearchBlock> with DshCopyFeedback {
  bool _expanded = false;
  final Set<int> _collapsed = {};

  List<_Row> _rows() {
    final paths = widget.paths;
    if (paths != null) return [for (final p in paths) _PathRow(p)];
    final rows = <_Row>[];
    final files = widget.files!;
    for (var i = 0; i < files.length; i++) {
      final collapsed = _collapsed.contains(i);
      rows.add(_FileRow(files[i].path, files[i].matches.length, i, collapsed));
      if (collapsed) continue;
      for (final m in files[i].matches) {
        rows.add(_MatchRow(m.lineNumber, m.line, i));
      }
    }
    return rows;
  }

  String _copyText() {
    final paths = widget.paths;
    if (paths != null) return paths.join('\n');
    return widget.files!
        .map(
          (f) => [
            f.path,
            ...f.matches.map((m) => '${m.lineNumber}: ${m.line}'),
          ].join('\n'),
        )
        .join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final w = widget;
    final labels = w.labels;
    final rows = _rows();
    final shown = w.paths != null
        ? w.paths!.length
        : w.files!.fold<int>(0, (s, f) => s + f.matches.length);
    final summary = w.paths != null
        ? labels.pathsSummary(shown, w.total, w.truncated)
        : labels.matchesSummary(shown, w.total, w.files!.length, w.truncated);
    final empty = rows.isEmpty;
    final code = theme.textStyle('--dsw-font-markdown-code-block');
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final cap = headTailCap(rows.length, w.maxLines, _expanded);
    final head = cap.capped ? rows.sublist(0, cap.headLines) : rows;
    final natural = cap.capped
        ? rows.sublist(rows.length - cap.tailLines)
        : const <_Row>[];
    final lead = natural.isEmpty ? null : natural.first;
    _FileRow? tailHeader;
    if (lead is _MatchRow &&
        !head.any((r) => r is _FileRow && r.index == lead.fileIndex)) {
      tailHeader = rows.whereType<_FileRow>().firstWhere(
        (r) => r.index == lead.fileIndex,
      );
    }
    final tail = tailHeader == null ? natural : natural.sublist(1);

    Widget render(_Row row) => switch (row) {
      _PathRow(:final path) => _line(
        Text(
          path,
          softWrap: false,
          style: code.copyWith(color: theme.labelPrimary),
        ),
      ),
      _MatchRow(:final lineNumber, :final line) => _line(
        Text.rich(
          TextSpan(
            style: code.copyWith(color: theme.labelPrimary),
            children: [
              TextSpan(
                text: '$lineNumber: ',
                style: TextStyle(color: tertiary),
              ),
              TextSpan(text: line),
            ],
          ),
          softWrap: false,
        ),
      ),
      _FileRow() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          if (!_collapsed.add(row.index)) _collapsed.remove(row.index);
        }),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    row.path,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: code.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.labelPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${row.count}', style: code.copyWith(color: tertiary)),
              ],
            ),
          ),
        ),
      ),
    };

    return DecoratedBox(
      key: const ValueKey('search-block'),
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
            ColoredBox(
              color: theme.color('--dsw-alias-markdown-code-block-banner'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme
                            .textStyle('--dsw-font-xs-13')
                            .copyWith(color: theme.labelSecondary),
                      ),
                    ),
                    if (!empty) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => copyText(_copyText()),
                        child: Text(
                          copied ? labels.copied : labels.copy,
                          key: const ValueKey('search-copy'),
                          style: theme
                              .textStyle('--dsw-font-xs-13')
                              .copyWith(color: theme.labelSecondary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (empty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Text(
                  labels.noResults,
                  style: code.copyWith(color: tertiary),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 14, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: IntrinsicWidth(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final r in head) render(r),
                            if (cap.hidden > 0)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () =>
                                    setState(() => _expanded = !_expanded),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  child: Text(
                                    _expanded
                                        ? labels.collapse
                                        : labels.expand(cap.hidden),
                                    key: const ValueKey('search-fold'),
                                    style: code.copyWith(color: tertiary),
                                  ),
                                ),
                              ),
                            if (tailHeader != null) render(tailHeader),
                            for (final r in tail) render(r),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(Widget child) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 22),
    child: Padding(padding: const EdgeInsets.only(left: 14), child: child),
  );
}
