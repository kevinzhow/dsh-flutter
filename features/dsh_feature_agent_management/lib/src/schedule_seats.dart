import 'dart:convert';

import 'package:dsh_client/generated_schedule.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';

import 'schedules.dart';

/// Transcript JSON is narrowed before it acquires a clickable task identity.
TaskEntry? createdTask(ToolResult call, String sessionId) {
  if (call.name != 'schedule_create' ||
      call.callArgsRaw == null ||
      call.parentCallId != null ||
      call.isError ||
      call.content.length != 1) {
    return null;
  }
  final first = call.content.first;
  if (first is! Map || first['type'] != 'text' || first['text'] is! String) {
    return null;
  }
  try {
    final decoded = jsonDecode(first['text'] as String);
    if (decoded is! Map<String, dynamic>) return null;
    final raw = Map<String, Object?>.from(decoded);
    if (raw['id'] is! String ||
        (raw['id'] as String).isEmpty ||
        raw['prompt'] is! String ||
        (raw['prompt'] as String).isEmpty ||
        raw['scheduledAt'] is! String) {
      return null;
    }
    if (raw['title'] is! String || (raw['title'] as String).trim().isEmpty) {
      raw['title'] = (raw['prompt'] as String)
          .split(RegExp(r'\r?\n'))
          .first
          .trim();
    }
    if (raw['title'] == '') return null;
    final record = ScheduleRecord.fromJson(raw);
    if (record is ScheduleRecordUnrecognized) return null;
    return TaskEntry(
      ScheduleCatalogEntry.fromJson({
        ...record.toJson(),
        'sessionId': sessionId,
        'status': 'active',
      }),
    );
  } on Object {
    return null;
  }
}

class ScheduleCatalogAction extends StatefulWidget {
  const ScheduleCatalogAction({
    super.key,
    required this.service,
    required this.owner,
    required this.i18n,
    required this.openTask,
  });
  final ScheduleService service;
  final SessionOwner owner;
  final DshI18n i18n;
  final void Function(TaskEntry) openTask;
  @override
  State<ScheduleCatalogAction> createState() => _ScheduleCatalogActionState();
}

