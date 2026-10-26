import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_job.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

Map<String, Object?> job({
  String id = 'j',
  String status = 'running',
  num earliest = 0,
}) => {
  'id': id,
  'kind': 'shell',
  'label': 'synthetic command',
  'status': status,
  'startedAt': 1000,
  'output': {'earliest': earliest, 'total': 10},
};
Map<String, Object?> anchor({num from = 0, num earliest = 0}) => {
  'type': 'opened',
  'job': job(earliest: earliest),
  'from': from,
};
Map<String, Object?> output(String text, num next, {bool gap = false}) => {
  'type': 'output',
  'chunks': [
    {'at': 0, 'text': text, 'gapBefore': gap},
  ],
  'next': next,
};
Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  test('UTF16 bounded rendering never splits surrogate and keeps absolute byte cursor', () async {
    final m = JobsModel();
    m.opened(
      'j',
      JobFollowFrameOpened.fromJson(anchor(from: 10, earliest: 12)),
    );
    expect(m.observed['j']!.gapBefore, true);
    final text = 'x😀${'a' * (128 * 1024 - 1)}';
    m.output('j', JobFollowFrameOutput.fromJson(output(text, 999999)));
    final view = m.observed['j']!;
    expect(view.text, 'a' * (128 * 1024 - 1));
    expect(view.cursor, 999999);
    expect(view.gapBefore, true);
    m.settled('j');
    expect(m.observed['j']!.streaming, false);
    m.failed('missing', StateError('gone'));
    expect(m.observed['missing']!.error, contains('gone'));
    m.stopped('j');
    expect(m.observed.containsKey('j'), false);
    await m.dispose();
  });
  test('reference-counted streams resume byte cursor and close after terminal status', () async {
    final host = FakeHost();
    final roster = StreamController<GenerationFrame>.broadcast(sync: true);
    final follow = StreamController<GenerationFrame>.broadcast(sync: true);
    var rosterOpens = 0, followOpens = 0;
    JobFollowRequest Function()? request;
    final service = JobsService(
      JobsHost(
        remote: JobRemote(host),
        list: (_) {
          rosterOpens++;
          return roster.stream;
        },
        follow: (r) {
          followOpens++;
          request = r;
          return follow.stream;
        },
      ),
    );
    final a = service.watchRows('s'), b = service.watchRows('s');
    expect(rosterOpens, 1);
    roster.add(const StreamOpened(1));
    roster.add(
      StreamItem(1, {
        'type': 'rows',
        'jobs': [job()],
      }),
    );
    expect(service.model.rows['s'], hasLength(1));
    a();
    await tick();
    expect(service.model.rows['s'], hasLength(1));
    final one = service.observe('s', 'j'), two = service.observe('s', 'j');
    expect(followOpens, 1);
    expect(request!().from, isNull);
    follow.add(const StreamOpened(1));
    follow.add(StreamItem(1, anchor()));
    follow.add(StreamItem(1, output('hello', 5)));
    follow.add(StreamEnded(1, CarrierLost('reconnecting')));
    follow.add(const StreamOpened(2));
    expect(request!().from, 5);
    follow.add(StreamItem(2, anchor(from: 5)));
    follow.add(StreamItem(1, output('stale', 9)));
    follow.add(StreamItem(2, output(' world', 11)));
    expect(service.model.observed['j']!.text, 'hello world');
    follow.add(
      StreamItem(2, {'type': 'status', 'job': job(status: 'completed')}),
    );
    await tick();
    expect(service.model.observed['j']!.streaming, false);
    one();
    two();
    b();
    await tick();
    expect(service.model.observed, isEmpty);
    expect(service.model.rows, isEmpty);
    await service.dispose();
    await roster.close();
    await follow.close();
    await host.close();
  });
  test('late release cannot clear a successor roster and terminal failures remove stale state', () async {
    final host = FakeHost();
    final wait = Completer<void>();
    final first = StreamController<GenerationFrame>(
      sync: true,
      onCancel: () => wait.future,
    );
    final second = StreamController<GenerationFrame>(sync: true);
    var opens = 0;
    final service = JobsService(
      JobsHost(
        remote: JobRemote(host),
        list: (_) => ++opens == 1 ? first.stream : second.stream,
        follow: (_) => const Stream.empty(),
      ),
    );
    final old = service.watchRows('s');
    first.add(const StreamOpened(1));
    first.add(
      StreamItem(1, {
        'type': 'rows',
        'jobs': [job(id: 'old')],
      }),
    );
    old();
    final fresh = service.watchRows('s');
    second.add(const StreamOpened(2));
    second.add(
      StreamItem(2, {
        'type': 'rows',
        'jobs': [job(id: 'new')],
      }),
    );
    wait.complete();
    await tick();
    expect(service.model.rows['s']!.single.id, 'new');
    second.add(StreamEnded(2, RemoteException('job/not-found', 'removed')));
    await tick();
    expect(service.model.rows, isEmpty);
    fresh();
    await service.dispose();
    unawaited(first.close());
    unawaited(second.close());
    await host.close();
  });
}
