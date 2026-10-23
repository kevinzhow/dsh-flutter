// dsh's tool rows (ui-tool) rendered through the real slot dispatch: the tool-call tree, the keyed
// `tool.call.toolview` entries and the generic fallback. Props = the React host's `tool.card` input:
// {layout, items: [{id, toolName, phase, callId, argsRaw, result?, cwd, home, expanded}]}.
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_tool/dsh_feature_tool.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:flutter/widgets.dart';

ToolCall _call(Map<String, dynamic> item) {
  final name = item['toolName'] as String;
  final callId = item['callId'] as String;
  final argsRaw = item['argsRaw'] as String;
  switch (item['phase']) {
    case 'preparing':
      return PreparingToolCall(
        callId: callId,
        name: name,
        args: PartialArguments()..append(argsRaw),
        subCalls: const [],
        turn: 1,
        step: 1,
        time: 1,
      );
    case 'start':
      return StartedToolCall(
        callId: callId,
        name: name,
        args: PartialArguments.fromText(argsRaw),
        subCalls: const [],
        argsRaw: argsRaw,
        turn: 1,
        step: 1,
        time: 1,
      );
    default:
      final result = Map<String, dynamic>.from(item['result'] as Map);
      return ToolResult(
        callId: callId,
        name: name,
        args: PartialArguments.fromText(argsRaw),
        subCalls: const [],
        seq: 9,
        time: 1,
        callArgsRaw: argsRaw,
        content: List<Object?>.from(result['content'] as List),
        isError: result['isError'] == true,
        error: result['error'] == null
            ? null
            : Map<String, Object?>.from(result['error'] as Map),
        meta: result['meta'],
      );
  }
}

final Map<String, ParityCase> toolCases = {
  'tool.card': ParityCase(
    widgets: const [
      'dsh_feature_tool:ToolCallTree',
      'dsh_feature_tool:ToolRow',
      'dsh_ui:DshTerminalBlock',
      'dsh_ui:DshDiffBlock',
    ],
    build: (ctx) {
      final items = (ctx.props['items'] as List).cast<Map<String, dynamic>>();
      final expanded = {
        for (final i in items) i['callId'] as String: i['expanded'] == true,
      };
      final base = testSessionOwner('parity');
      final owner = SessionOwner(
        session: base.session,
        conversation: base.conversation,
        actions: base.actions,
        cwdReader: () => items.first['cwd'] as String?,
        hostHome: items.first['home'] as String? ?? '',
      );
      final slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      registerToolFeature(
        slots,
        i18n: () => DshI18n(DshLocale.fromTag(ctx.locale)),
        // dsh's file paths always read as links; the app wires the real opener.
        actions: ToolHostActions(openFile: (path, {line}) {}),
        expandedByDefault: (id) => expanded[id] ?? false,
      );
      return ParityStack(
        layout: ctx.layout,
        children: [
          for (final item in items)
            parityItem(
              item['id'] as String,
              slots.renderKeyed<ChatNodeOwner, Widget>(
                    chatNodeSlot,
                    'tool-call',
                    ChatNodeOwner(
                      session: owner,
                      node: ViewNode(
                        key: item['id'] as String,
                        kind: 'tool-call',
                        id: item['callId'] as String,
                        target: 'chat',
                        anchorSeq: 9,
                        location: const SessionLocation(),
                        visible: true,
                        data: ToolData(_call(item)),
                      ),
                      snapshot: ChatSnapshot.empty,
                    ),
                  ) ??
                  const SizedBox.shrink(),
            ),
        ],
      );
    },
  ),
};