class _ScheduleCatalogActionState extends State<ScheduleCatalogAction> {
  final panel = DshPanelController();
  @override
  void dispose() {
    panel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TaskCatalogView(
    catalog: widget.service.catalog,
    builder: (context, snapshot) {
      final rows =
          snapshot.records
              .where(
                (r) =>
                    r.sessionId == widget.owner.sessionId &&
                    r.status == 'active',
              )
              .toList()
            ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      if (rows.isEmpty) return const SizedBox.shrink();
      return DshAnchoredPanel(
        controller: panel,
        panelWidth: 340,
        viewportMargin: 12,
        builder: (context, _) => DshButton(
          size: DshButtonSize.sm,
          semanticLabel: widget.i18n.t('schedule.manager', 'list.label'),
          onPressed: panel.toggle,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DshIcon(DshShellIcons.clock, size: 14),
              const SizedBox(width: 4),
              Text('${rows.length}'),
            ],
          ),
        ),
        panelBuilder: (context, _) => TaskCatalogView(
          catalog: widget.service.catalog,
          builder: (context, current) => Material(
            type: MaterialType.transparency,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final row in current.records.where(
                      (r) =>
                          r.sessionId == widget.owner.sessionId &&
                          r.status == 'active',
                    ))
                      TaskRow(
                        entry: row,
                        i18n: widget.i18n,
                        onOpen: () {
                          panel.close();
                          widget.openTask(row);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ScheduleSessionMark extends StatelessWidget {
  const ScheduleSessionMark({
    super.key,
    required this.service,
    required this.sessionId,
    required this.i18n,
    this.hover = false,
  });
  final ScheduleService service;
  final String sessionId;
  final DshI18n i18n;
  final bool hover;
  @override
  Widget build(BuildContext context) => TaskCatalogView(
    catalog: service.catalog,
    builder: (context, snapshot) {
      final rows =
          snapshot.records
              .where((r) => r.sessionId == sessionId && r.status == 'active')
              .toList()
            ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      if (rows.isEmpty) return const SizedBox.shrink();
      if (hover) {
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${rows.first.title}\n${rows.first.scheduledAt}',
              style: context.dsh.textStyle('--dsw-font-xxs-12'),
            ),
          ),
        );
      }
      return DshTooltip(
        label: i18n.t('schedule.manager', 'title'),
        child: const DshIcon(DshShellIcons.clock, size: 14),
      );
    },
  );
}

class ScheduleTaskTab extends StatelessWidget {
  const ScheduleTaskTab({
    super.key,
    required this.service,
    required this.owner,
    required this.i18n,
    required this.openSession,
    this.deviceZone = 'UTC',
    this.sessionBlock,
  });
  final ScheduleService service;
  final SidebarTabOwner owner;
  final DshI18n i18n;
  final void Function(String) openSession;
  final String deviceZone;
  final String? Function(String)? sessionBlock;
  @override
  Widget build(BuildContext context) {
    final sessionId = owner.params['sessionId'], id = owner.params['id'];
    return TaskCatalogView(
      catalog: service.catalog,
      builder: (context, snapshot) {
        final row = snapshot.records
            .where((r) => r.id == id && r.sessionId == sessionId)
            .firstOrNull;
        if (row == null) {
          return snapshot.status == 'ready'
              ? Center(
                  child: Text(i18n.t('schedule.manager', 'detail.missing')),
                )
              : TaskCatalogFeedback(
                  snapshot: snapshot,
                  i18n: i18n,
                  retry: () => service.catalog.refresh(),
                );
        }
        return TaskDetail(
          key: ValueKey('${row.sessionId}/${row.id}'),
          service: service,
          entry: row,
          i18n: i18n,
          onOpenSession: openSession,
          deviceZone: deviceZone,
          sessionBlock: sessionBlock,
        );
      },
    );
  }
}

void Function() registerScheduleSeats(
  SlotRegistry slots, {
  required ScheduleService service,
  required DshI18n Function() i18n,
  required void Function(SessionOwner, TaskEntry) openTask,
  required void Function(String) openSession,
  String deviceZone = 'UTC',
  String? Function(String)? sessionBlock,
}) {
  final offs = <void Function()>[
    slots.sidebarTabs.register(
      SidebarTabType(
        kind: 'scheduleTask',
        restorable: true,
        persistParams: (params) {
          final id = params['id'], session = params['sessionId'];
          if (id is! String ||
              id.isEmpty ||
              session is! String ||
              session.isEmpty) {
            return null;
          }
          return {'id': id, 'sessionId': session};
        },
      ),
    ),
    slots.register<SessionOwner, Widget>(
      DshSlots.conversationSessionHeaderActions.typed<SessionOwner, Widget>(),
      (owner) => ScheduleCatalogAction(
        key: ValueKey('schedule-${owner.sessionId}'),
        service: service,
        owner: owner,
        i18n: i18n(),
        openTask: (task) => openTask(owner, task),
      ),
      id: 'schedule-catalog',
      order: 40,
    ),
    slots.register<SidebarTabOwner, Widget>(
      DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
      (owner) => ScheduleTaskTab(
        service: service,
        owner: owner,
        i18n: i18n(),
        openSession: openSession,
        deviceZone: deviceZone,
        sessionBlock: sessionBlock,
      ),
      key: 'scheduleTask',
    ),
    slots.register<SidebarTabOwner, Widget>(
      DshSlots.sidebarRightPaneTabTitle.typed<SidebarTabOwner, Widget>(),
      (_) => Text(i18n().t('schedule.manager', 'detail.label')),
      key: 'scheduleTask',
    ),
    slots.register<Object?, Widget>(
      DshShellSlots.shellOverlay.typed<Object?, Widget>(),
      (_) => TaskDeleteNotice(service: service, i18n: i18n()),
      id: 'schedule-delete-notice',
    ),
    for (final hover in [false, true])
      slots.register<SessionRowOwner, Widget>(
        (hover
                ? DshSlots.sidebarSessionRowHover
                : DshSlots.sidebarSessionRowLeading)
            .typed<SessionRowOwner, Widget>(),
        (owner) => ScheduleSessionMark(
          service: service,
          sessionId: owner.sessionId,
          i18n: i18n(),
          hover: hover,
        ),
        id: 'schedule',
      ),
    slots.register<TurnTailOwner, Widget?>(
      DshSlots.conversationChatTurnTail.typed<TurnTailOwner, Widget?>(),
      (owner) {
        final rows = <TaskEntry>[];
        final calls =
            owner.snapshot
                .turnData<ToolData>(owner.turn, 'tool')
                .map((t) => t.root)
                .whereType<ToolResult>()
                .where(
                  (r) =>
                      r.seq <=
                      (owner.snapshot.timeline.turns[owner.turn]?.end?.seq ??
                          owner.seq),
                )
                .toList()
              ..sort((a, b) => a.seq.compareTo(b.seq));
        for (final call in calls) {
          final row = createdTask(call, owner.session.sessionId);
          if (row != null) rows.add(row);
        }
        if (rows.isEmpty) return null;
        return Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final row in rows)
                TaskRow(
                  entry: row,
                  i18n: i18n(),
                  onOpen: () => openTask(owner.session, row),
                ),
            ],
          ),
        );
      },
      id: 'schedule-created',
    ),
  ];
  return () {
    for (final off in offs.reversed) {
      off();
    }
  };
}
