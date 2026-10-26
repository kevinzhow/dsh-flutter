import 'dart:convert';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'deliverables_tail.dart';
import 'review_address.dart';
import 'review_tab.dart';

class DeliverablesFeature {
  DeliverablesFeature({
    required this.model,
    required this.openFile,
    required this.openResource,
  });
  final DeliverablesModel model;
  final void Function(SessionOwner owner, String path) openFile;
  final void Function(SessionOwner owner, String address, int index)
  openResource;
  void openReview(SessionOwner owner, num seq, int turn, int index) =>
      openResource(
        owner,
        ChangesReviewAddress(owner.sessionId, seq, turn).address,
        index,
      );
  DshMarkdownFileMention? mention(
    ChatNodeOwner owner,
    String value,
    DshI18n i18n,
  ) {
    final assistant = owner.node.data;
    if (assistant is! AssistantData || assistant.finalNode == null) return null;
    final turn = owner.snapshot.timeline.turns[assistant.turn];
    if (turn?.status != BoundaryStatus.closed) return null;
    final tail = owner.snapshot
        .turnData<TurnTailData>(assistant.turn, 'turn-tail')
        .firstOrNull;
    if (tail?.closing?.finalNode?.seq != assistant.finalNode!.seq) return null;
    final seq = assistant.finalNode!.seq,
        data = turn!.data.get('deliverables') as DeliverablesTurnData?;
    final paths = {
      ...producedForClosing(data, seq),
      ...presentedForClosing(data, seq).map((f) => f.path),
    }.toList();
    final path = resolveProducedFileMention(
      paths,
      value,
      operations:
          data?.produced.where((p) => p.seq <= seq).toList() ?? const [],
    );
    return path == null
        ? null
        : DshMarkdownFileMention(
            title: path,
            label: i18n.t(
              'deliverables',
              'presented.previewButton',
              params: {'name': path},
            ),
            open: () => openFile(owner.session, path),
          );
  }
}

DeliverablesFeature registerDeliverablesFeature(
  SlotRegistry slots, {
  required DeliverablesModel model,
  required Observable<bool> showCodeDiff,
  required DshI18n Function() i18n,
  required void Function(SessionOwner owner, String path) openFile,
  required void Function(SessionOwner owner, String address, int index)
  openResource,
}) {
  final feature = DeliverablesFeature(
    model: model,
    openFile: openFile,
    openResource: openResource,
  );
  slots.register<TurnTailOwner, Widget?>(
    DshSlots.conversationChatTurnTail.typed<TurnTailOwner, Widget?>(),
    (owner) {
      final data = owner.snapshot.timeline.turns[owner.turn]?.data.get(
        'deliverables',
      ) as DeliverablesTurnData?;
      if (data?.changes == null &&
          presentedForClosing(data, owner.seq).isEmpty) {
        return null;
      }
      return DeliverablesTail(
        owner: owner,
        model: model,
        showCodeDiff: showCodeDiff,
        slots: slots,
        i18n: i18n(),
        openFile: (path) => openFile(owner.session, path),
        openReview: (seq, turn, index) =>
            feature.openReview(owner.session, seq, turn, index),
      );
    },
    id: 'deliverables',
  );
  slots.sidebarTabs.register(
    SidebarTabType(
      restorable: true,
      kind: 'changes-review',
      multiple: true,
      acceptsResource: (address) => ChangesReviewAddress.parse(address) != null,
      titleForResource: (address) => i18n().t(
        'deliverables',
        'review.title',
        params: {'turn': ChangesReviewAddress.parse(address)?.turn ?? ''},
      ),
    ),
  );
  slots.register<SidebarTabOwner, Widget>(
    DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
    (owner) => ChangesReviewTab(
      key: ValueKey(owner.id),
      owner: owner,
      model: model,
      slots: slots,
      i18n: i18n(),
      openFile: (path) => openFile(owner.session, path),
    ),
    key: 'changes-review',
  );
  slots.register<SidebarTabOwner, Widget>(
    DshSlots.sidebarRightPaneTabTitle.typed<SidebarTabOwner, Widget>(),
    (owner) => Text(
      i18n().t(
        'deliverables',
        'review.title',
        params: {
          'turn': ChangesReviewAddress.parse(owner.contentId)?.turn ?? '',
        },
      ),
    ),
    key: 'changes-review',
  );
  slots.register<ToolViewOwner, Widget>(
    DshSlots.toolCallToolview.typed<ToolViewOwner, Widget>(),
    (owner) => _PresentRow(call: owner.call, i18n: i18n()),
    key: 'present',
  );
  return feature;
}

class _PresentRow extends StatefulWidget {
  const _PresentRow({required this.call, required this.i18n});
  final ToolCall call;
  final DshI18n i18n;
  @override
  State<_PresentRow> createState() => _PresentRowState();
}

class _PresentRowState extends State<_PresentRow> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final call = widget.call, settled = call is ToolResult;
    final state = call is PreparingToolCall
        ? 'preparing'
        : !settled
        ? 'running'
        : call.error?['code'] == 'interrupted'
        ? 'stopped'
        : call.isError
        ? 'error'
        : 'ok';
    String t(String k) => widget.i18n.t('deliverables', k);
    final raw = switch (call) {
      StartedToolCall(:final argsRaw) => argsRaw,
      ToolResult(:final callArgsRaw) => callArgsRaw ?? '',
      _ => '',
    };
    var names = raw;
    try {
      final args = jsonDecode(raw);
      if (args is Map && args['files'] is List) {
        names = (args['files'] as List)
            .whereType<Map<String, Object?>>()
            .map((f) => f['path'])
            .whereType<String>()
            .join(', ');
      }
    } on FormatException {
      /* Streaming arguments remain raw. */
    }
    final output = settled
        ? call.content
              .map(
                (item) => item is Map && item['type'] == 'text'
                    ? item['text']
                    : jsonEncode(item),
              )
              .join('\n')
        : '';
    final details = output.isNotEmpty
        ? output
        : settled && call.error != null
        ? '${call.error!['name']}: ${call.error!['code']}'
        : '';
    return DshDisclosureRow(
      icon: DshIcons.deliverDoc,
      title: t('row.title'),
      open: expanded && details.isNotEmpty,
      expandable: details.isNotEmpty,
      onToggle: () => setState(() => expanded = !expanded),
      running: state == 'preparing' || state == 'running',
      collapsedContent: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 6),
          Text(t('row.$state')),
          const SizedBox(width: 6),
          Flexible(
            child: Text(names, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      children: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          details,
          style: context.dsh.textStyle('--dsw-font-markdown-code'),
        ),
      ),
    );
  }
}
