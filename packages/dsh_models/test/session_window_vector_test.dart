// Behaviour vector: a scrubbed trace of one real dsh session (follow snapshot,
// live events, assistant-stream frames, loadOlder pages) was replayed through
// dsh's own TypeScript client model (tool/vectors/ts, real `Session`,
// `RemoteJournalStream`, `ClientAssistantStream`) to produce `expected`.
// The Dart models must produce the same window after every step.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/replay.dart';

void main() {
  final file = File('test/fixtures/session_window_vector.json');
  late Map<String, Object?> fixture;

  setUpAll(() {
    fixture = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  });

  test('fixture is a dsh-session-vector/1 with TS-produced expectations', () {
    expect(fixture['format'], 'dsh-session-vector/1');
    expect(fixture['expected'], isA<List<Object?>>());
    expect((fixture['expected']! as List).length, greaterThan(10));
    final by = fixture['expectedBy']! as Map<String, Object?>;
    expect(by['model'], contains('TypeScript'));
    expect(by['dshCommit'], matches(RegExp(r'^[0-9a-f]{40}$')));
    final ops = (fixture['steps']! as List)
        .map((s) => (s as Map)['op'])
        .toSet();
    expect(ops, containsAll(['opened', 'frame', 'page', 'action']));
    final frames = {
      for (final s in fixture['steps']! as List)
        if ((s as Map)['op'] == 'frame') (s['frame']! as Map)['type'],
    };
    expect(frames, containsAll(['snapshot', 'event', 'assistant-stream']));
  });

  test(
    'Dart Session produces the same window as the TS model after every step',
    () async {
      final actual = await replayFixture(fixture);
      final expected = (fixture['expected']! as List)
          .cast<Map<String, Object?>>();
      expect(
        actual.length,
        expected.length,
        reason: 'one snapshot per snapshot-worthy step',
      );
      for (var i = 0; i < expected.length; i++) {
        final a = canonical(actual[i]) as Map<String, Object?>;
        final e = expected[i];
        expect(
          a['step'],
          e['step'],
          reason: 'snapshot $i is for the same step',
        );
        expect(
          a['openState'],
          e['openState'],
          reason: 'openState at step ${e['step']}',
        );
        expect(
          a['hasMore'],
          e['hasMore'],
          reason: 'hasMore at step ${e['step']}',
        );
        expect(
          a['entries'],
          e['entries'],
          reason: 'window entries at step ${e['step']}',
        );
      }
    },
  );

  test('the fixture carries no private content', () {
    final text = file.readAsStringSync();
    for (final needle in [
      RegExp(r'/home/'),
      RegExp(r'/mnt/'),
      RegExp(r'[?&]token='),
      RegExp('cookie', caseSensitive: false),
      RegExp(r'sk-[A-Za-z0-9]{8}'),
      RegExp(r'https?://'),
      RegExp(r'[A-Za-z0-9._-]+@[A-Za-z0-9-]+\.[a-z]{2,}'),
    ]) {
      expect(
        needle.hasMatch(text),
        isFalse,
        reason: '$needle must not appear in a committed fixture',
      );
    }
    // every string value is either structure (enum-like) or a scrubbed `s<len>` / pseudonym
    final words = RegExp(r'^(s\d+|[a-z]+-\d+|[A-Za-z0-9/._-]{1,40})$');
    void walk(Object? v, String key) {
      if (v is Map) {
        v.forEach((k, x) => walk(x, '$k'));
      } else if (v is List) {
        for (final x in v) {
          walk(x, key);
        }
      } else if (v is String) {
        expect(
          words.hasMatch(v),
          isTrue,
          reason: 'unexpected free text under "$key"',
        );
      }
    }

    walk(fixture['steps'], 'steps');
  });
}
