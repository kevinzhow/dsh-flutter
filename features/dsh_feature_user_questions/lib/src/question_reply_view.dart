import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

String replyClipboardText(QuestionReplyData data, DshI18n i18n) {
  if (data.questions.isEmpty) return data.text;
  return data.questions
      .map((q) {
        final header = q['header'] as String?;
        final heading =
            header != null && header.isNotEmpty && header != q['question']
            ? '$header — ${q['question']}'
            : q['question'];
        final values = data.answerValues(q['id'] as String);
        final answer = values.isEmpty
            ? i18n.t('question', 'reply.skipped')
            : '${i18n.t('question', 'reply.answerLabel')}${values.join(', ')}';
        return '$heading\n$answer';
      })
      .join('\n\n');
}

class QuestionReplyView extends StatefulWidget {
  const QuestionReplyView({
    super.key,
    required this.data,
    required this.i18n,
    this.initiallyOpen = false,
  });
  final QuestionReplyData data;
  final DshI18n i18n;
  final bool initiallyOpen;
  @override
  State<QuestionReplyView> createState() => _QuestionReplyViewState();
}

class _QuestionReplyViewState extends State<QuestionReplyView>
    with DshCopyFeedback {
  late bool _open = widget.initiallyOpen;
  String t(String key) => widget.i18n.t('question', key);
  Widget text(
    BuildContext c,
    String value, {
    int size = 14,
    bool secondary = false,
  }) => DshChromeText(
    value,
    style: c.dsh
        .textStyle(switch (size) {
          11 => '--dsw-font-xxxs-11',
          12 => '--dsw-font-xxs-12',
          13 => '--dsw-font-xs-13',
          _ => '--dsw-font-s-14',
        })
        .copyWith(
          color: secondary ? c.dsh.labelSecondary : c.dsh.labelPrimary,
          height: (size == 13 ? 18 : 22) / size,
        ),
  );
  Widget action({
    required Widget child,
    required VoidCallback onTap,
    String? label,
    bool? expanded,
  }) => Semantics(
    button: true,
    label: label,
    expanded: expanded,
    child: FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final data = widget.data, theme = context.dsh;
    final summary = data.questions
        .expand((q) => data.answerValues(q['id'] as String))
        .join(', ');
    final date = DateTime.fromMillisecondsSinceEpoch(data.time.toInt());
    final clock =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Semantics(
      label: t('reply.label'),
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _ReplyWidth(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: DshDecoratedBox(
                    decoration: theme.cornerDecoration(
                      theme.radiusXl,
                      color: theme.color('--dsw-specific-bubble'),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              top: _open ? 1 : 0,
                              bottom: _open ? 3 : 0,
                            ),
                            child: action(
                              label:
                                  '${t('reply.label')} · ${t(_open ? 'reply.close' : 'reply.open')}',
                              expanded: _open,
                              onTap: () {
                                DshDisclosureChange(
                                  !_open,
                                  context,
                                ).dispatch(context);
                                setState(() => _open = !_open);
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      DshIcon(
                                        _open
                                            ? DshIcons.chevronDown
                                            : DshIcons.chevronRight,
                                        size: 12,
                                        color: theme.labelSecondary,
                                      ),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: text(
                                          context,
                                          t('reply.label'),
                                          size: 13,
                                          secondary: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!_open)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: text(
                                        context,
                                        summary.isEmpty
                                            ? t('reply.skipped')
                                            : summary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_open)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: data.questions.isEmpty
                                  ? text(context, data.text)
                                  : DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(
                                            color: theme.labelSecondary
                                                .withValues(alpha: .24),
                                            width: dshBorderWidthOf(context, 1),
                                          ),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          top: 8 + dshBorderWidthOf(context, 1),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            for (
                                              var i = 0;
                                              i < data.questions.length;
                                              i++
                                            )
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  top: i == 0 ? 0 : 12,
                                                ),
                                                child: Builder(
                                                  builder: (context) {
                                                    final q = data.questions[i],
                                                        values = data.answerValues(
                                                          data.questions[i]['id']
                                                              as String,
                                                        );
                                                    return Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        if (q['header']
                                                                is String &&
                                                            (q['header']
                                                                    as String)
                                                                .isNotEmpty &&
                                                            q['header'] !=
                                                                q['question']) ...[
                                                          text(
                                                            context,
                                                            q['header']
                                                                as String,
                                                            size: 11,
                                                            secondary: true,
                                                          ),
                                                          const SizedBox(
                                                            height: 3,
                                                          ),
                                                        ],
                                                        text(
                                                          context,
                                                          q['question']
                                                              as String,
                                                          size: 12,
                                                        ),
                                                        if (q['detail']
                                                                is String &&
                                                            (q['detail']
                                                                    as String)
                                                                .isNotEmpty) ...[
                                                          const SizedBox(
                                                            height: 3,
                                                          ),
                                                          text(
                                                            context,
                                                            q['detail']
                                                                as String,
                                                            size: 11,
                                                            secondary: true,
                                                          ),
                                                        ],
                                                        if (q['options']
                                                            is List)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  left: 16,
                                                                  top: 3,
                                                                ),
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .stretch,
                                                              children: [
                                                                for (final o
                                                                    in q['options']
                                                                        as List)
                                                                  text(
                                                                    context,
                                                                    '• ${(o as Map)['label']}${o['description'] is String && (o['description'] as String).isNotEmpty ? ' — ${o['description']}' : ''}',
                                                                    size: 11,
                                                                    secondary:
                                                                        true,
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 4,
                                                              ),
                                                          child: Text.rich(
                                                            TextSpan(
                                                              style: theme
                                                                  .textStyle(
                                                                    '--dsw-font-s-14',
                                                                  )
                                                                  .copyWith(
                                                                    color: theme
                                                                        .labelPrimary,
                                                                    height:
                                                                        22 / 14,
                                                                  ),
                                                              children: [
                                                                TextSpan(
                                                                  text: t(
                                                                    'reply.answerLabel',
                                                                  ),
                                                                  style: theme
                                                                      .textStyle(
                                                                        '--dsw-font-xxs-12',
                                                                      )
                                                                      .copyWith(
                                                                        height:
                                                                            22 /
                                                                            12,
                                                                        color: theme
                                                                            .labelSecondary,
                                                                      ),
                                                                ),
                                                                const WidgetSpan(
                                                                  child:
                                                                      SizedBox(
                                                                        width:
                                                                            4,
                                                                      ),
                                                                ),
                                                                TextSpan(
                                                                  text:
                                                                      values
                                                                          .isEmpty
                                                                      ? t(
                                                                          'reply.skipped',
                                                                        )
                                                                      : values
                                                                            .join(
                                                                              ', ',
                                                                            ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(
                height: 28,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: DshChromeText(
                        clock,
                        style: theme
                            .textStyle('--dsw-font-xs-13')
                            .copyWith(
                              height: 24 / 13,
                              color: theme.color('--dsw-alias-label-tertiary'),
                            ),
                      ),
                    ),
                    action(
                      label: t(copied ? 'copied' : 'copy'),
                      onTap: () =>
                          copyText(replyClipboardText(data, widget.i18n)),
                      child: SizedBox.square(
                        dimension: 28,
                        child: Center(
                          child: DshIcon(
                            copied ? DshIcons.check : DshIcons.copy,
                            size: 15,
                            color: theme.color('--dsw-alias-label-tertiary'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The upstream bubble's 72% limit applies to its content box; horizontal
// padding adds 32px. It still shrinks to the intrinsic content width.
class _ReplyWidth extends StatelessWidget {
  const _ReplyWidth({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: constraints.maxWidth * .72 + 32),
      child: IntrinsicWidth(child: child),
    ),
  );
}
