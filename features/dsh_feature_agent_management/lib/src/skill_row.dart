import 'dart:convert';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/widgets.dart';

class SkillRowData {
  const SkillRowData(this.name, this.output, this.errorSummary, this.state);
  final String name, state;
  final String? output, errorSummary;
}

String _firstLine(String text) => text.split('\n').first;
SkillRowData skillRowData(ToolCall call) {
  final raw = switch (call) {
    StartedToolCall(:final argsRaw) => argsRaw,
    ToolResult(:final callArgsRaw) => callArgsRaw ?? '',
    _ => '',
  };
  String? name;
  try {
    final args = jsonDecode(raw);
    if (args is Map &&
        args['name'] is String &&
        (args['name'] as String).isNotEmpty) {
      name = _firstLine(args['name'] as String);
    }
  } on FormatException {
    /* Streaming arguments can be incomplete. */
  }
  name ??= raw.isEmpty ? call.callId : _firstLine(raw);
  if (call is! ToolResult) return SkillRowData(name, null, null, 'running');
  final parts = [
    for (final item in call.content)
      if (item is Map && item['type'] == 'text' && item['text'] is String)
        item['text'] as String
      else
        const JsonEncoder.withIndent('  ').convert(item),
  ];
  if (parts.isEmpty && call.error != null) {
    parts.add('${call.error!['name']}: ${call.error!['code']}');
  }
  final text = parts.join('\n');
  final output = text.isEmpty ? null : text;
  final state = call.error?['code'] == 'interrupted'
      ? 'stopped'
      : call.isError
      ? 'error'
      : 'ok';
  return SkillRowData(
    name,
    output,
    state == 'error' && output != null ? _firstLine(output) : null,
    state,
  );
}

class SkillRow extends StatefulWidget {
  const SkillRow({super.key, required this.call, required this.i18n});
  final ToolCall call;
  final DshI18n i18n;
  @override
  State<SkillRow> createState() => _SkillRowState();
}

class _SkillRowState extends State<SkillRow> {
  bool expanded = false;
  String t(String key) => widget.i18n.t('skill', key);
  @override
  Widget build(BuildContext context) {
    final data = skillRowData(widget.call), theme = context.dsh;
    final preparing = widget.call is PreparingToolCall;
    final open = expanded && data.output != null;
    final summary = data.state == 'stopped'
        ? t('row.stopped')
        : data.errorSummary ?? data.name;
    final color = theme.color(
      data.state == 'error'
          ? '--dsw-alias-state-error-primary'
          : data.state == 'stopped'
          ? '--dsw-alias-state-warn-label'
          : '--dsw-alias-label-tertiary',
    );
    return Semantics(
      label: preparing
          ? t('row.preparing')
          : data.state == 'running'
          ? t('row.running')
          : data.state == 'error'
          ? t('row.failed')
          : null,
      child: DshDisclosureRow(
        icon: DshIcons.skill,
        title: t('row.title'),
        open: open,
        expandable: data.output != null,
        onToggle: () => setState(() => expanded = !expanded),
        running: preparing || data.state == 'running',
        expandedIcon: DshIcons.chevronDown,
        collapsedContent: preparing
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.color('--dsw-alias-label-caption'),
                        borderRadius: BorderRadius.circular(1),
                      ),
                      child: const SizedBox(width: 2, height: 2),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .textStyle('--dsw-font-xs-13')
                          .copyWith(color: color, height: 24 / 13),
                    ),
                  ),
                ],
              ),
        children: !open
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: DshDecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        width: .5,
                        color: theme.color('--dsw-alias-border-l1'),
                      ),
                      borderRadius: BorderRadius.circular(theme.radiusLg),
                      color: theme.color('--dsw-alias-markdown-code-block'),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.color(
                              '--dsw-alias-markdown-code-block-banner',
                            ),
                            border: Border(
                              bottom: BorderSide(
                                width: .5,
                                color: theme.color('--dsw-alias-border-l2'),
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              t('row.instructions').toUpperCase(),
                              style: theme
                                  .fixedTextStyle(
                                    size: 11,
                                    line: 16,
                                    weight: 500,
                                  )
                                  .copyWith(
                                    color: theme.color(
                                      '--dsw-alias-label-caption',
                                    ),
                                    letterSpacing: .44,
                                  ),
                            ),
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                12,
                              ),
                              child: SelectionArea(
                                child: Text(
                                  data.output!,
                                  style: theme
                                      .textStyle(
                                        '--dsw-font-markdown-code-block-small',
                                      )
                                      .copyWith(
                                        color: data.state == 'error'
                                            ? color
                                            : theme.labelSecondary,
                                      ),
                                ),
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
    );
  }
}
