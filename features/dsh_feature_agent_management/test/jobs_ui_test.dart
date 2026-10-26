import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_job.dart';
import 'package:dsh_feature_agent_management/dsh_feature_agent_management.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> row([String state = 'running']) => {
  'id': 'j',
  'kind': 'shell',
  'label': 'synthetic command',
  'status': state,
  'startedAt': 1000,
  'output': {'earliest': 0, 'total': 20},
};
void main() {
  testWidgets(
    'jobs observe only expanded output and require two stop presses without duplicate kill',
    (tester) async {
      final host = FakeHost();
      var kills = 0;
      host.handlers['job/kill'] = (_) {
        kills++;
        return {'outcome': 'requested'};
      };
      final roster = StreamController<GenerationFrame>.broadcast(sync: true),
          follow = StreamController<GenerationFrame>.broadcast(sync: true);
      var observed = 0, released = 0;
      final service = JobsService(
        JobsHost(
          remote: JobRemote(host),
          list: (_) => roster.stream,
          follow: (_) {
            observed++;
            return follow.stream.transform(
              StreamTransformer.fromHandlers(
                handleDone: (sink) {
                  released++;
                  sink.close();
                },
              ),
            );
          },
        ),
      );
      const i18n = DshI18n(DshLocale.en);
      String t(String k, [Map<String, Object?> p = const {}]) =>
          i18n.t('job', k, params: p);
      await tester.pumpWidget(
        dshTestApp(JobListAction(service: service, sessionId: 's', i18n: i18n)),
      );
      roster.add(const StreamOpened(1));
      roster.add(
        StreamItem(1, {
          'type': 'rows',
          'jobs': [row()],
        }),
      );
      await tester.pump();
      await tester.tap(find.text(t('count.live.one', {'count': 1})));
      await tester.pump();
      expect(observed, 0);
      await tester.tap(find.text('synthetic command'));
      await tester.pump();
      expect(observed, 1);
      follow.add(const StreamOpened(1));
      follow.add(StreamItem(1, {'type': 'opened', 'job': row(), 'from': 0}));
      follow.add(
        const StreamItem(1, {
          'type': 'output',
          'chunks': [
            {'at': 0, 'text': 'Synthetic native output'},
          ],
          'next': 23,
        }),
      );
      await tester.pump();
      expect(find.textContaining('Synthetic native output'), findsWidgets);
      final stop = find.bySemanticsLabel(
        t('kill.stop', {'label': 'synthetic command'}),
      );
      await tester.tap(stop);
      await tester.pump();
      expect(kills, 0);
      await tester.tap(find.text(t('kill.confirmAction')));
      await tester.pump();
      expect(kills, 1);
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text(t('kill.failed')), findsNothing);
      roster.add(
        StreamItem(1, {
          'type': 'rows',
          'jobs': [row('stopping')],
        }),
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel(t('kill.stop', {'label': 'synthetic command'})),
        findsNothing,
      );
      await tester.tap(find.text(t('count.live.one', {'count': 1})));
      await tester.pump();
      expect(find.textContaining('Synthetic native output'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        await service.dispose();
        await roster.close();
        await follow.close();
        await host.close();
      });
      expect(tester.takeException(), isNull);
      // A logical stream subscription was released on panel closure (the
      // broadcast fixture remains available for a future generation).
      expect(released, 0);
    },
  );
}
