import 'dart:async';

import 'package:dsh_client/generated_schedule.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

Map<String, Object?> task({
  String title = 'Original',
  String prompt = 'Instruction',
  String status = 'active',
  List<int> days = const [1, 2, 3, 4, 5],
}) => {
  'id': 'task',
  'sessionId': 's',
  'kind': 'weekly',
  'title': title,
  'prompt': prompt,
  'scheduledAt': '2026-10-26T00:12:34.567Z',
  'time': '09:12:34.567',
  'timeZone': 'Asia/Tokyo',
  'weekdays': days,
  'status': status,
};
TaskEntry entry(Map<String, Object?> row) =>
    TaskEntry(ScheduleCatalogEntry.fromJson(row));
Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  test('catalog batches same-commit reads but post-delete refresh supersedes pre-write state', () async {
    final changed = StreamController<void>.broadcast(sync: true),
        resets = StreamController<void>.broadcast(sync: true);
    final first = Completer<List<String>>();
    var reads = 0;
    final deleted = <String>[];
    final catalog = TaskCatalog<String>(
      list: () => ++reads == 1 ? first.future : Future.value(['fresh']),
      remove: (id) async {
        deleted.add(id);
      },
      changes: changed.stream,
      resets: resets.stream,
    );
    final unwatch = catalog.watch(() {});
    final joined = catalog.refresh();
    expect(reads, 1);
    final removed = catalog.delete('x');
    await removed;
    expect(reads, 2);
    expect(catalog.snapshot.records, ['fresh']);
    expect(deleted, ['x']);
    expect(catalog.snapshot.readSettled, 3);
    first.complete(['old']);
    await joined;
    expect(catalog.snapshot.records, ['fresh']);
    unwatch();
    await catalog.dispose();
    await changed.close();
    await resets.close();
  });
  test('a last watcher leaving excludes late rows and pending delete cannot remove a successor owner state', () async {
    final changes = StreamController<void>.broadcast(sync: true);
    final old = Completer<List<String>>();
    final deletion = Completer<void>();
    var reads = 0;
    final catalog = TaskCatalog<String>(
      list: () => ++reads == 1 ? old.future : Future.value(['new']),
      remove: (_) => deletion.future,
      changes: changes.stream,
      resets: changes.stream,
    );
    final off = catalog.watch(() {});
    final pending = catalog.delete('x');
    off();
    final next = catalog.watch(() {});
    await tick();
    old.complete(['old']);
    await tick();
    expect(catalog.snapshot.records, ['new']);
    deletion.complete();
    expect(await pending, 'deleted');
    expect(catalog.snapshot.records, ['new']);
    expect(catalog.snapshot.deleting, isEmpty);
    next();
    await catalog.dispose();
    await changes.close();
  });
  test('draft preserves edited content while adopting remote timing, then submits minimal content-only request', () async {
    final requests = <ScheduleUpdateRequest>[];
    final draft = TaskEditDraft(entry(task()), (request) async {
      requests.add(request);
      return ScheduleUpdateResult(
        record: request.expected,
        id: 'task',
        updated: true,
      );
    });
    draft.edit(prompt: 'Local instruction');
    draft.accept(entry({...task(title: 'Renamed'), 'time': '10:00:00'}));
    expect(draft.shown.title, 'Renamed');
    expect(draft.shown.prompt, 'Local instruction');
    expect(draft.shown.draft['time'], '10:00:00');
    final request = draft.request();
    expect(request.title, isNull);
    expect(request.prompt, 'Local instruction');
    expect(request.change, isNull);
    expect(request.expected.toJson()['time'], '10:00:00');
    expect(request.expected.toJson().containsKey('status'), false);
    draft.toggleWeekday(5);
    draft.chooseKind('daily');
    draft.chooseKind('weekly');
    expect(draft.shown.weekdays, [1, 2, 3, 4]);
    draft.accept(entry(task(status: 'inactive')));
    expect(draft.dirty, false);
    expect(await draft.save(), false);
    expect(requests, isEmpty);
    await draft.dispose();
  });
  test('timing parser retains milliseconds, changes zones through Host inputs and rejects empty weekday removal', () async {
    final draft = TaskEditDraft(
      entry(task()),
      (_) async => const ScheduleUpdateResult(),
    );
    expect(
      zonedTaskClock('2026-10-26T00:12:34.567Z', 'Asia/Tokyo'),
      '2026-10-26T09:12:34.567',
    );
    expect(zonedTaskClock('2026-10-26T00:12:34.567Z', 'invalid-zone'), '');
    draft.chooseKind('once');
    expect(taskRuleChange(draft.shown), {
      'kind': 'at',
      'at': {
        'date': '2026-10-26',
        'time': '09:12:34.567',
        'time_zone': 'Asia/Tokyo',
      },
    });
    draft.chooseKind('cron');
    expect(draft.shown.draft['expression'], '12 9 * * *');
    draft.chooseKind('weekly');
    for (final day in [2, 3, 4, 5]) {
      draft.toggleWeekday(day);
    }
    draft.toggleWeekday(1);
    expect(draft.shown.weekdays, [1]);
    draft.chooseKind('every');
    draft.edit(field: 'seconds', value: '59');
    expect(taskDraftFailure(draft.shown), 'timing.invalidInterval');
    draft.edit(field: 'seconds', value: '60');
    expect(taskDraftFailure(draft.shown), isNull);
    await draft.dispose();
  });
  test('history deduplicates pages and a fresh latest page supersedes a pending older page', () async {
    final host = FakeHost();
    Map<String, Object?> page(String id, {String? next}) => {
      'id': 'task',
      'records': [
        {
          'messageId': id,
          'scheduledAt': '2026-10-26T00:00:00.000Z',
          'deliveredAt': '2026-10-26T00:00:01.000Z',
          'prompt': 'Saved instruction',
        },
      ],
      'earlierRecordsUnavailable': true,
      'earlierRecordsPruned': false,
      'retention': {'days': 30, 'records': 100},
      if (next != null) 'nextBefore': next,
    };
    host.handlers['schedule/history'] = (_) => page('m2', next: 'm2');
    final model = TaskDeliveryModel(host.remotes, 's', 'task');
    await model.load();
    final slow = Completer<Object?>();
    host.handlers['schedule/history'] = (_) => slow.future;
    final old = model.load(before: 'm2');
    host.handlers['schedule/history'] = (_) => page('m3', next: 'm3');
    await model.load(refresh: true);
    slow.complete(page('m1'));
    await old;
    expect(model.records.map((r) => r.messageId), ['m3']);
    host.handlers['schedule/history'] = (_) => page('m3');
    await model.load(before: 'm3');
    expect(model.records, hasLength(1));
    expect(host.callsTo('schedule/history').last.args['request'], {
      'sessionId': 's',
      'id': 'task',
      'limit': 20,
      'before': 'm3',
    });
    await model.dispose();
    await host.close();
  });
}
