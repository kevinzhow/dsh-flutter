import 'dart:convert';

import 'package:dsh_conversation/dsh_conversation.dart';

import 'raw_call.dart';

/// Translator bound to the `conversation` namespace.
typedef Tr = String Function(String key, [Map<String, Object?> params]);

/// One recorded entity, receipt or group of related values (dsh
/// `ToolDetailItem`).
class DetailItem {
  const DetailItem({
    this.title,
    this.subtitle,
    this.description,
    this.badge,
    this.status,
    this.previousStatus,
    this.change,
    this.fields = const [],
    this.groups = const [],
  });

  final String? title;
  final String? subtitle;
  final String? description;
  final ({String label, String tone})? badge;

  /// `completed`, `in_progress` or `pending`, with its localized label.
  final ({String value, String label})? status;
  final String? previousStatus;

  /// `added`, `removed` or `updated`, with its localized label.
  final ({String value, String label})? change;
  final List<({String label, String value})> fields;
  final List<({String label, List<DetailItem> items})> groups;

  DetailItem copyWith({
    String? previousStatus,
    ({String value, String label})? change,
  }) => DetailItem(
    title: title,
    subtitle: subtitle,
    description: description,
    badge: badge,
    status: status,
    previousStatus: previousStatus ?? this.previousStatus,
    change: change ?? this.change,
    fields: fields,
    groups: groups,
  );
}

/// Localized display data shared by the detail cards (dsh `ToolDetailsModel`).
class DetailsModel {
  const DetailsModel({
    required this.items,
    this.summary,
    this.empty,
    this.caption,
    this.unchanged,
  });
  final List<DetailItem> items;
  final String? summary;
  final String? empty;
  final String? caption;
  final ({String label, List<DetailItem> items})? unchanged;

  DetailsModel withCaption(String caption) => DetailsModel(
    items: items,
    summary: summary,
    empty: empty,
    caption: caption,
    unchanged: unchanged,
  );
}

bool _nonempty(Object? v) => v is String && v.trim().isNotEmpty;
bool _count(Object? v) => v is int && v >= 0;

/// The compact todo list of a `todo_write` call (dsh `todosDetail`).
DetailsModel? todosDetail(Map<String, Object?> args, Tr t) {
  final todos = args['todos'];
  if (todos is! List) return null;
  final items = <DetailItem>[];
  final seen = <String>{};
  for (final todo in todos) {
    if (todo is! Map<String, Object?> || !_nonempty(todo['content'])) {
      return null;
    }
    final status = todo['status'];
    if (status != 'completed' &&
        status != 'in_progress' &&
        status != 'pending') {
      return null;
    }
    final title = (todo['content'] as String).trim();
    if (!seen.add(title)) return null;
    items.add(
      DetailItem(
        title: title,
        status: (value: status as String, label: t('detail.todo.$status')),
      ),
    );
  }
  return DetailsModel(items: items, empty: t('detail.todo.empty'));
}

