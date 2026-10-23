// The generated codecs (tool/codegen) must accept real wire data: every frame
// of the scrubbed real-session fixture goes through the generated follow-frame
// decoder, and every durable event through the generated event decoder.
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/generated.dart';
import 'package:dsh_models/generated.dart' as ev;
import 'package:test/test.dart';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/session_window_vector.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final steps = (fixture['steps']! as List).cast<Map<String, Object?>>();
  final frames = [
    for (final s in steps)
      if (s['op'] == 'frame') s['frame'],
  ];

  test('every recorded follow frame decodes with the generated descriptor', () {
    var snapshots = 0, events = 0, assistant = 0;
    for (final f in frames) {
      final decoded = SessionStreams.follow.decodeFrame(f);
      switch (decoded) {
        case SessionFollowFrameSnapshot():
          snapshots++;
        case SessionEventEntry():
          events++;
        case SessionFollowFrameAssistantStream():
          assistant++;
        default:
          fail('unrecognized frame: ${(f! as Map)['type']}');
      }
    }
    expect([snapshots, events > 0, assistant > 0], [1, true, true]);
  });

  test('every durable event (live and in history pages) decodes and is not unknown', () {
    final wire = <Map<String, Object?>>[];
    for (final s in steps) {
      if (s['op'] == 'frame') {
        final f = s['frame']! as Map<String, Object?>;
        if (f['type'] == 'event') wire.add(f['event']! as Map<String, Object?>);
        if (f['type'] == 'snapshot') {
          for (final r in f['records']! as List) {
            wire.add((r as Map)['event']! as Map<String, Object?>);
          }
        }
      } else if (s['op'] == 'page') {
        final records = ((s['response']! as Map)['records']! as List);
        for (final r in records) {
          wire.add((r as Map)['event']! as Map<String, Object?>);
        }
      }
    }
    expect(wire.length, greaterThan(40));
    final unknown = <String>{};
    for (final e in wire) {
      final decoded = ev.SessionEvent.fromJson(e);
      if (decoded is ev.UnknownSessionEvent) unknown.add('${e['type']}');
      expect(decoded.seq, e['seq']);
    }
    expect(unknown, isEmpty, reason: 'event types the schema does not know');
  });
}
