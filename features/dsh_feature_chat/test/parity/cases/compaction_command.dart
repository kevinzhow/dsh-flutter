import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';

const _summary = '## Summary\n\nRemember **this** synthetic fact.';
Widget _card(ParityContext ctx, bool compaction) {
  final p = ctx.props, i18n = DshI18n(DshLocale.fromTag(ctx.locale));
  final manual = p['manual'] == true;
  final command = CommandData(
    seq: 1,
    time: 10001,
    commandId: 'fixture',
    name: p['orphan'] == true
        ? null
        : manual
        ? 'compact'
        : 'status',
    outcome: p['state'] == 'running'
        ? null
        : CommandOutcome(
            kind: p['state'] as String? ?? 'success',
            text: p['text'] as String?,
          ),
  );
  final child = compaction
      ? CompactionView(
          data: CompactionData(
            seq: 3,
            time: 10003,
            summary: p['summary'] == true ? _summary : null,
            summaryEventSeq: p['summary'] == true ? 2 : null,
            shadowedItemCount: p['counts'] == true ? 2 : null,
            shadowedTokenCount: p['counts'] == true ? 125 : null,
          ),
          i18n: i18n,
          title: manual
              ? i18n.t('chat', 'message.compaction.commandTitle')
              : null,
          fallbackSummary: manual ? 'Manual settlement' : null,
        )
      : manual
      ? ManualCompactionView(
          data: ManualCompactionData(command, null),
          i18n: i18n,
        )
      : CommandView(data: command, i18n: i18n);
  return Align(
    alignment: Alignment.topLeft,
    child: parityItem(
      'lifecycle-el',
      SizedBox(
        width: (p['width'] as num).toDouble(),
        child: parityItem('lifecycle-toggle', child),
      ),
    ),
  );
}

final Map<String, ParityCase> compactionCommandCases = {
  'chat.compaction': ParityCase(
    widgets: const ['dsh_feature_chat:CompactionView'],
    build: (ctx) => _card(ctx, true),
  ),
  'chat.command': ParityCase(
    widgets: const [
      'dsh_feature_chat:CommandView',
      'dsh_feature_chat:ManualCompactionView',
    ],
    build: (ctx) => _card(ctx, false),
  ),
};
