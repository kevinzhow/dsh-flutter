import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/widgets.dart';

import 'tool_format.dart';

/// Longest result shown in an expanded card; the rest is cut with a notice.
const maxResultChars = 6000;

/// Generic tool call card (the fallback of dsh's `tool.call.toolview` slot): a
/// status dot, the tool title, a one-line arguments summary and the result
/// preview; expands to the full arguments and result. Tool-specific views occupy
/// the slot in later phases.
class ToolCard extends StatelessWidget {
  const ToolCard({super.key, required this.call, required this.i18n});

  final ToolCall call;
  final DshI18n i18n;

  String _c(String key, {Map<String, Object?> params = const {}}) =>
      i18n.t('conversation', key, params: params);
  String _a(String key) => i18n.t(appNamespace, key);

  DshStatus get _status => switch (call) {
    PreparingToolCall() || StartedToolCall() => DshStatus.running,
    ToolResult(:final isError, :final error) =>
      isError
          ? (error?['code'] == 'interrupted' ? DshStatus.idle : DshStatus.error)
          : DshStatus.success,
  };

  String get _statusLabel => switch (call) {
    PreparingToolCall() => _a('session.tool.preparing'),
    StartedToolCall() => _c('row.running'),
    ToolResult(:final isError, :final error) =>
      isError
          ? (error?['code'] == 'interrupted'
                ? _a('session.tool.interrupted')
                : _c('row.failed'))
          : '',
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final call = this.call;
    final title = toolTitle(i18n, call.name);
    final summary = argsSummary(call.args);
    final result = call is ToolResult ? resultText(call.content) : null;
    final preview = result == null ? null : previewLines(result);
    final meta = theme
        .textStyle('--dsw-font-xxs-12')
        .copyWith(color: theme.color('--dsw-alias-label-tertiary'));
    final code = theme
        .textStyle('--dsw-font-markdown-code')
        .copyWith(color: theme.labelPrimary);

    final header = Row(
      children: [
        DshStatusDot(_status),
        const SizedBox(width: DshSpace.sm),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme
                .textStyle('--dsw-font-s-strong-14')
                .copyWith(color: theme.labelPrimary),
          ),
        ),
        if (_statusLabel.isNotEmpty) ...[
          const SizedBox(width: DshSpace.sm),
          Text(_statusLabel, style: meta),
        ],
      ],
    );

    final rawArgs = switch (call) {
      StartedToolCall(:final argsRaw) => argsRaw,
      ToolResult(:final callArgsRaw) => callArgsRaw ?? '',
      PreparingToolCall() => call.args.raw,
    };

    return DshCard(
      key: ValueKey('tool-card-${call.callId}'),
      padding: const EdgeInsets.symmetric(
        horizontal: DshSpace.md,
        vertical: DshSpace.xs,
      ),
      child: DshDisclosure(
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            if (summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: DshSpace.xs),
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: code.copyWith(color: theme.labelSecondary),
                ),
              ),
            if (preview != null && preview.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: DshSpace.xs),
                child: Text(
                  preview.cut ? '${preview.text}\n…' : preview.text,
                  key: const ValueKey('tool-result-preview'),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: code.copyWith(
                    color: (call as ToolResult).isError
                        ? theme.color('--dsw-alias-state-error-primary')
                        : theme.labelPrimary,
                  ),
                ),
              ),
            if (call is StartedToolCall || call is PreparingToolCall)
              const SizedBox(height: DshSpace.xs),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.only(bottom: DshSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rawArgs.isNotEmpty) ...[
                Text(_a('session.tool.args'), style: meta),
                const SizedBox(height: DshSpace.xs),
                SelectableText(
                  argsPretty(rawArgs),
                  key: const ValueKey('tool-args'),
                  style: code,
                ),
              ],
              if (call is ToolResult) ...[
                const SizedBox(height: DshSpace.sm),
                Text(
                  (call).isError
                      ? _a('session.tool.error')
                      : _a('session.tool.result'),
                  style: meta,
                ),
                const SizedBox(height: DshSpace.xs),
                SelectableText(
                  result!.length > maxResultChars
                      ? '${result.substring(0, maxResultChars)}\n… ${i18n.t('common', 'truncated')}'
                      : (result.isEmpty
                            ? i18n.t('conversation', 'terminal.noOutput')
                            : result),
                  key: const ValueKey('tool-result'),
                  style: code,
                ),
                if ((call).error?['reason'] case final String reason)
                  Padding(
                    padding: const EdgeInsets.only(top: DshSpace.xs),
                    child: Text(reason, style: meta),
                  ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: DshSpace.sm),
                  child: Text(_a('session.tool.noResult'), style: meta),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
