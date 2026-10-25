import 'dart:math' as math;

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show SelectionArea;

class DeliveryDiffRow {
  const DeliveryDiffRow(this.kind, this.old, this.fresh, this.text);
  final String kind, text;
  final int? old, fresh;
}

List<DeliveryDiffRow> deliveryHunkRows(ChangesHunk hunk) {
  var old = hunk.oldStart, fresh = hunk.newStart;
  return [
    for (final line in hunk.lines)
      switch (line[0]) {
        '+' => DeliveryDiffRow('add', null, fresh++, line.substring(1)),
        '-' => DeliveryDiffRow('del', old++, null, line.substring(1)),
        _ => DeliveryDiffRow('context', old++, fresh++, line.substring(1)),
      },
  ];
}

List<(DeliveryDiffRow?, DeliveryDiffRow?)> deliverySplitRows(ChangesHunk hunk) {
  final result = <(DeliveryDiffRow?, DeliveryDiffRow?)>[],
      dels = <DeliveryDiffRow>[],
      adds = <DeliveryDiffRow>[];
  void flush() {
    for (var i = 0; i < math.max(dels.length, adds.length); i++) {
      result.add((
        i < dels.length ? dels[i] : null,
        i < adds.length ? adds[i] : null,
      ));
    }
    dels.clear();
    adds.clear();
  }

  for (final row in deliveryHunkRows(hunk)) {
    if (row.kind == 'del') {
      dels.add(row);
    } else if (row.kind == 'add') {
      adds.add(row);
    } else {
      flush();
      result.add((row, row));
    }
  }
  flush();
  return result;
}

class DeliverablesFileDiff extends StatefulWidget {
  const DeliverablesFileDiff({
    super.key,
    required this.state,
    required this.i18n,
    required this.retry,
    this.split = false,
    this.wrap = false,
  });
  final HostRead<ChangesDiff>? state;
  final DshI18n i18n;
  final VoidCallback retry;
  final bool split, wrap;
  @override
  State<DeliverablesFileDiff> createState() => _DiffState();
}

