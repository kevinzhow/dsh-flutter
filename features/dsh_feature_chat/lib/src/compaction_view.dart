import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'chat_nodes.dart' show codeLabels;
import 'command_view.dart';
import 'compaction_sticky.dart';

class ManualCompactionView extends StatelessWidget {
  const ManualCompactionView({
    super.key,
    required this.data,
    required this.i18n,
    this.host,
  });
  final ManualCompactionData data;
  final DshI18n i18n;
  final ToolHostActions? host;
  @override
  Widget build(BuildContext context) => data.compaction == null
      ? CommandView(
          data: data.command,
          i18n: i18n,
          runningSummary: i18n.t('chat', 'message.compaction.running'),
        )
      : CompactionView(
          data: data.compaction!,
          i18n: i18n,
          title: i18n.t('chat', 'message.compaction.commandTitle'),
          fallbackSummary: data.command.outcome?.text,
          host: host,
        );
}

/// Only the cited in-window summary expands, never the checkpoint envelope.
class CompactionView extends StatefulWidget {
  const CompactionView({
    super.key,
    required this.data,
    required this.i18n,
    this.title,
    this.fallbackSummary,
    this.host,
  });
  final CompactionData data;
  final DshI18n i18n;
  final String? title, fallbackSummary;
  final ToolHostActions? host;
  @override
  State<CompactionView> createState() => _CompactionViewState();
}

class _CompactionViewState extends State<CompactionView> {
  bool _expanded = false, _hover = false, _focus = false;
  void _toggle() => setState(() => _expanded = !_expanded);
  @override
  Widget build(BuildContext context) {
    final theme = context.dsh, data = widget.data, i18n = widget.i18n;
    final expandable = data.summary != null,
        open = _expanded && data.summary != null;
    final color = theme.color(
      _hover ? '--dsw-alias-label-secondary' : '--dsw-alias-label-tertiary',
    );
    final style = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(color: color, height: 24 / 13);
    final summary =
        data.shadowedItemCount != null && data.shadowedTokenCount != null
        ? i18n.t(
            'chat',
            'message.compaction.completed',
            params: {
              'items': data.shadowedItemCount,
              'tokens': data.shadowedTokenCount,
            },
          )
        : widget.fallbackSummary ??
              i18n.t(
                'chat',
                expandable
                    ? 'message.compaction.expand'
                    : 'message.compaction.unavailable',
              );
    final header = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        enabled: expandable,
        expanded: expandable ? open : null,
        child: FocusableActionDetector(
          enabled: expandable,
          mouseCursor: expandable
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowFocusHighlight: (value) => setState(() => _focus = value),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _toggle();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: expandable ? _toggle : null,
            child: DshDecoratedBox(
              decoration: theme.cornerDecoration(
                open ? 0 : theme.radiusSm,
                color: open
                    ? theme.color(
                        _hover
                            ? '--dsw-alias-interactive-bg-hover-solid'
                            : '--dsw-alias-bg-base',
                      )
                    : _hover && expandable
                    ? theme.color('--dsw-alias-interactive-bg-hover')
                    : null,
              ),
              child: SizedBox(
                key: const ValueKey('compaction-header'),
                height: 24,
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: Center(
                        child: DshIcon(
                          expandable && (_hover || _focus)
                              ? open
                                    ? DshIcons.chevronDown
                                    : DshIcons.chevronRight
                              : DshIcons.api,
                          size: 14,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    DshChromeText(
                      widget.title ?? i18n.t('chat', 'message.compaction'),
                      style: style,
                      maxLines: 1,
                    ),
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
                    Expanded(
                      child: DshChromeText(
                        summary,
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 0, 4),
      child: DshMarkdown(
        data.summary ?? '',
        selectable: true,
        blockSpacing: 16,
        codeLabels: codeLabels(i18n),
        onOpenUrl: widget.host?.openUrl,
        onOpenFile: widget.host?.openFile,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      // Keep the header at the same element location while toggling, so its
      // keyboard focus survives opening the Markdown body.
      child: CompactionSticky(
        header: header,
        body: open ? body : const SizedBox.shrink(),
      ),
    );
  }
}
