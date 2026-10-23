import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';

import '../../dsh_models.dart';
import 'fake_transport.dart';

/// Replays a `dsh-session-vector/1` fixture through the Dart [Session] and
/// returns one snapshot per snapshot-worthy step, in the exact shape the TS
/// runner (tool/vectors/ts) writes into `expected`:
/// `{step, openState, hasMore, entries: [["event", seq, type] | ["live", seq, chunkType, text]]}`.
///
/// Step semantics (the contract with the TS side):
///  * `action open`  construct the Session for `session-1` and call open;
///  * `opened` / `frame` / `ended`  push the recorded follow stream items;
///  * `page`  not an event in time: pre-registered answers, matched on
///    `(throughSeq, beforeSeq)` (the host answer is recorded);
///  * `action loadOlder`  awaited completely;
///  * `action prompt`  informational.
class ReplayTransport extends FakeTransport {
  ReplayTransport(List<Map<String, Object?>> pages) {
    for (final p in pages) {
      this.pages.add(p);
    }
    onPage = (req) async {
      final through = req['throughSeq'];
      final before = req['beforeSeq'];
      for (final p in this.pages) {
        final r = p['request']! as Map<String, Object?>;
        if (r['throughSeq'] == through && r['beforeSeq'] == before) {
          return Map<String, Object?>.from(p['response']! as Map);
        }
      }
      throw StateError(
        'no recorded page answer for throughSeq=$through beforeSeq=$before',
      );
    };
  }

  final List<Map<String, Object?>> pages = [];
}

Future<void> settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<Object?> encodeEntries(EventWindow window) => [
  for (final e in window.entries)
    if (e.transient)
      [
        'live',
        e.seq,
        ((e.data as Map)['chunk'] as Map)['type'],
        ((e.data as Map)['chunk'] as Map)['text'] is String
            ? ((e.data as Map)['chunk'] as Map)['text']
            : '',
      ]
    else
      ['event', e.seq, e.type],
];

/// [attach] runs once with the freshly built Session (before `open`), so a
/// consumer such as the conversation binding can subscribe to its event
/// source; [project] adds extra fields to every snapshot map.
Future<List<Map<String, Object?>>> replayFixture(
  Map<String, Object?> fixture, {
  void Function(Session session)? attach,
  Map<String, Object?> Function()? project,
}) async {
  final steps = (fixture['steps']! as List).cast<Map<String, Object?>>();
  final transport = ReplayTransport([
    for (final s in steps)
      if (s['op'] == 'page') s,
  ]);
  final session = Session(
    'session-1',
    transport,
    pageOptions: Map<String, Object?>.from(fixture['openOptions']! as Map),
  );
  attach?.call(session);
  final out = <Map<String, Object?>>[];
  for (var i = 0; i < steps.length; i++) {
    final s = steps[i];
    var snapshot = true;
    switch (s['op']) {
      case 'action':
        switch (s['name']) {
          case 'open':
            unawaited(session.open().catchError((Object _) {}));
            snapshot = false;
          case 'loadOlder':
            await session.loadOlder();
          default:
            snapshot = false;
        }
      case 'opened':
        transport.currentFollow.add(StreamOpened(s['generation']! as int));
      case 'frame':
        transport.currentFollow.add(
          StreamItem(s['generation']! as int, s['frame']),
        );
      case 'ended':
        transport.currentFollow.add(
          StreamEnded(
            s['generation']! as int,
            s['error'] == null ? null : CarrierLost(),
          ),
        );
      default:
        snapshot = false;
    }
    await settle();
    if (snapshot) {
      out.add({
        'step': i,
        'openState': session.snapshot.value.openState.name,
        'hasMore': session.eventSource.window.hasMore,
        'entries': encodeEntries(session.eventSource.window),
        ...?project?.call(),
      });
    }
  }
  await session.dispose();
  return out;
}

/// JSON round trip so numbers and lists compare structurally.
Object? canonical(Object? v) => jsonDecode(jsonEncode(v));
