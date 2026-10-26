import 'dart:convert';

import 'package:dsh_client/generated_schedule.dart';
import 'package:timezone/data/latest.dart' as zone_data;
import 'package:timezone/timezone.dart' as tz;

import '../observable.dart';
import 'schedules.dart';

bool _zonesReady = false;
void _zones() {
  if (!_zonesReady) {
    zone_data.initializeTimeZones();
    _zonesReady = true;
  }
}

tz.Location _location(String zone) =>
    zone == 'UTC' || zone == 'GMT' ? tz.UTC : tz.getLocation(zone);

String zonedTaskClock(String instant, String zone) {
  final at = DateTime.tryParse(instant);
  if (at == null) return '';
  try {
    _zones();
    final d = tz.TZDateTime.from(at, _location(zone));
    String p(int n, int width) => n.toString().padLeft(width, '0');
    return '${p(d.year, 4)}-${p(d.month, 2)}-${p(d.day, 2)}T${p(d.hour, 2)}:${p(d.minute, 2)}:${p(d.second, 2)}.${p(d.millisecond, 3)}';
  } on Object {
    return '';
  }
}

List<String> taskTimeZones() {
  _zones();
  return {'UTC', ...tz.timeZoneDatabase.locations.keys}.toList()..sort();
}

Map<String, Object?>? parseTaskCron(String expression) {
  if (expression.isEmpty || expression.trim() != expression) return null;
  final fields = expression.split(RegExp(r'\s+'));
  if (fields.length != 5) return null;
  const specs = [(0, 59, 60), (0, 23, 24), (1, 31, 31), (1, 12, 12), (0, 7, 7)];
  final result = <String, Object?>{};
  const names = ['minutes', 'hours', 'daysOfMonth', 'months', 'daysOfWeek'];
  for (var index = 0; index < 5; index++) {
    final (min, max, count) = specs[index];
    final matched = <int>{};
    int? number(String text, {bool step = false}) {
      final v = int.tryParse(text);
      return v != null &&
              v <= 9007199254740991 &&
              (step ? v >= 1 : v >= min && v <= max)
          ? v
          : null;
    }

    for (final element in fields[index].split(',')) {
      int start, end, step = 1;
      if (element == '*') {
        start = min;
        end = max;
      } else if (element.startsWith('*')) {
        final m = RegExp(r'^\*/(\d+)$').firstMatch(element);
        if (m == null) return null;
        final n = number(m[1]!, step: true);
        if (n == null) return null;
        start = min;
        end = max;
        step = n;
      } else {
        final m = RegExp(r'^(\d+)(?:-(\d+))?(?:/(\d+))?$').firstMatch(element);
        if (m == null) return null;
        final first = number(m[1]!);
        if (first == null) return null;
        start = first;
        if (m[2] == null) {
          if (m[3] != null) return null;
          end = start;
        } else {
          final last = number(m[2]!);
          if (last == null || start > last) return null;
          end = last;
          final n = m[3] == null ? 1 : number(m[3]!, step: true);
          if (n == null) return null;
          step = n;
        }
      }
      for (var v = start; v <= end; v += step) {
        matched.add(index == 4 && v == 7 ? 0 : v);
      }
    }
    final values = matched.toList()..sort();
    final starred = fields[index].startsWith('*'),
        full = values.length == count;
    result[names[index]] = {
      'values': values,
      'starred': starred,
      'full': full,
      'unrestricted': starred && full,
    };
  }
  return result;
}

const _timingFields = ['date', 'time', 'timeZone', 'seconds', 'expression'];
bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);
bool _weekdays(List<int> days) =>
    days.length == 5 && const [1, 2, 3, 4, 5].every(days.contains);
String _storedKind(String kind) => kind == 'weekdays' ? 'weekly' : kind;
String _seconds(String time) =>
    RegExp(r'^\d{2}:\d{2}$').hasMatch(time) ? '$time:00' : time;

