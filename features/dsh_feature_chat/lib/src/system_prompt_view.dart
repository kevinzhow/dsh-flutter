import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// The pinned SystemPromptRow: a disclosure above a bounded plain-text
/// scrollport. Prompt text is never interpreted as Markdown or HTML.
class SystemPromptView extends StatefulWidget {
  const SystemPromptView({
    super.key,
    required this.text,
    required this.i18n,
    this.update = false,
    this.initiallyOpen = false,
  });
  final String text;
  final DshI18n i18n;
  final bool update, initiallyOpen;
  @override
  State<SystemPromptView> createState() => _SystemPromptViewState();
}

class _SystemPromptViewState extends State<SystemPromptView> {
  late bool _open = widget.initiallyOpen;
  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final text = widget.text.length > 20000
        ? '${widget.text.substring(0, 20000)}\n${widget.i18n.t('chat', 'json.truncated', params: {'total': widget.text.length})}'
        : widget.text;
    final style = theme
        .fixedCodeStyle(size: 11, line: 16)
        .copyWith(color: theme.labelSecondary);
    return DshDisclosureRow(
      key: const ValueKey('system-prompt-row'),
      icon: DshIcons.browse,
      title: widget.i18n.t(
        'chat',
        widget.update ? 'message.systemPromptUpdate' : 'message.systemPrompt',
      ),
      open: _open,
      expandable: true,
      chevronColor: theme.labelSecondary,
      onToggle: () => setState(() => _open = !_open),
      children: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 0, 4),
        child: ConstrainedBox(
          key: const ValueKey('system-prompt-body'),
          constraints: const BoxConstraints(maxHeight: 141),
          child: DshDecoratedBox(
            decoration: theme.cornerDecoration(
              theme.radiusMd,
              color: theme.color('--dsw-alias-markdown-code-block'),
            ),
            child: theme.clipCorners(
              theme.radiusMd,
              SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
                child: text.isEmpty
                    ? const SizedBox.shrink()
                    : DshChromeText(text, style: style),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
