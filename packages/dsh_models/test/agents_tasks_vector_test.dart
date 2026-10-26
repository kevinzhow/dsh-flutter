import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/generated_schedule.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

void main() {
  final f = jsonDecode(
    File('test/fixtures/agents_tasks.json').readAsStringSync(),
  ) as Map;
  final expected = f['expected'] as Map;
  TaskEntry entry(Object? raw) => TaskEntry(
    ScheduleCatalogEntry.fromJson({
      ...Map<String, Object?>.from(raw as Map),
      'sessionId': 'synthetic-session',
      'status': 'active',
    }),
  );
  TaskRuleValues values(Object? raw) {
    final v = raw as Map;
    return TaskRuleValues(
      title: v['title'] as String,
      prompt: v['prompt'] as String,
      kind: v['kind'] as String,
      draft: Map<String, String>.from(v['draft'] as Map),
      weekdays: (v['weekdays'] as List).cast<int>(),
    );
  }

  test('17 cron dialect cases match pinned production parser including Vixie star flags', () {
    expect([
      for (final v in f['crons'] as List) parseTaskCron(v as String),
    ], expected['crons']);
  });
  test('structured cron builder recognizes and serializes actual production shapes', () {
    final shapes = [
      for (final v in f['crons'] as List)
        if (parseTaskCron(v as String) case final parsed?)
          taskCronShape(parsed)
        else
          null,
    ];
    expect(shapes, expected['shapes']);
    expect([
      for (final shape in shapes)
        shape == null ? null : taskCronExpression(shape),
    ], expected['expressions']);
  });
  test('six exact persisted snapshots and precision-preserving drafts match production timing', () {
    final entries = [for (final r in f['records'] as List) entry(r)];
    expect(entries.map((e) => e.expectedJson).toList(), expected['snapshots']);
    expect(
      entries.map((e) => taskRuleValues(e).draft).toList(),
      expected['drafts'],
    );
  });
  test(
    'twelve zoned clocks and eleven Host business failures match production',
    () {
      expect([
        for (final v in f['clocks'] as List)
          zonedTaskClock(v['instant'] as String, v['zone'] as String),
      ], expected['clocks']);
      expect([
        for (final v in f['failures'] as List) taskTimingFailure(v),
      ], expected['failures']);
    },
  );
  test(
    'eight concurrent text/kind/weekday merges match actual TaskDetail export',
    () {
      expect([
        for (final v in f['merges'] as List)
          mergeTaskRule(
            values(v['fresh']),
            values(v['draft']),
            values(v['stored']),
          ).toJson(),
      ], expected['merges']);
    },
  );
}
