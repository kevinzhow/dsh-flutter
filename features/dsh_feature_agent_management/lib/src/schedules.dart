import 'dart:async';

import 'schedule_timing_controls.dart';
import 'schedule_format.dart';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart'
    show
        Material,
        MaterialType,
        InkWell,
        TextField,
        InputDecoration,
        DropdownButtonFormField,
        DropdownMenuItem,
        showDialog;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

String _t(DshI18n i, String key, [Map<String, Object?> params = const {}]) =>
    i.t('schedule.manager', key, params: params);

/// A subscription is owned by the mounted surface. Hidden sidebar tabs release
/// their catalog, while simultaneous viewers share the root's authoritative data.
class TaskCatalogView extends StatefulWidget {
  const TaskCatalogView({
    super.key,
    required this.catalog,
    required this.builder,
  });
  final TaskCatalog<TaskEntry> catalog;
  final Widget Function(BuildContext, CatalogSnapshot<TaskEntry>) builder;
  @override
  State<TaskCatalogView> createState() => _TaskCatalogViewState();
}

class _TaskCatalogViewState extends State<TaskCatalogView> {
  void Function()? off;
  int _binding = 0;
  void watchLater() {
    final binding = ++_binding;
    scheduleMicrotask(() {
      if (mounted && binding == _binding) watch();
    });
  }

  @override
  void initState() {
    super.initState();
    watchLater();
  }

  void watch() {
    off = widget.catalog.watch(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(TaskCatalogView old) {
    super.didUpdateWidget(old);
    if (!identical(old.catalog, widget.catalog)) {
      off?.call();
      watchLater();
    }
  }

  @override
  void dispose() {
    _binding++;
    off?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.catalog.snapshot);
}

class TaskManagerPage extends StatefulWidget {
  const TaskManagerPage({
    super.key,
    required this.service,
    required this.i18n,
    required this.onNew,
    required this.onOpenSession,
    this.deviceZone = 'UTC',
    this.sessionBlock,
  });
  final ScheduleService service;
  final DshI18n i18n;
  final VoidCallback onNew;
  final void Function(String) onOpenSession;
  final String deviceZone;
  final String? Function(String)? sessionBlock;
  @override
  State<TaskManagerPage> createState() => _TaskManagerPageState();
}

class _TaskManagerPageState extends State<TaskManagerPage> {
  final search = TextEditingController();
  String filter = 'all';
  String? selected;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String t(String key) => _t(widget.i18n, key);
  @override
  Widget build(BuildContext context) => TaskCatalogView(
    catalog: widget.service.catalog,
    builder: (context, snapshot) {
      final selectedRow = snapshot.records
          .where((r) => r.id == selected)
          .firstOrNull;
      if (snapshot.status == 'ready' &&
          selected != null &&
          selectedRow == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              !widget.service.catalog.snapshot.records.any(
                (r) => r.id == selected,
              )) {
            setState(() => selected = null);
          }
        });
      }
      final query = search.text.trim().toLowerCase();
      final rows =
          snapshot.records
              .where(
                (r) =>
                    (filter == 'all' || filter == r.status) &&
                    [
                      r.title,
                      r.prompt,
                      r.sessionId,
                    ].any((s) => s.toLowerCase().contains(query)),
              )
              .toList()
            ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      final list = ListView(
        key: const ValueKey('task-manager-list'),
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 600 ? 24 : 48,
          28,
          24,
          48,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t('title'),
                  style: context.dsh
                      .textStyle('--dsw-font-l-20')
                      .copyWith(height: 1.4, fontWeight: FontWeight.w500),
                ),
              ),
              DshButton(
                size: DshButtonSize.sm,
                onPressed: widget.onNew,
                child: Text(t('new.action')),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            children: [
              for (final f in ['all', 'active', 'inactive'])
                DshButton(
                  variant: filter == f
                      ? DshButtonVariant.toolbar
                      : DshButtonVariant.ghost,
                  size: DshButtonSize.sm,
                  onPressed: () => setState(() => filter = f),
                  child: Semantics(
                    selected: filter == f,
                    child: Text(
                      t(f == 'all' ? 'statusFilter.all' : 'status.$f'),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('task-search'),
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: t('search.placeholder'),
              labelText: t('search.label'),
              isDense: true,
            ),
          ),
          const SizedBox(height: 18),
          if (snapshot.status != 'ready')
            TaskCatalogFeedback(
              snapshot: snapshot,
              i18n: widget.i18n,
              retry: () => unawaited(widget.service.catalog.refresh()),
            ),
          if (snapshot.status == 'ready' && rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  const DshIcon(DshShellIcons.clock, size: 24),
                  const SizedBox(height: 12),
                  Text(
                    t(
                      filter == 'inactive' && query.isEmpty
                          ? 'list.emptyInactive'
                          : snapshot.records.isEmpty
                          ? 'list.empty'
                          : 'list.noMatches',
                    ),
                  ),
                  DshButton(
                    onPressed: widget.onNew,
                    child: Text(t('empty.action')),
                  ),
                ],
              ),
            ),
          for (final row in rows)
            TaskRow(
              entry: row,
              i18n: widget.i18n,
              selected: row.id == selected,
              onOpen: () => setState(() => selected = row.id),
            ),
        ],
      );
      final detail = selectedRow == null
          ? null
          : TaskDetail(
              key: ValueKey('${selectedRow.sessionId}/${selectedRow.id}'),
              service: widget.service,
              entry: selectedRow,
              i18n: widget.i18n,
              deviceZone: widget.deviceZone,
              onClose: () => setState(() => selected = null),
              onOpenSession: widget.onOpenSession,
              sessionBlock: widget.sessionBlock,
            );
      return Material(
        type: MaterialType.transparency,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                setState(() => selected = null),
          },
          child: LayoutBuilder(
            builder: (context, box) => detail == null
                ? list
                : box.maxWidth < 760
                ? detail
                : Row(
                    children: [
                      Expanded(child: list),
                      SizedBox(width: 380, child: detail),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}

class TaskCatalogFeedback extends StatelessWidget {
  const TaskCatalogFeedback({
    super.key,
    required this.snapshot,
    required this.i18n,
    required this.retry,
  });
  final CatalogSnapshot<TaskEntry> snapshot;
  final DshI18n i18n;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Text(
          _t(i18n, snapshot.status == 'error' ? 'list.error' : 'list.loading'),
        ),
        if (snapshot.status == 'error')
          DshButton(onPressed: retry, child: Text(_t(i18n, 'list.retry'))),
      ],
    ),
  );
}