class TaskRuleValues {
  TaskRuleValues({
    required this.title,
    required this.prompt,
    required this.kind,
    required Map<String, String> draft,
    required List<int> weekdays,
  }) : draft = Map.unmodifiable(draft),
       weekdays = List.unmodifiable(weekdays);
  final String title, prompt, kind;
  final Map<String, String> draft;
  final List<int> weekdays;
  Map<String, Object?> toJson() => {
    'title': title,
    'prompt': prompt,
    'kind': kind,
    'draft': draft,
    'weekdays': weekdays,
  };
  String get timingKey =>
      jsonEncode([kind, ..._timingFields.map((f) => draft[f]), weekdays]);
  String get key => jsonEncode([title.trim(), prompt.trim(), timingKey]);
  TaskRuleValues copy({
    String? title,
    String? prompt,
    String? kind,
    Map<String, String>? draft,
    List<int>? weekdays,
  }) => TaskRuleValues(
    title: title ?? this.title,
    prompt: prompt ?? this.prompt,
    kind: kind ?? this.kind,
    draft: draft ?? this.draft,
    weekdays: weekdays ?? this.weekdays,
  );
}

TaskRuleValues taskRuleValues(TaskEntry entry, {String deviceZone = 'UTC'}) {
  final raw = entry.raw, kind = entry.kind;
  final draft = {for (final field in _timingFields) field: ''};
  var shown = kind;
  List<int> days = [1];
  switch (kind) {
    case 'after' || 'at':
      shown = 'once';
      final wall = zonedTaskClock(entry.scheduledAt, deviceZone);
      draft['date'] = wall.isEmpty ? '' : wall.substring(0, 10);
      draft['time'] = wall.isEmpty ? '' : wall.substring(11);
      draft['timeZone'] = deviceZone;
    case 'every':
      draft['seconds'] = '${raw['everySeconds']}';
    case 'daily' || 'weekly':
      draft['time'] = raw['time']! as String;
      draft['timeZone'] = raw['timeZone']! as String;
      if (kind == 'weekly') {
        days = (raw['weekdays']! as List).cast<int>();
        shown = _weekdays(days) ? 'weekdays' : 'weekly';
      }
    case 'cron':
      draft['expression'] = raw['expression']! as String;
      draft['timeZone'] = raw['timeZone']! as String;
  }
  if (kind != 'weekly') {
    try {
      _zones();
      final zone = (raw['timeZone'] as String?) ?? deviceZone;
      days = [
        tz.TZDateTime.from(
          DateTime.parse(entry.scheduledAt),
          _location(zone),
        ).weekday,
      ];
    } on Object {
      days = [DateTime.tryParse(entry.scheduledAt)?.weekday ?? 1];
    }
  }
  return TaskRuleValues(
    title: entry.title,
    prompt: entry.prompt,
    kind: shown,
    draft: draft,
    weekdays: days,
  );
}

TaskRuleValues mergeTaskRule(
  TaskRuleValues fresh,
  TaskRuleValues draft,
  TaskRuleValues stored,
) {
  final title = draft.title.trim() == stored.title.trim()
          ? fresh.title
          : draft.title,
      prompt = draft.prompt.trim() == stored.prompt.trim()
          ? fresh.prompt
          : draft.prompt;
  final timingEdited =
      _timingFields.any((f) => draft.draft[f] != stored.draft[f]) ||
      !_same(draft.weekdays, stored.weekdays);
  if (_storedKind(draft.kind) != _storedKind(stored.kind)) {
    return draft.copy(title: title, prompt: prompt);
  }
  if (_storedKind(fresh.kind) != _storedKind(stored.kind)) {
    return (timingEdited ? draft : fresh).copy(title: title, prompt: prompt);
  }
  final days = _same(draft.weekdays, stored.weekdays)
      ? fresh.weekdays
      : draft.weekdays;
  final chosen =
      draft.kind != stored.kind || !_same(draft.weekdays, stored.weekdays);
  return TaskRuleValues(
    title: title,
    prompt: prompt,
    kind: _storedKind(draft.kind) == 'weekly'
        ? (chosen
              ? draft.kind
              : _weekdays(days)
              ? 'weekdays'
              : 'weekly')
        : draft.kind == stored.kind
        ? fresh.kind
        : draft.kind,
    draft: {
      for (final field in _timingFields)
        field: draft.draft[field] == stored.draft[field]
            ? fresh.draft[field]!
            : draft.draft[field]!,
    },
    weekdays: days,
  );
}

