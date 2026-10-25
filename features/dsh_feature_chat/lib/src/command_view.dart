import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// Generic command output stays plain text; only multiline settlement expands.
class CommandView extends StatefulWidget {
  const CommandView({
    super.key,
    required this.data,
    required this.i18n,
    this.runningSummary,
  });
  final CommandData data;
  final DshI18n i18n;
  final String? runningSummary;
  @override
  State<CommandView> createState() => _CommandViewState();
}

class _CommandViewState extends State<CommandView> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final data = widget.data, i18n = widget.i18n;
    final theme = context.dsh;
    final border = dshBorderWidthOf(context, .5);
    final running = data.outcome == null;
    final error = data.outcome?.kind == 'error';
    final summary = running
        ? widget.runningSummary ?? i18n.t('chat', 'command.running')
        : data.outcome!.text ??
              i18n.t('chat', error ? 'command.failed' : 'command.done');
    final text = data.outcome?.text;
    final expandable = text != null && text.contains('\n');
    final style = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(
          height: 24 / 13,
          color: error ? theme.color('--dsw-alias-state-error-primary') : null,
        );
    return Semantics(
      liveRegion: true,
      label: running
          ? i18n.t('chat', 'row.running')
          : error
          ? i18n.t('chat', 'row.failed')
          : null,
      child: DshDisclosureRow(
        icon: DshIcons.api,
        title: data.name ?? i18n.t('chat', 'command.title'),
        running: running,
        open: _expanded && expandable,
        expandable: expandable,
        onToggle: () => setState(() => _expanded = !_expanded),
        collapsedContent: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                width: 2,
                height: 2,
                decoration: BoxDecoration(
                  color: theme.color('--dsw-alias-label-caption'),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Flexible(
              child: DshChromeText(
                summary,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        children: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: DshDecoratedBox(
              decoration: theme.cornerDecoration(
                theme.radiusLg,
                color: theme.color('--dsw-alias-markdown-code-block'),
                borderColor: theme.color('--dsw-alias-border-l1'),
                borderWidth: border,
              ),
              child: theme.clipCorners(
                theme.radiusLg,
                Padding(
                  // CSS borders contribute to the pre's box dimensions;
                  // a painted Flutter decoration alone does not.
                  padding: EdgeInsets.all(border),
                  child: SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: DshChromeText(
                      text ?? '',
                      style: theme
                          .fixedCodeStyle(size: 11, line: 16)
                          .copyWith(
                            color: error
                                ? theme.color('--dsw-alias-state-error-primary')
                                : theme.labelPrimary,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