class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.entry,
    required this.i18n,
    required this.onOpen,
    this.selected = false,
  });
  final TaskEntry entry;
  final DshI18n i18n;
  final VoidCallback onOpen;
  final bool selected;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      key: ValueKey('task-row-${entry.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: DshIcon(DshShellIcons.clock, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: context.dsh.textStyle('--dsw-font-s-14'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_t(i18n, 'status.${entry.status}')} · ${taskFrequency(entry, i18n)}',
                    style: context.dsh
                        .textStyle('--dsw-font-xxs-12')
                        .copyWith(color: context.dsh.labelSecondary),
                  ),
                  if (entry.status == 'active')
                    TaskNextRun(
                      instant: entry.scheduledAt,
                      i18n: i18n,
                      prefix: _t(i18n, 'list.nextPrefix'),
                      style: context.dsh
                          .textStyle('--dsw-font-xxs-12')
                          .copyWith(color: context.dsh.labelSecondary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String taskFrequency(TaskEntry entry, DshI18n i18n) {
  String t(String key, [Map<String, Object?> params = const {}]) =>
      _t(i18n, key, params);
  String clock(String value) => value
      .replaceFirst(RegExp(r'\.\d+$'), '')
      .replaceFirst(RegExp(r':00$'), '');
  switch (entry.kind) {
    case 'every':
      final seconds = entry.raw['everySeconds']! as num;
      final unit = const [
        ('day', 86400),
        ('hour', 3600),
        ('minute', 60),
        ('second', 1),
      ].firstWhere((u) => seconds % u.$2 == 0);
      final value = seconds / unit.$2;
      return t('frequency.every', {
        'value': value == value.roundToDouble() ? value.toInt() : value,
        'unit': t('unit.${unit.$1}.${value == 1 ? 'one' : 'other'}', {
          'count': value,
        }),
      });
    case 'daily':
      return t('frequency.daily', {
        'time': clock(entry.raw['time']! as String),
        'timeZone': entry.raw['timeZone'],
      });
    case 'weekly':
      return t('frequency.weekly', {
        'time': clock(entry.raw['time']! as String),
        'timeZone': entry.raw['timeZone'],
        'weekdays': (entry.raw['weekdays'] as List)
            .map((d) => t('frequency.weekday.$d'))
            .join(t('frequency.weekday.join')),
      });
    case 'cron':
      return t('frequency.cron', {
        'expression': entry.raw['expression'],
        'timeZone': entry.raw['timeZone'],
      });
    default:
      return t('frequency.once');
  }
}

class TaskDetail extends StatefulWidget {
  const TaskDetail({
    super.key,
    required this.service,
    required this.entry,
    required this.i18n,
    required this.onOpenSession,
    this.onClose,
    this.deviceZone = 'UTC',
    this.sessionBlock,
  });
  final ScheduleService service;
  final TaskEntry entry;
  final DshI18n i18n;
  final void Function(String) onOpenSession;
  final VoidCallback? onClose;
  final String deviceZone;
  final String? Function(String)? sessionBlock;
  @override
  State<TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<TaskDetail> {
  late final draft = TaskEditDraft(
    widget.entry,
    widget.service.update,
    deviceZone: widget.deviceZone,
  );
  final controllers = <String, TextEditingController>{};
  StreamSubscription<int>? sub;
  bool history = false;
  late String intervalUnit = _preferredUnit(draft.shown.draft['seconds']!);
  String _preferredUnit(String seconds) {
    final n = int.tryParse(seconds);
    return n != null && n > 0 && n % 3600 == 0
        ? 'hour'
        : n != null && n > 0 && n % 60 == 0
        ? 'minute'
        : 'second';
  }

  int get intervalScale => intervalUnit == 'hour'
      ? 3600
      : intervalUnit == 'minute'
      ? 60
      : 1;
  String t(String key) => _t(widget.i18n, key);
  @override
  void initState() {
    super.initState();
    sub = draft.changed.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(TaskDetail old) {
    super.didUpdateWidget(old);
    if (!identical(old.entry, widget.entry)) draft.accept(widget.entry);
  }

  @override
  void dispose() {
    unawaited(sub?.cancel());
    unawaited(draft.dispose());
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(
    String name,
    String label,
    String text,
    void Function(String) edit, {
    int lines = 1,
  }) {
    final c = controllers.putIfAbsent(
      name,
      () => TextEditingController(text: text),
    );
    if (c.text != text) {
      c.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        key: ValueKey('task-edit-$name'),
        controller: c,
        maxLines: lines,
        enabled: draft.writable && !draft.saving,
        onChanged: edit,
        style: context.dsh.textStyle('--dsw-font-s-14'),
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

  Future<void> remove() async {
    final row = widget.entry, service = widget.service;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            borderRadius: BorderRadius.circular(12),
            color: context.dsh.bgBase,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('delete.title')),
                    const SizedBox(height: 12),
                    Text(t('delete.description')),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      children: [
                        DshButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(t('delete.cancel')),
                        ),
                        DshButton(
                          key: const ValueKey('task-delete-confirm'),
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(t('delete.confirm')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await service.delete(row.id);
    if (mounted && result == 'deleted') widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final v = draft.shown;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('detail.label'),
                    style: context.dsh.textStyle('--dsw-font-s-14'),
                  ),
                ),
                if (widget.onClose != null)
                  DshButton(
                    size: DshButtonSize.sm,
                    semanticLabel: t('detail.close'),
                    onPressed: widget.onClose,
                    child: const DshIcon(DshIcons.close, size: 14),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              children: [
                DshButton(
                  size: DshButtonSize.sm,
                  onPressed: () => setState(() => history = false),
                  child: Text(t('detail.rule')),
                ),
                DshButton(
                  size: DshButtonSize.sm,
                  onPressed: () => setState(() => history = true),
                  child: Text(t('detail.records')),
                ),
              ],
            ),
          ),
          Expanded(
            child: history
                ? TaskDeliveryHistory(
                    key: ValueKey(
                      '${widget.entry.sessionId}/${widget.entry.id}',
                    ),
                    service: widget.service,
                    entry: widget.entry,
                    i18n: widget.i18n,
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      field(
                        'title',
                        t('detail.name'),
                        v.title,
                        (s) => draft.edit(title: s),
                      ),
                      field(
                        'prompt',
                        t('detail.instruction'),
                        v.prompt,
                        (s) => draft.edit(prompt: s),
                        lines: 4,
                      ),
                      Text(t('status.${widget.entry.status}')),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey('${v.kind}-$intervalUnit'),
                        initialValue: v.kind == 'every'
                            ? 'every-$intervalUnit'
                            : v.kind,
                        decoration: InputDecoration(
                          labelText: t('rule.repeat'),
                        ),
                        items: [
                          for (final k in [
                            'once',
                            'daily',
                            'weekdays',
                            'weekly',
                            'every-hour',
                            'every-minute',
                            'every-second',
                            'cron',
                          ])
                            DropdownMenuItem(
                              value: k,
                              child: Text(
                                t(switch (k) {
                                  'every-hour' => 'rule.everyHours',
                                  'every-minute' => 'rule.everyMinutes',
                                  'every-second' => 'rule.everySeconds',
                                  _ => 'rule.$k',
                                }),
                              ),
                            ),
                        ],
                        onChanged: draft.writable && !draft.saving
                            ? (s) {
                                if (s != null) {
                                  if (s.startsWith('every-')) {
                                    setState(
                                      () => intervalUnit = s.substring(6),
                                    );
                                    draft.chooseKind('every');
                                  } else {
                                    draft.chooseKind(s);
                                  }
                                }
                              }
                            : null,
                      ),
                      const SizedBox(height: 20),
                      if (v.kind == 'once')
                        field(
                          'date',
                          t('timing.date'),
                          v.draft['date']!,
                          (s) => draft.edit(field: 'date', value: s),
                        ),
                      if (!['every', 'cron'].contains(v.kind))
                        field(
                          'time',
                          t('timing.time'),
                          v.draft['time']!,
                          (s) => draft.edit(field: 'time', value: s),
                        ),
                      if (v.kind != 'every')
                        TaskZonePicker(
                          value: v.draft['timeZone']!,
                          enabled: draft.writable && !draft.saving,
                          i18n: widget.i18n,
                          onChanged: (zone) =>
                              draft.edit(field: 'timeZone', value: zone),
                        ),
                      if (v.kind == 'every')
                        field(
                          'seconds',
                          t('timing.interval'),
                          num.tryParse(v.draft['seconds']!) == null
                              ? ''
                              : (num.parse(v.draft['seconds']!) / intervalScale)
                                    .toString()
                                    .replaceFirst(RegExp(r'\.0$'), ''),
                          (s) => draft.edit(
                            field: 'seconds',
                            value: s.isEmpty || num.tryParse(s) == null
                                ? s
                                : (num.parse(s) * intervalScale)
                                      .round()
                                      .toString(),
                          ),
                        ),
                      if (v.kind == 'cron') ...[
                        TaskCronBuilder(
                          expression: v.draft['expression']!,
                          enabled: draft.writable && !draft.saving,
                          i18n: widget.i18n,
                          onChanged: (s) =>
                              draft.edit(field: 'expression', value: s),
                        ),
                        field(
                          'expression',
                          t('rule.cronLabel'),
                          v.draft['expression']!,
                          (s) => draft.edit(field: 'expression', value: s),
                        ),
                      ],
                      if (v.kind == 'weekly')
                        Wrap(
                          spacing: 4,
                          children: [
                            for (var day = 1; day <= 7; day++)
                              DshButton(
                                variant: v.weekdays.contains(day)
                                    ? DshButtonVariant.toolbar
                                    : DshButtonVariant.ghost,
                                size: DshButtonSize.sm,
                                onPressed: draft.writable && !draft.saving
                                    ? () => draft.toggleWeekday(day)
                                    : null,
                                child: Semantics(
                                  selected: v.weekdays.contains(day),
                                  child: Text('$day'),
                                ),
                              ),
                          ],
                        ),
                      if (!draft.writable) Text(t('timing.inactive')),
                      if (draft.failure != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(t(draft.failure!)),
                        ),
                      if (draft.dirty) ...[
                        const SizedBox(height: 16),
                        Text(t('rule.unsaved')),
                        Wrap(
                          spacing: 8,
                          children: [
                            DshButton(
                              key: const ValueKey('task-save'),
                              onPressed: draft.saving || !draft.writable
                                  ? null
                                  : () => unawaited(draft.save()),
                              child: Text(
                                t(draft.saving ? 'rule.saving' : 'rule.save'),
                              ),
                            ),
                            DshButton(
                              onPressed: draft.saving ? null : draft.cancel,
                              child: Text(t('rule.cancel')),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text('${t('detail.id')}: ${widget.entry.id}'),
                      const SizedBox(height: 8),
                      if (widget.sessionBlock?.call(widget.entry.sessionId)
                          case final message?)
                        Text(t(message)),
                      DshButton(
                        semanticLabel: t('detail.openSession'),
                        onPressed:
                            widget.sessionBlock?.call(widget.entry.sessionId) !=
                                null
                            ? null
                            : () {
                                if (widget.sessionBlock?.call(
                                      widget.entry.sessionId,
                                    ) ==
                                    null) {
                                  widget.onOpenSession(widget.entry.sessionId);
                                }
                              },
                        child: Text(t('detail.session')),
                      ),
                      const SizedBox(height: 16),
                      DshButton(
                        onPressed:
                            widget.service.catalog.snapshot.deleting.contains(
                              widget.entry.id,
                            )
                            ? null
                            : () => unawaited(remove()),
                        child: Text(t('delete.action')),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class TaskDeliveryHistory extends StatefulWidget {
  const TaskDeliveryHistory({
    super.key,
    required this.service,
    required this.entry,
    required this.i18n,
  });
  final ScheduleService service;
  final TaskEntry entry;
  final DshI18n i18n;
  @override
  State<TaskDeliveryHistory> createState() => _TaskDeliveryHistoryState();
}

class _TaskDeliveryHistoryState extends State<TaskDeliveryHistory> {
  late final model = TaskDeliveryModel(
    widget.service.remotes,
    widget.entry.sessionId,
    widget.entry.id,
  );
  StreamSubscription<int>? sub;
  bool retentionOpen = false;
  final expanded = <String>{};
  String t(String key) => _t(widget.i18n, key);
  @override
  void initState() {
    super.initState();
    sub = model.changed.changes.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(model.load());
  }

  @override
  void didUpdateWidget(TaskDeliveryHistory old) {
    super.didUpdateWidget(old);
    if (old.entry.latestMessageId != widget.entry.latestMessageId) {
      unawaited(model.load(refresh: true));
    }
  }

  @override
  void dispose() {
    unawaited(sub?.cancel());
    unawaited(model.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      if (model.loading) Text(t('delivery.loading')),
      if (model.failure != null) ...[
        Text(t(model.failure!)),
        DshButton(
          onPressed: () => unawaited(model.load(before: model.retryBefore)),
          child: Text(
            t(
              model.failure == 'delivery.cursorError'
                  ? 'delivery.refresh'
                  : 'delivery.retry',
            ),
          ),
        ),
      ],
      if (model.settled &&
          model.records.isEmpty &&
          !model.loading &&
          model.failure == null)
        Text(t('delivery.empty')),
      for (final r in model.records)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                taskAbsolute(r.scheduledAt, widget.i18n),
                style: context.dsh.textStyle('--dsw-font-xxs-12'),
              ),
              if (r.prompt != null) ...[
                const SizedBox(height: 8),
                Text(
                  r.prompt!,
                  maxLines: expanded.contains(r.messageId) ? null : 3,
                  overflow: expanded.contains(r.messageId)
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
                if (r.prompt!.length > 120 ||
                    '\n'.allMatches(r.prompt!).length >= 3)
                  DshButton(
                    size: DshButtonSize.sm,
                    onPressed: () => setState(() {
                      if (!expanded.remove(r.messageId)) {
                        expanded.add(r.messageId);
                      }
                    }),
                    child: Text(
                      t(
                        expanded.contains(r.messageId)
                            ? 'delivery.collapse'
                            : 'delivery.expand',
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      if (model.nextBefore != null && model.failure == null)
        DshButton(
          onPressed: model.loading
              ? null
              : () => unawaited(model.load(before: model.nextBefore)),
          child: Text(t('delivery.loadMore')),
        ),
      if (model.earlierPruned &&
          model.records.isNotEmpty &&
          model.nextBefore == null &&
          !model.loading &&
          model.failure == null) ...[
        Text(t('delivery.pruned')),
        DshButton(
          onPressed: () => setState(() => retentionOpen = !retentionOpen),
          child: Text(t('delivery.retention')),
        ),
        if (retentionOpen) ...[
          if (model.retention case final bounds?)
            Text(
              _t(widget.i18n, 'delivery.retentionBounds', {
                'days': bounds.days,
                'records': bounds.records,
              }),
            ),
          Text(t('delivery.retentionExplanation')),
        ],
      ],
    ],
  );
}

class TaskDeleteNotice extends StatelessWidget {
  const TaskDeleteNotice({
    super.key,
    required this.service,
    required this.i18n,
  });
  final ScheduleService service;
  final DshI18n i18n;
  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: service.notice.changes,
    builder: (context, _) {
      final notice = service.notice.value;
      if (notice == null) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            color: context.dsh.bgBase,
            borderRadius: BorderRadius.circular(12),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _t(
                        i18n,
                        notice.outcome == 'deleted'
                            ? 'toast.deleted'
                            : 'toast.deleteFailed',
                      ),
                    ),
                  ),
                  DshButton(
                    size: DshButtonSize.sm,
                    semanticLabel: _t(i18n, 'detail.close'),
                    onPressed: () => service.dismissNotice(notice.revision),
                    child: const DshIcon(DshIcons.close, size: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