/// Todo changes relative to the preceding recorded write (dsh
/// `todoDiffModel`): details plus a change summary, or null for the generic
/// output.
({DetailsModel details, String? summary})? todoDiffModel(
  ToolCall call,
  TodoBaseline? baseline,
  bool hasMore,
  Tr t,
) {
  if (call is ToolResult && call.isError) return null;
  final parsed = parsedCall(call);
  final current = parsed?.name == 'todo_write'
      ? todosDetail(parsed!.args, t)
      : null;
  if (current == null) return null;
  final previousTodos = baseline?.todos;
  final previous = previousTodos == null
      ? null
      : [
          for (final todo in previousTodos)
            DetailItem(
              title: todo.content,
              status: (
                value: todo.status,
                label: t('detail.todo.${todo.status}'),
              ),
            ),
        ];
  if (baseline == null || (previous == null && hasMore)) {
    return (
      details: current.withCaption(t('todo.diff.unavailable')),
      summary: null,
    );
  }
  final previousByTitle = <String, DetailItem>{
    for (final item in previous ?? const <DetailItem>[]) item.title!: item,
  };
  final currentTitles = {for (final i in current.items) i.title};
  final retainedPositions = <String, int>{};
  var index = 0;
  for (final item in previous ?? const <DetailItem>[]) {
    if (currentTitles.contains(item.title)) {
      retainedPositions[item.title!] = index++;
    }
  }
  var retainedIndex = 0;
  final items = <DetailItem>[];
  final unchanged = <DetailItem>[];
  var added = 0;
  var updated = 0;
  for (final item in current.items) {
    final before = previousByTitle.remove(item.title);
    if (before == null) {
      added++;
      items.add(
        item.copyWith(
          change: (value: 'added', label: t('todo.diff.addedItem')),
        ),
      );
    } else {
      final moved = retainedPositions[item.title] != retainedIndex++;
      final statusChanged = before.status?.value != item.status?.value;
      if (statusChanged || moved) {
        updated++;
        items.add(
          item.copyWith(
            previousStatus: statusChanged ? before.status?.label : null,
            change: (
              value: 'updated',
              label: t(
                statusChanged ? 'todo.diff.updatedItem' : 'todo.diff.movedItem',
              ),
            ),
          ),
        );
      } else {
        unchanged.add(item);
      }
    }
  }
  for (final item in previousByTitle.values) {
    items.add(
      item.copyWith(
        change: (value: 'removed', label: t('todo.diff.removedItem')),
      ),
    );
  }
  final summary = [
    if (added > 0) t('todo.diff.added', {'count': added}),
    if (updated > 0) t('todo.diff.updated', {'count': updated}),
    if (previousByTitle.isNotEmpty)
      t('todo.diff.removed', {'count': previousByTitle.length}),
  ].join(' · ');
  return (
    summary: summary.isEmpty ? t('todo.diff.noChanges') : summary,
    details: DetailsModel(
      items: items,
      caption: t(previous == null ? 'todo.diff.initial' : 'todo.diff.compare'),
      empty: current.items.isEmpty && previous == null
          ? t('detail.todo.empty')
          : t('todo.diff.noChanges'),
      unchanged: unchanged.isEmpty
          ? null
          : (
              label: t('todo.diff.unchanged', {'count': unchanged.length}),
              items: unchanged,
            ),
    ),
  );
}

DetailsModel? _goalDetail(Object? value, Tr t) {
  if (value is! Map<String, Object?>) return null;
  if (value['goal'] == null && value.containsKey('goal')) {
    return DetailsModel(items: const [], empty: t('detail.goal.empty'));
  }
  final goal = value['goal'];
  if (goal is! Map<String, Object?> ||
      !_nonempty(goal['id']) ||
      !_nonempty(goal['objective']) ||
      !_count(goal['revision']) ||
      !_count(goal['roundsStarted']) ||
      !_count(goal['maxGoalRounds'])) {
    return null;
  }
  final phase = goal['phase'];
  if (phase != 'active' &&
      phase != 'paused' &&
      phase != 'blocked' &&
      phase != 'complete') {
    return null;
  }
  final activation = value['activation'];
  if (activation != 'armed' && activation != 'disarmed') return null;
  final fields = <({String label, String value})>[
    (
      label: t('detail.state'),
      value: t(
        phase == 'active' && activation == 'disarmed'
            ? 'detail.goal.disarmed'
            : 'detail.goal.$phase',
      ),
    ),
    (
      label: t('detail.goal.rounds'),
      value: '${goal['roundsStarted']} / ${goal['maxGoalRounds']}',
    ),
  ];
  if (goal.containsKey('blockedReason')) {
    final reason = goal['blockedReason'];
    if (reason is! Map<String, Object?> ||
        !_nonempty(reason['code']) ||
        !_nonempty(reason['message'])) {
      return null;
    }
    fields.add((
      label: t('detail.goal.reason'),
      value: reason['message']! as String,
    ));
  }
  return DetailsModel(
    items: [DetailItem(title: goal['objective']! as String, fields: fields)],
  );
}

String _interval(int seconds, Tr t) {
  if (seconds % 86400 == 0) {
    return t('detail.days', {'count': seconds ~/ 86400});
  }
  if (seconds % 3600 == 0) return t('detail.hours', {'count': seconds ~/ 3600});
  if (seconds % 60 == 0) return t('detail.minutes', {'count': seconds ~/ 60});
  return t('detail.seconds', {'count': seconds});
}

String _shortTime(String time) =>
    time.replaceAll(RegExp(r':00\.000$'), '').replaceAll(RegExp(r'\.000$'), '');

