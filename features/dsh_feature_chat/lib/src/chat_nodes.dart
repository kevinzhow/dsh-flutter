import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Icons, SelectableText;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';

String _chat(
  DshI18n i18n,
  String key, {
  Map<String, Object?> params = const {},
}) => i18n.t('chat', key, params: params);

TextStyle _caption(BuildContext context) {
  final theme = context.dsh;
  return theme
      .textStyle('--dsw-font-xxs-12')
      .copyWith(color: theme.color('--dsw-alias-label-tertiary'));
}

/// A person's message: a right-aligned bubble on `--dsw-specific-bubble`.
/// [pending] dims a local echo that the host has not yet admitted.
class UserBubble extends StatelessWidget {
  const UserBubble({
    super.key,
    required this.text,
    required this.i18n,
    this.steering = false,
    this.pending = false,
  });

  final String text;
  final DshI18n i18n;
  final bool steering;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.86),
          child: Opacity(
            opacity: pending ? 0.6 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (steering)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DshSpace.xs),
                    child: Text(
                      i18n.t('conversation', 'settings.enter.steer'),
                      style: _caption(context),
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.color('--dsw-specific-bubble'),
                    borderRadius: BorderRadius.circular(theme.radiusXl),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DshSpace.lg,
                      vertical: DshSpace.md,
                    ),
                    child: SelectableText(
                      text,
                      style: theme
                          .textStyle('--dsw-font-base-16')
                          .copyWith(color: theme.labelPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One streamed or settled assistant step: collapsible reasoning rows and the
/// markdown answer text; a stopped marker when the step was interrupted.
class AssistantStepView extends StatelessWidget {
  const AssistantStepView({
    super.key,
    required this.data,
    required this.nodeKey,
    required this.i18n,
  });

  final AssistantData data;
  final String nodeKey;
  final DshI18n i18n;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final children = <Widget>[];
    for (var i = 0; i < data.blocks.length; i++) {
      final block = data.blocks[i];
      switch (block) {
        case ReasoningBlock(:final text) when text.trim().isNotEmpty:
          final last = i == data.blocks.length - 1;
          children.add(
            _ReasoningRow(
              key: ValueKey('reasoning-$nodeKey-$i'),
              text: text,
              streaming: data.status == 'running' && last,
              i18n: i18n,
            ),
          );
        case TextBlock(:final text) when text.trim().isNotEmpty:
          children.add(DshMarkdown(text, key: ValueKey('text-$nodeKey-$i')));
        case ImageBlock():
          children.add(
            Text(
              i18n.t('conversation', 'image.label'),
              style: _caption(context),
            ),
          );
        case _:
          break;
      }
    }
    if (data.status == 'interrupted') {
      children.add(
        Text(
          _chat(i18n, 'message.stopped'),
          key: const ValueKey('assistant-stopped'),
          style: _caption(context)
              .copyWith(color: theme.color('--dsw-alias-label-secondary')),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: DshSpace.sm),
          children[i],
        ],
      ],
    );
  }
}

/// Reasoning is open while it streams and folds away once it is done, unless
/// the reader opened or closed it by hand (dsh's "collapse on completion").
class _ReasoningRow extends StatefulWidget {
  const _ReasoningRow({
    super.key,
    required this.text,
    required this.streaming,
    required this.i18n,
  });

  final String text;
  final bool streaming;
  final DshI18n i18n;

  @override
  State<_ReasoningRow> createState() => _ReasoningRowState();
}

class _ReasoningRowState extends State<_ReasoningRow> {
  bool? _byHand;

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final streaming = widget.streaming;
    final i18n = widget.i18n;
    final theme = context.dsh;
    final style = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(color: theme.labelSecondary);
    return DshDisclosure(
      open: _byHand ?? streaming,
      onToggle: (open) => setState(() => _byHand = open),
      header: Row(
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 16,
            color: theme.color('--dsw-alias-label-tertiary'),
          ),
          const SizedBox(width: DshSpace.xs),
          Text(
            streaming
                ? i18n.t(appNamespace, 'session.reasoning.running')
                : _chat(i18n, 'message.think'),
            style: _caption(context)
                .copyWith(color: theme.color('--dsw-alias-label-secondary')),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: DshSpace.sm, bottom: DshSpace.xs),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.color('--dsw-alias-border-l2'),
                width: 2,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: DshSpace.md),
            child: SelectableText(text, style: style),
          ),
        ),
      ),
    );
  }
}

/// The closing row of a finished turn: copy of the closing answer.
class TurnTailView extends StatefulWidget {
  const TurnTailView({super.key, required this.data, required this.i18n});

  final TurnTailData data;
  final DshI18n i18n;

  @override
  State<TurnTailView> createState() => _TurnTailViewState();
}

class _TurnTailViewState extends State<TurnTailView> {
  bool _copied = false;

  String? get _text {
    final closing = widget.data.closing;
    if (closing == null) return null;
    return [
      for (final b in closing.blocks)
        if (b is TextBlock) b.text,
    ].join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    if (text == null || text.trim().isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: DshButton(
        key: const ValueKey('turn-copy'),
        size: DshButtonSize.sm,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (!mounted) return;
          setState(() => _copied = true);
        },
        child: Text(widget.i18n.t('common', _copied ? 'copied' : 'copy')),
      ),
    );
  }
}

/// A terminal turn failure.
class TurnErrorView extends StatelessWidget {
  const TurnErrorView({super.key, required this.data, required this.i18n});

  final TurnErrorData data;
  final DshI18n i18n;

  String get _text => switch (data.code) {
    'AUTH' => _chat(i18n, 'message.failure.auth'),
    'ACCOUNT_SIGNED_OUT' => i18n.t(appNamespace, 'session.turn.signedOut'),
    'INTERRUPTED' => i18n.t(appNamespace, 'session.turn.interrupted'),
    _ => data.message,
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final detail = _text;
    return DshCard(
      key: const ValueKey('turn-error'),
      tint: theme
          .color('--dsw-alias-state-error-secondary')
          .withValues(alpha: 0.12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: DshSpace.xs),
            child: DshStatusDot(DshStatus.error),
          ),
          const SizedBox(width: DshSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.t(appNamespace, 'session.turn.failed'),
                  style: theme
                      .textStyle('--dsw-font-s-strong-14')
                      .copyWith(color: theme.labelPrimary),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .copyWith(color: theme.labelSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A caption row used for small turn notices (max tokens, triggers, unknown
/// events).
class NoticeRow extends StatelessWidget {
  const NoticeRow({super.key, required this.text, this.status});

  final String text;
  final DshStatus? status;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (status != null) ...[
        DshStatusDot(status!),
        const SizedBox(width: DshSpace.sm),
      ],
      Flexible(child: Text(text, style: _caption(context))),
    ],
  );
}