String? taskDraftFailure(TaskRuleValues shown) {
  if (shown.title.trim().isEmpty || shown.title.trim().length > 120) {
    return 'rule.invalidTitle';
  }
  if (shown.prompt.trim().isEmpty) return 'rule.invalidPrompt';
  if (shown.kind == 'every') {
    final text = shown.draft['seconds']!;
    return RegExp(r'^\d+$').hasMatch(text) &&
            (double.tryParse(text) ?? double.nan) >= 60
        ? null
        : 'timing.invalidInterval';
  }
  if (shown.kind == 'cron') {
    return parseTaskCron(shown.draft['expression']!) == null
        ? 'rule.cronInvalid'
        : null;
  }
  final date = shown.draft['date']!;
  if (shown.kind == 'once') {
    final parsed = DateTime.tryParse('${date}T00:00:00.000Z');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date) {
      return 'timing.invalid';
    }
  }
  return RegExp(r'^\d{2}:\d{2}(:\d{2}(\.\d{1,3})?)?$')
          .hasMatch(shown.draft['time']!)
      ? null
      : 'timing.invalid';
}

Map<String, Object?> taskRuleChange(TaskRuleValues shown) {
  final d = shown.draft;
  return switch (shown.kind) {
    'once' => {
      'kind': 'at',
      'at': {
        'date': d['date'],
        'time': _seconds(d['time']!),
        'time_zone': d['timeZone']!.trim(),
      },
    },
    'every' => {'kind': 'every', 'every_seconds': num.parse(d['seconds']!)},
    'daily' => {
      'kind': 'daily',
      'daily': {
        'time': _seconds(d['time']!),
        'time_zone': d['timeZone']!.trim(),
      },
    },
    'cron' => {
      'kind': 'cron',
      'cron': {
        'expression': d['expression']!.trim(),
        'time_zone': d['timeZone']!.trim(),
      },
    },
    _ => {
      'kind': 'weekly',
      'weekly': {
        'time': _seconds(d['time']!),
        'time_zone': d['timeZone']!.trim(),
        'weekdays': shown.kind == 'weekdays' ? [1, 2, 3, 4, 5] : shown.weekdays,
      },
    },
  };
}

String taskTimingFailure(Object? code) => switch (code) {
  'schedule_conflict' => 'timing.conflict',
  'schedule_ended' => 'timing.inactive',
  'schedule_not_found' => 'timing.notFound',
  'subagent_session' => 'timing.subagentSession',
  'invalid_time_zone' => 'timing.invalidZone',
  'not_future' => 'timing.notFuture',
  'frequency_too_high' => 'timing.invalidInterval',
  'invalid_prompt' ||
  'invalid_selector' ||
  'invalid_rule' ||
  'time_out_of_range' => 'timing.invalid',
  _ => 'timing.error',
};

class TaskEditDraft {
  TaskEditDraft(this.entry, this.update, {this.deviceZone = 'UTC'}) {
    stored = shown = taskRuleValues(entry, deviceZone: deviceZone);
  }
  TaskEntry entry;
  final Future<ScheduleUpdateResult> Function(ScheduleUpdateRequest) update;
  final String deviceZone;
  late TaskRuleValues stored, shown;
  final changed = Observable(0);
  String? failure;
  bool saving = false, _disposed = false;
  int _submissions = 0;
  List<int>? _rememberedDays;
  bool get dirty => shown.key != stored.key;
  bool get writable => entry.status == 'active';
  void _notify() {
    if (!_disposed) changed.set(changed.value + 1);
  }

  void accept(TaskEntry fresh) {
    if (fresh.id != entry.id || fresh.sessionId != entry.sessionId) return;
    final next = taskRuleValues(fresh, deviceZone: deviceZone);
    entry = fresh;
    shown = fresh.status == 'inactive'
        ? next
        : mergeTaskRule(next, shown, stored);
    stored = next;
    _notify();
  }