String? _weekdayText(Object? days, Tr t) {
  if (days is! List || days.isEmpty) return null;
  final labels = <String>[];
  for (final day in days) {
    if (day is! int || day < 1 || day > 7) return null;
    labels.add(t('detail.weekday.$day'));
  }
  return labels.join(t('detail.weekday.join'));
}

String _formatDate(DateTime date, String fallback) {
  final d = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

DetailItem? _scheduleItem(Object? value, Tr t) {
  if (value is! Map<String, Object?> ||
      !_nonempty(value['id']) ||
      !_nonempty(value['prompt']) ||
      value['scheduledAt'] is! String ||
      (value['deliveryMode'] != 'host' &&
          value['deliveryMode'] != 'session-local') ||
      (value['state'] != 'scheduled' && value['state'] != 'overdue')) {
    return null;
  }
  final date = DateTime.tryParse(value['scheduledAt']! as String);
  if (date == null) return null;
  final String frequency;
  switch (value['kind']) {
    case 'at':
      frequency = t('detail.schedule.once');
    case 'after':
      final s = value['afterSeconds'];
      if (!_count(s) || s == 0) return null;
      frequency = t('detail.schedule.once');
    case 'every':
      final s = value['everySeconds'];
      if (!_count(s) || s == 0) return null;
      frequency = t('detail.schedule.every', {
        'interval': _interval(s! as int, t),
      });
    case 'daily':
      if (!_nonempty(value['time']) || !_nonempty(value['timeZone'])) {
        return null;
      }
      frequency = t('detail.schedule.daily', {
        'time': _shortTime(value['time']! as String),
        'zone': value['timeZone'],
      });
    case 'weekly':
      final days = _weekdayText(value['weekdays'], t);
      if (!_nonempty(value['time']) ||
          !_nonempty(value['timeZone']) ||
          days == null) {
        return null;
      }
      frequency = t('detail.schedule.weekly', {
        'days': days,
        'time': _shortTime(value['time']! as String),
        'zone': value['timeZone'],
      });
    case 'cron':
      if (!_nonempty(value['expression']) || !_nonempty(value['timeZone'])) {
        return null;
      }
      frequency = t('detail.schedule.cron', {
        'expression': value['expression'],
        'zone': value['timeZone'],
      });
    default:
      return null;
  }
  return DetailItem(
    title: _nonempty(value['title'])
        ? value['title']! as String
        : value['prompt']! as String,
    fields: [
      (
        label: t('detail.schedule.when'),
        value: _formatDate(date, value['scheduledAt']! as String),
      ),
      (label: t('detail.schedule.frequency'), value: frequency),
      (label: t('detail.state'), value: t('detail.schedule.${value['state']}')),
    ],
  );
}

Object? _json(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// Derive a supported successful goal or schedule result into compact
/// details, or null for raw input/output (the subset of dsh
/// `detailsCardModel` this client ships; other recorded-result tools keep
/// their generic input and output).
DetailsModel? detailsCardModel(ToolCall call, Tr t) {
  if (call is! ToolResult || call.isError) return null;
  final parsed = parsedCall(call);
  if (parsed == null) return null;
  final text = singleResultText(call);
  if (text == null) return null;
  final value = _json(text);
  if (value == null) return null;
  switch (parsed.name) {
    case 'create_goal':
    case 'get_goal':
    case 'update_goal':
      return _goalDetail(value, t);
    case 'schedule_create':
    case 'schedule_update':
      final item = _scheduleItem(value, t);
      return item == null ? null : DetailsModel(items: [item]);
    case 'schedule_list':
      if (value is! List) return null;
      final items = <DetailItem>[];
      for (final entry in value) {
        final item = _scheduleItem(entry, t);
        if (item == null) return null;
        items.add(item);
      }
      return DetailsModel(
        items: items,
        summary: t('detail.schedule.count', {'count': items.length}),
        empty: t('detail.schedule.empty'),
      );
    case 'schedule_delete':
      if (value is! Map<String, Object?> ||
          !_nonempty(value['id']) ||
          value['deleted'] != true) {
        return null;
      }
      return DetailsModel(
        items: [
          DetailItem(
            title: value['id']! as String,
            fields: [
              (label: t('detail.state'), value: t('detail.schedule.deleted')),
            ],
          ),
        ],
      );
  }
  return null;
}