class _DiffState extends State<DeliverablesFileDiff> with DshHighlightListener {
  @override
  String? get highlightLang =>
      dshLanguageForPath(widget.state?.value?.path ?? '');
  String t(String key, [Map<String, Object?> params = const {}]) =>
      widget.i18n.t('deliverables', key, params: params);
  @override
  Widget build(BuildContext context) {
    final state = widget.state, diff = state?.value;
    Widget status(String key) =>
        Padding(padding: const EdgeInsets.all(12), child: Text(t(key)));
    if (state == null || state.phase == HostReadPhase.loading) {
      return Semantics(liveRegion: true, child: status('diff.loading'));
    }
    if (state.phase == HostReadPhase.missing) return status('diff.missing');
    if (state.phase == HostReadPhase.error) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          status('diff.error'),
          DshButton(
            size: DshButtonSize.sm,
            onPressed: widget.retry,
            child: Text(t('presented.retry')),
          ),
        ],
      );
    }
    if (diff == null) return status('diff.missing');
    if (diff.kind != 'text') return status('diff.${diff.kind}');
    var budget = 5000, truncated = false;
    final hunks = <ChangesHunk>[];
    for (final h in diff.hunks) {
      if (budget == 0) {
        truncated = true;
        break;
      }
      final lines = h.lines.take(budget).toList();
      if (lines.length < h.lines.length) truncated = true;
      hunks.add(
        ChangesHunk(
          oldStart: h.oldStart,
          oldLines: h.oldLines,
          newStart: h.newStart,
          newLines: h.newLines,
          lines: lines,
        ),
      );
      budget -= lines.length;
    }
    final hasAdd = hunks.any((h) => h.lines.any((l) => l.startsWith('+'))),
        hasDel = hunks.any((h) => h.lines.any((l) => l.startsWith('-')));
    final split = widget.split && hasAdd && hasDel;
    final theme = context.dsh,
        base = theme.textStyle('--dsw-font-markdown-code-block');
    Widget line(DeliveryDiffRow? row, {bool? side, List<DshCodeSpan>? spans}) {
      final modified = row?.kind == 'add' || row?.kind == 'del';
      final added = row?.kind == 'add';
      final fill = modified
          ? theme.color(
              added
                  ? '--dsw-alias-file-diff-added-bg'
                  : '--dsw-alias-file-diff-deleted-bg',
            )
          : row == null
          ? theme
                .color('--dsw-alias-interactive-bg-hover')
                .withValues(alpha: .5)
          : theme.labelPrimary.withValues(alpha: 0);
      final marker = modified
          ? theme.color(
              added
                  ? '--dsw-alias-file-diff-added-marker'
                  : '--dsw-alias-file-diff-deleted-marker',
            )
          : theme.color('--dsw-alias-label-tertiary');
      final gutter = modified
          ? theme.color(
              added
                  ? '--dsw-alias-file-diff-added-gutter'
                  : '--dsw-alias-file-diff-deleted-gutter',
            )
          : theme.labelPrimary.withValues(alpha: 0);
      Widget number(int? value, {bool first = false}) => DshContainer(
        width: base.fontSize! * 3.5,
        padding: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: gutter,
          border: first && modified
              ? Border(left: BorderSide(color: marker, width: 3))
              : null,
        ),
        child: Text(
          value == null ? '' : '$value',
          textAlign: TextAlign.right,
          style: base.copyWith(color: marker, height: 22 / base.fontSize!),
        ),
      );
      final text = Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Text.rich(
          TextSpan(
            style: base.copyWith(
              height: 22 / base.fontSize!,
              color: row?.kind == 'context'
                  ? theme.labelSecondary
                  : theme.labelPrimary,
            ),
            children: spans == null
                ? [TextSpan(text: row?.text ?? '')]
                : dshStyledSpans(context, spans, base, wrap: widget.wrap),
          ),
        ),
      );
      return DshContainer(
        decoration: BoxDecoration(color: fill),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (side == null) ...[
                number(row?.old, first: true),
                number(row?.fresh),
                SizedBox(
                  width: base.fontSize! * 1.2,
                  child: Text(
                    row?.kind == 'add'
                        ? '+'
                        : row?.kind == 'del'
                        ? '-'
                        : ' ',
                    textAlign: TextAlign.center,
                    style: base.copyWith(
                      color: marker,
                      height: 22 / base.fontSize!,
                    ),
                  ),
                ),
              ] else
                number(side ? row?.fresh : row?.old, first: true),
              if (widget.wrap) Expanded(child: text) else text,
            ],
          ),
        ),
      );
    }

    final blocks = <Widget>[];
    if (!diff.before) {
      blocks.add(status('diff.created'));
    } else if (!diff.after) {
      blocks.add(status('diff.deleted'));
    } else if (diff.hunks.isEmpty) {
      blocks.add(status('diff.unchanged'));
    }
    if (diff.coarse) blocks.add(status('diff.coarse'));
    if (truncated) {
      blocks.add(
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(t('diff.truncated', {'count': '5000'})),
        ),
      );
    }
    final highlighter = DshCodeHighlighting.of(context);
    for (final h in hunks) {
      final rows = deliveryHunkRows(h);
      Map<int, List<DshCodeSpan>> highlight(bool old) {
        final source = rows
            .where((r) => old ? r.old != null : r.fresh != null)
            .toList();
        final colored = highlighter?.highlight(
          source.map((r) => r.text).join('\n'),
          highlightLang,
        );
        return {
          for (var i = 0; i < source.length; i++)
            (old
                ? source[i].old!
                : source[i].fresh!): colored != null && i < colored.length
                ? colored[i]
                : [DshCodeSpan(source[i].text)],
        };
      }

      final oldColors = highlight(true), newColors = highlight(false);
      final header = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          '@@ -${h.oldStart},${h.oldLines} +${h.newStart},${h.newLines} @@',
          style: base.copyWith(
            color: theme.color('--dsw-alias-label-tertiary'),
          ),
        ),
      );
      if (!split || widget.wrap) blocks.add(header);
      if (split) {
        final pairs = deliverySplitRows(h);
        Widget column(bool right) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            for (final pair in pairs)
              line(
                right ? pair.$2 : pair.$1,
                side: right,
                spans: right
                    ? newColors[pair.$2?.fresh]
                    : oldColors[pair.$1?.old],
              ),
          ],
        );
        if (widget.wrap) {
          blocks.add(
            Column(
              children: [
                for (final p in pairs)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: line(
                            p.$1,
                            side: false,
                            spans: oldColors[p.$1?.old],
                          ),
                        ),
                        Expanded(
                          child: line(
                            p.$2,
                            side: true,
                            spans: newColors[p.$2?.fresh],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        } else {
          blocks.add(_LinkedColumns(left: column(false), right: column(true)));
        }
      } else {
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows)
              line(
                row,
                spans: row.kind == 'add'
                    ? newColors[row.fresh]
                    : oldColors[row.old],
              ),
          ],
        );
        blocks.add(widget.wrap ? body : _HorizontalTrack(child: body));
      }
      blocks.add(const SizedBox(height: 8));
    }
    return SelectionArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: Column(
          key: ValueKey(
            'delivery-diff-${split ? 'split' : 'unified'}-${widget.wrap}',
          ),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: blocks,
        ),
      ),
    );
  }
}

class _LinkedColumns extends StatefulWidget {
  const _LinkedColumns({required this.left, required this.right});
  final Widget left, right;
  @override
  State<_LinkedColumns> createState() => _LinkedColumnsState();
}

class _LinkedColumnsState extends State<_LinkedColumns> {
  final left = ScrollController(), right = ScrollController();
  bool linking = false;
  void follow(ScrollController from, ScrollController to) {
    if (linking || !to.hasClients || !from.hasClients) return;
    linking = true;
    to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
    linking = false;
  }

  @override
  void initState() {
    super.initState();
    left.addListener(() => follow(left, right));
    right.addListener(() => follow(right, left));
  }

  @override
  void dispose() {
    left.dispose();
    right.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (child, controller) in [
        (widget.left, left),
        (widget.right, right),
      ])
        Expanded(
          child: _HorizontalTrack(controller: controller, child: child),
        ),
    ],
  );
}

class _HorizontalTrack extends StatelessWidget {
  const _HorizontalTrack({required this.child, this.controller});
  final Widget child;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: constraints.maxWidth),
        child: IntrinsicWidth(child: child),
      ),
    ),
  );
}