  void edit({String? title, String? prompt, String? field, String? value}) {
    if (!writable || saving) return;
    shown = shown.copy(
      title: title,
      prompt: prompt,
      draft: field == null ? null : {...shown.draft, field: value ?? ''},
    );
    failure = null;
    _notify();
  }

  void cancel() {
    shown = stored;
    failure = null;
    _rememberedDays = null;
    _notify();
  }

  void chooseKind(String kind) {
    if (!writable || saving || shown.kind == kind) return;
    if (const ['weekly', 'weekdays'].contains(shown.kind)) {
      _rememberedDays = shown.weekdays;
    }
    final restore = kind == stored.kind;
    final clock = const ['daily', 'weekdays', 'weekly'];
    final carry =
        !restore && clock.contains(kind) && clock.contains(shown.kind);
    final seed = taskRuleValues(entry, deviceZone: deviceZone);
    final zone = (entry.raw['timeZone'] as String?) ?? deviceZone;
    final wall = zonedTaskClock(entry.scheduledAt, zone);
    final draft = {for (final f in _timingFields) f: ''};
    if (restore) {
      draft.addAll(stored.draft);
    } else {
      switch (kind) {
        case 'once':
          draft['date'] = wall.isEmpty ? '' : wall.substring(0, 10);
          draft['time'] = wall.isEmpty ? '' : wall.substring(11);
          draft['timeZone'] = zone;
        case 'every':
          draft['seconds'] = entry.kind == 'every'
              ? '${entry.raw['everySeconds']}'
              : '3600';
        case 'cron':
          draft['expression'] = entry.kind == 'cron'
              ? entry.raw['expression']! as String
              : '${int.tryParse(wall.length >= 16 ? wall.substring(14, 16) : '') ?? 0} ${int.tryParse(wall.length >= 13 ? wall.substring(11, 13) : '') ?? 0} * * *';
          draft['timeZone'] = zone;
        default:
          draft['time'] = carry
              ? shown.draft['time']!
              : (wall.isEmpty ? '00:00:00' : wall.substring(11));
          draft['timeZone'] = carry ? shown.draft['timeZone']! : zone;
      }
    }
    final days = kind == 'weekdays'
        ? <int>[1, 2, 3, 4, 5]
        : kind == 'weekly'
        ? (_rememberedDays ??
              (const ['weekly', 'weekdays'].contains(stored.kind)
                  ? stored.weekdays
                  : seed.weekdays))
        : seed.weekdays;
    shown = shown.copy(
      kind: kind,
      draft: draft,
      weekdays: kind == 'weekly' && _rememberedDays != null
          ? _rememberedDays!
          : restore
          ? stored.weekdays
          : days,
    );
    failure = null;
    _notify();
  }

  void toggleWeekday(int day) {
    if (!writable || saving) return;
    if (shown.weekdays.length == 1 && shown.weekdays.contains(day)) return;
    final days = shown.weekdays.toSet();
    if (!days.remove(day)) days.add(day);
    final next = days.toList()..sort();
    shown = shown.copy(weekdays: next);
    _rememberedDays = next;
    failure = null;
    _notify();
  }

