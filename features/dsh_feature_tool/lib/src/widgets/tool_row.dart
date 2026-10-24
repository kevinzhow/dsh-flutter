import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import '../model/details_model.dart' show Tr;
import '../model/row_model.dart';
import 'exit_badge.dart';
import 'io_card.dart';

/// The shared tool row (dsh `ToolRow`): the 24px disclosure row with icon,
/// title, dot separator and summary (a path or URL link, a failure line, the
/// exit capsule, size and diff suffixes), and a lazily built expanded body: a
/// structured card when [card] is given, else the input/output card.
class ToolRow extends StatefulWidget {
  const ToolRow({
    super.key,
    required this.t,
    required this.icon,
    required this.title,
    required this.summary,
    required this.state,
    this.toolName,
    this.summarySuffix,
    this.bodyRaw,
    this.output,
    this.errorSummary,
    this.card,
    this.summaryOverride,
    this.exitLabel,
    this.diffStat,
    this.variant = ToolRowVariant.others,
    this.filePath,
    this.filePathLine,
    this.onOpenFile,
    this.href,
    this.onOpenUrl,
    this.initiallyExpanded = false,
    this.stateId,
    this.panelLabel,
    this.onPanel,
  });

  final Tr t;
  final DshIconData icon;
  final String title;
  final String summary;
  final ToolRowState state;
  final String? toolName;

  /// Trailing fragment outside the ellipsized summary (kept on narrow rows).
  final String? summarySuffix;

  /// Original argument JSON, formatted only while the row is expanded.
  final String? bodyRaw;

  /// Flattened result text for the OUT section.
  final String? output;
  final String? errorSummary;

  /// Builds the structured expanded card; replaces the input/output sections.
  final WidgetBuilder? card;

  /// Replaces the summary (a terminal card shows its command description).
  final String? summaryOverride;

  /// Localized exit capsule of a failed command.
  final String? exitLabel;

  /// `+added -removed` totals of a diff card, coloured on hover or expansion.
  final ({int added, int removed})? diffStat;
  final ToolRowVariant variant;
  final String? filePath;
  final int? filePathLine;
  final void Function(String path, {int? line})? onOpenFile;
  final Uri? href;
  final void Function(Uri url)? onOpenUrl;
  final bool initiallyExpanded;

  /// Identity (the call id) under which the open state survives the row being
  /// scrolled out of the list and back (dsh keeps it in the chat's
  /// `useDisclosure`).
  final String? stateId;

  /// Optional panel action beside the summary (the ask row's reopen button).
  final String? panelLabel;
  final bool Function()? onPanel;

