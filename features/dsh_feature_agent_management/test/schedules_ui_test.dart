import 'package:dsh_client/generated_schedule.dart';
import 'package:dsh_feature_agent_management/dsh_feature_agent_management.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> task(
  String id, {
  String session = 'original',
  String status = 'active',
}) => {
  'id': id,
  'sessionId': session,
  'title': 'Synthetic $id',
  'prompt': 'Task instruction $id',
  'kind': 'daily',
  'scheduledAt': '2026-10-27T00:00:00.000Z',
  'time': '09:00:00.123',
  'timeZone': 'Asia/Tokyo',
  'status': status,
};
void main() {
  testWidgets(
    'catalog search and details bind updates/history/delete to original task and session',
    (t) async {
      t.view.physicalSize = const Size(1200, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      const i18n = DshI18n(DshLocale.en);
      final host = FakeHost();
      var rows = [task('a'), task('b', session: 'second', status: 'inactive')];
      host.handlers['schedule/catalog'] = (_) => rows;
      host.handlers['schedule/history'] = (_) => {
        'id': 'a',
        'records': [
          {
            'messageId': 'm',
            'scheduledAt': '2026-10-26T00:00:00.000Z',
            'deliveredAt': '2026-10-26T00:00:01.000Z',
            'prompt': 'Saved synthetic prompt',
          },
        ],
        'earlierRecordsUnavailable': false,
        'earlierRecordsPruned': true,
        'retention': {'days': 30, 'records': 100},
      };
      host.handlers['schedule/update'] = (args) {
        final req = args['request'] as Map;
        final fresh = {...task('a'), 'title': req['title']};
        rows = [fresh, rows[1]];
        return {
          'id': 'a',
          'updated': true,
          'record': {...fresh}
            ..remove('sessionId')
            ..remove('status'),
        };
      };
      host.handlers['schedule/delete'] = (_) {
        rows = rows.where((r) => r['id'] != 'a').toList();
        return {'id': 'a', 'deleted': true};
      };
      final service = ScheduleService(host.remotes);
      final opened = <String>[];
      await t.pumpWidget(
        dshTestApp(
          TaskManagerPage(
            service: service,
            i18n: i18n,
            onNew: () {},
            onOpenSession: opened.add,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Synthetic a'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('task-search')), 'second');
      await t.pumpAndSettle();
      expect(find.text('Synthetic a'), findsNothing);
      expect(find.text('Synthetic b'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('task-search')), '');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('task-row-a')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('task-edit-title')),
        'Edited synthetic',
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('task-save')));
      await t.tap(find.byKey(const ValueKey('task-save')));
      await t.pumpAndSettle();
      final request =
          host.callsTo('schedule/update').single.args['request'] as Map;
      expect(request['sessionId'], 'original');
      expect(request['id'], 'a');
      expect(request.containsKey('change'), false);
      expect((request['expected'] as Map)['time'], '09:00:00.123');
      await t.tap(find.text(i18n.t('schedule.manager', 'detail.records')));
      await t.pumpAndSettle();
      expect(find.text('Saved synthetic prompt'), findsOneWidget);
      expect(
        (host.callsTo('schedule/history').single.args['request']
            as Map)['sessionId'],
        'original',
      );
      await t.tap(find.text(i18n.t('schedule.manager', 'delivery.retention')));
      await t.pumpAndSettle();
      expect(find.textContaining('100 delivery records'), findsOneWidget);
      await t.tap(find.text(i18n.t('schedule.manager', 'detail.rule')));
      await t.pumpAndSettle();
      await t.ensureVisible(
        find.text(i18n.t('schedule.manager', 'detail.session')),
      );
      await t.tap(find.text(i18n.t('schedule.manager', 'detail.session')));
      expect(opened, ['original']);
      await t.ensureVisible(
        find.text(i18n.t('schedule.manager', 'delete.action')),
      );
      await t.tap(find.text(i18n.t('schedule.manager', 'delete.action')));
      await t.pumpAndSettle();
      expect(host.callsTo('schedule/delete'), isEmpty);
      await t.tap(find.byKey(const ValueKey('task-delete-confirm')));
      await t.pumpAndSettle();
      expect((host.callsTo('schedule/delete').single.args['request'] as Map), {
        'sessionId': 'original',
        'id': 'a',
      });
      expect(find.byKey(const ValueKey('task-edit-title')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await t.runAsync(() async {
        await service.dispose();
        await host.close();
      });
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'changing sidebar selection discards previous task editor on phone',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final host = FakeHost();
      final service = ScheduleService(host.remotes);
      TaskEntry row(String id) =>
          TaskEntry(ScheduleCatalogEntry.fromJson(task(id)));
      Widget page(String id) => dshTestApp(
        TaskDetail(
          key: ValueKey(id),
          service: service,
          entry: row(id),
          i18n: const DshI18n(DshLocale.en),
          onOpenSession: (_) {},
        ),
      );
      await t.pumpWidget(page('a'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('task-edit-title')),
        'Unsent old draft',
      );
      await t.pumpWidget(page('b'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('task-edit-title')))
            .controller!
            .text,
        'Synthetic b',
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await t.runAsync(() async {
        await service.dispose();
        await host.close();
      });
      expect(t.takeException(), isNull);
    },
  );
}