  ScheduleUpdateRequest request() => ScheduleUpdateRequest(
    sessionId: entry.sessionId,
    id: entry.id,
    expected: entry.expected,
    title: shown.title.trim() == stored.title ? null : shown.title.trim(),
    prompt: shown.prompt.trim() == stored.prompt ? null : shown.prompt.trim(),
    change: shown.timingKey == stored.timingKey
        ? null
        : ScheduleTimingChange.fromJson(taskRuleChange(shown)),
  );
  Future<bool> save() async {
    if (_disposed || saving || !writable || !dirty) return false;
    failure = taskDraftFailure(shown);
    if (failure != null) {
      _notify();
      return false;
    }
    final submission = ++_submissions, prop = stored.key;
    saving = true;
    failure = null;
    _notify();
    try {
      final result = await update(request());
      if (_disposed || submission != _submissions) return false;
      if (result.code != null) {
        failure = taskTimingFailure(result.code);
        return false;
      }
      if (result.record == null) {
        failure = 'rule.error.unknown';
        return false;
      }
      if (stored.key == prop) {
        final saved = TaskEntry(
          ScheduleCatalogEntry.fromJson({
            ...result.record!.toJson(),
            'sessionId': entry.sessionId,
            'status': entry.status,
          }),
        );
        entry = saved;
        stored = shown = taskRuleValues(saved, deviceZone: deviceZone);
      } else {
        shown = stored;
      }
      _rememberedDays = null;
      return true;
    } on Object {
      if (!_disposed && submission == _submissions) {
        failure = 'rule.error.unknown';
      }
      return false;
    } finally {
      if (!_disposed && submission == _submissions) {
        saving = false;
        _notify();
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _submissions++;
    await changed.dispose();
  }
}

/// Structured cron editing preserves Vixie day-field semantics. A full numeric
/// day set stays selected, while a literal star is unrestricted.
Map<String, Object?>? taskCronShape(Map<String, Object?> parsed) {
  Map<Object?, Object?> field(String key) => parsed[key] as Map;
  List<int> values(String key) => (field(key)['values'] as List).cast<int>();
  int? step(List<int> v, int max) {
    if (v.length < 2 || v.first != 0) return null;
    final n = v[1];
    if (n < 1 || v.length != (max ~/ n) + 1) return null;
    for (var i = 0; i < v.length; i++) {
      if (v[i] != i * n) return null;
    }
    return n;
  }

  if (field('months')['full'] != true) return null;
  final minutes = values('minutes'), hours = values('hours');
  final minuteStep = field('minutes')['unrestricted'] == true
      ? 1
      : step(minutes, 59);
  final hourStep = field('hours')['unrestricted'] == true ? 1 : step(hours, 23);
  final minute = minutes.length == 1 ? minutes.first : null;
  final hour = hours.length == 1 ? hours.first : null;
  if (field('daysOfWeek')['unrestricted'] == true) {
    if (field('daysOfMonth')['unrestricted'] == true) {
      if (minuteStep != null && field('hours')['full'] == true) {
        return {'kind': 'minutely', 'step': minuteStep};
      }
      if (minute != null && hourStep != null) {
        return {'kind': 'hourly', 'step': hourStep, 'minute': minute};
      }
      if (minute != null && hour != null) {
        return {'kind': 'daily', 'hour': hour, 'minute': minute};
      }
      return null;
    }
    if (minute == null || hour == null) return null;
    return {
      'kind': 'monthly',
      'days': values('daysOfMonth'),
      'hour': hour,
      'minute': minute,
    };
  }
  if (field('daysOfMonth')['unrestricted'] != true ||
      minute == null ||
      hour == null) {
    return null;
  }
  final days = values('daysOfWeek').map((d) => d == 0 ? 7 : d).toList()..sort();
  return {'kind': 'weekly', 'weekdays': days, 'hour': hour, 'minute': minute};
}

String taskCronExpression(Map<String, Object?> state) {
  String runs(Iterable<int> input) {
    final values = input.toSet().toList()..sort(), parts = <String>[];
    for (var i = 0; i < values.length;) {
      var end = i;
      while (end + 1 < values.length && values[end + 1] == values[end] + 1) {
        end++;
      }
      parts.add(
        end - i >= 2
            ? '${values[i]}-${values[end]}'
            : values.sublist(i, end + 1).join(','),
      );
      i = end + 1;
    }
    return parts.join(',');
  }

  return switch (state['kind']) {
    'minutely' =>
      state['step'] == 1 ? '* * * * *' : '*/${state['step']} * * * *',
    'hourly' =>
      state['step'] == 1
          ? '${state['minute']} * * * *'
          : '${state['minute']} */${state['step']} * * *',
    'daily' => '${state['minute']} ${state['hour']} * * *',
    'weekly' =>
      '${state['minute']} ${state['hour']} * * ${runs((state['weekdays'] as List).cast<int>().map((d) => d % 7))}',
    'monthly' =>
      '${state['minute']} ${state['hour']} ${runs((state['days'] as List).cast<int>())} * *',
    _ => throw ArgumentError('Unknown cron builder kind'),
  };
}