  @override
  State<ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<ToolRow> {
  late bool _expanded = _restore() ?? widget.initiallyExpanded;

  Object? get _identifier =>
      widget.stateId == null ? null : 'tool-open-${widget.stateId}';

  bool? _restore() {
    final id = _identifier;
    if (id == null) return null;
    return PageStorage.maybeOf(context)?.readState(context, identifier: id)
        as bool?;
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    final id = _identifier;
    if (id != null) {
      PageStorage.maybeOf(context)
          ?.writeState(context, _expanded, identifier: id);
    }
  }

  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final w = widget;
    final t = w.t;
    final hasCard = w.card != null;
    final expandable =
        w.state != ToolRowState.preparing &&
        (w.bodyRaw != null || w.output != null || hasCard);
    final open = _expanded && expandable;
    final running =
        w.state == ToolRowState.running || w.state == ToolRowState.preparing;
    final settledWithCue =
        w.state == ToolRowState.error || w.state == ToolRowState.stopped;

    final normalSummary = w.summaryOverride ?? w.summary;
    final failureLine = w.state == ToolRowState.error && w.exitLabel == null
        ? (w.errorSummary ?? normalSummary)
        : null;
    final summaryText = failureLine ?? normalSummary;
    final suffix = settledWithCue ? null : w.summarySuffix;
    final totals = settledWithCue ? null : w.diffStat;

    final base = theme.textStyle('--dsw-font-xs-13');
    final rowStyle = base.copyWith(height: 24 / 13);
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final rowColor = _hover ? theme.labelSecondary : tertiary;

    final linkable =
        w.filePath != null &&
        w.onOpenFile != null &&
        !settledWithCue &&
        w.exitLabel == null;
    final hrefLink =
        w.href != null &&
        w.onOpenUrl != null &&
        !settledWithCue &&
        w.exitLabel == null;

    Widget summaryWidget;
    if (linkable || hrefLink) {
      summaryWidget = Flexible(
        child: GestureDetector(
          key: const ValueKey('tool-link'),
          behavior: HitTestBehavior.opaque,
          onTap: () => linkable
              ? w.onOpenFile!(w.filePath!, line: w.filePathLine)
              : w.onOpenUrl!(w.href!),
          child: DshChromeText(
            summaryText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: rowStyle.copyWith(
              color: rowColor,
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: rowColor,
              decorationThickness: 1,
            ),
          ),
        ),
      );
    } else {
      summaryWidget = Flexible(
        child: DshChromeText(
          summaryText,
          key: const ValueKey('tool-summary'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: rowStyle.copyWith(
            color: w.exitLabel == null && w.state == ToolRowState.error
                ? theme.color('--dsw-alias-state-error-primary')
                : w.exitLabel == null && w.state == ToolRowState.stopped
                ? theme.color('--dsw-alias-state-warn-label')
                : rowColor,
          ),
        ),
      );
    }

    final collapsed = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (summaryText.isNotEmpty) ...[
          DshContainer(
            width: 2,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.color('--dsw-alias-label-caption'),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          summaryWidget,
          if (w.exitLabel != null) ExitBadge(label: w.exitLabel!),
          if (suffix != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: DshChromeText(
                suffix,
                maxLines: 1,
                softWrap: false,
                style: rowStyle.copyWith(color: rowColor),
              ),
            ),
          if (totals != null)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Transform.translate(
                offset: const Offset(0, 0.5),
                child: Text.rich(
                  TextSpan(
                    style: theme
                        .textStyle('--dsw-font-markdown-code')
                        .sized(11, line: 24)
                        .copyWith(color: rowColor),
                    children: [
                      TextSpan(
                        text: '+${totals.added}',
                        style: TextStyle(
                          color: _hover || open
                              ? theme.color('--dsw-alias-state-success-primary')
                              : null,
                        ),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: '-${totals.removed}',
                        style: TextStyle(
                          color: _hover || open
                              ? theme.color('--dsw-alias-state-error-primary')
                              : null,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
        ],
        if (w.panelLabel != null && w.onPanel != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!w.onPanel!()) _toggle();
              },
              child: DshChromeText(
                w.panelLabel!,
                style: rowStyle.copyWith(color: theme.labelSecondary),
              ),
            ),
          ),
      ],
    );

    Widget? body;
    if (open) {
      final Widget content;
      if (hasCard) {
        content = w.card!(context);
      } else {
        final input = w.bodyRaw == null
            ? null
            : formatToolBody(w.variant, w.bodyRaw!);
        content = IoCard(
          inputLabel: t('row.input'),
          outputLabel: t('row.output'),
          input: input,
          output: w.output,
          error: w.state == ToolRowState.error,
        );
      }
      body = Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
        child: content,
      );
    }

    final status = switch (w.state) {
      ToolRowState.preparing => t('row.preparing'),
      ToolRowState.running => t('row.running'),
      ToolRowState.error => t('row.failed'),
      ToolRowState.stopped => t('row.stopped'),
      _ => null,
    };

    return Semantics(
      label: status == null ? null : '$status ${w.title}',
      container: false,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: DshDisclosureRow(
          key: ValueKey('tool-row-${w.toolName ?? w.title}'),
          icon: w.icon,
          title: w.title,
          open: open,
          expandable: expandable,
          running: running,
          onToggle: _toggle,
          collapsedContent: collapsed,
          children: body,
        ),
      ),
    );
  }
}
