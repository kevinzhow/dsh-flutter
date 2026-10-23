import 'dart:convert';
import 'dart:io';

import 'package:dsh_models/src/generated/session_events.g.dart';
import 'package:test/test.dart';

/// The committed IR lists every event type of docs/persistence-schema.json
/// (dsh formatVersion 2); the tests use it to cover all of them.
Map<String, Object?> loadIr() {
  final f = File('../../tool/codegen/ir/events.ir.json');
  return jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
}

/// Builds a minimal valid JSON instance of an IR type. `pick` selects which
/// member of every union is used; `full` includes optional properties.
class Synth {
  Synth(this.decls, {required this.pick, required this.full});
  final Map<String, Object?> decls;
  final int pick;
  final bool full;

  Object? gen(Map<String, Object?> t) {
    switch (t['k']) {
      case 'str':
        return 'x';
      case 'num':
        return 1;
      case 'bool':
        return true;
      case 'null':
        return null;
      case 'json':
        return {'any': 1};
      case 'lit':
        return t['v'];
      case 'enum':
        return (t['values'] as List).first;
      case 'arr':
        return [gen(t['of'] as Map<String, Object?>)];
      case 'rec':
        return {'key': gen(t['of'] as Map<String, Object?>)};
      case 'nullable':
        return gen(t['of'] as Map<String, Object?>);
      case 'ref':
        return gen(decls[t['name']] as Map<String, Object?>);
      case 'union':
        final ms = (t['members'] as List).cast<Map<String, Object?>>();
        return gen(ms[pick % ms.length]);
      case 'obj':
        final out = <String, Object?>{};
        for (final p in (t['props'] as List).cast<Map<String, Object?>>()) {
          if (p['optional'] == true && !full) continue;
          out[p['name'] as String] = gen(p['type'] as Map<String, Object?>);
        }
        if (t['extras'] != null && full) {
          out['extraKey'] = gen(t['extras'] as Map<String, Object?>);
        }
        return out;
    }
    throw StateError('unknown IR kind ${t['k']}');
  }
}

Map<String, Object?> envelope(Map<String, Object?> ev, Synth s) {
  final json = <String, Object?>{
    'type': ev['type'],
    'seq': 41,
    'time': 1760000000000,
  };
  final data = ev['data'];
  if (data != null) json['data'] = s.gen(data as Map<String, Object?>);
  if (ev['surfaceOp'] != null) {
    json['surfaceOp'] = s.gen(ev['surfaceOp'] as Map<String, Object?>);
  }
  if (ev['sourceEventSeqs'] != null &&
      (s.full || ev['sourceEventSeqsOptional'] == false)) {
    json['sourceEventSeqs'] = [3, 4];
  }
  return json;
}

void main() {
  final ir = loadIr();
  final events = (ir['events'] as List).cast<Map<String, Object?>>();
  final decls = ir['decls'] as Map<String, Object?>;
  final types = [for (final e in events) e['type'] as String];

  group('catalog', () {
    test(
      'knownSessionEventTypes covers every type of persistence-schema.json',
      () {
        expect(ir['formatVersion'], sessionEventFormatVersion);
        expect(types, hasLength(62));
        expect(knownSessionEventTypes, containsAll(types));
        expect(knownSessionEventTypes, hasLength(types.length));
        expect(sessionEventSchemaDigests.keys.toSet(), knownSessionEventTypes);
      },
    );
  });

  group('every event type round-trips', () {
    for (final ev in events) {
      final type = ev['type'] as String;
      test(type, () {
        for (var pick = 0; pick < 8; pick++) {
          for (final full in [false, true]) {
            final json = envelope(ev, Synth(decls, pick: pick, full: full));
            final decoded = SessionEvent.fromJson(json);
            expect(decoded.isKnown, isTrue, reason: type);
            expect(decoded.type, type);
            expect(decoded.seq, 41);
            expect(decoded.time, 1760000000000);
            // encode -> JSON text -> decode: equal to the input
            final again = jsonDecode(jsonEncode(decoded.toJson()));
            expect(again, json, reason: 'pick=$pick full=$full');
            expect(SessionEvent.fromJson(again).toJson(), json);
          }
        }
      });
    }
  });

  group('typed access', () {
    test('turn/start', () {
      final e = SessionEvent.fromJson({
        'type': 'turn/start',
        'seq': 2,
        'time': 1760000000100,
        'data': {'turn': 1},
      });
      e as TurnStartEvent;
      expect(e.data.turn, 1);
      expect(e.ignorable, isFalse);
      expect(e.surfaceOp, isNull);
      expect(e.isSkippable, isFalse);
    });

    test('approval/asked keeps optional fields optional', () {
      final e = SessionEvent.fromJson({
        'type': 'approval/asked',
        'seq': 5,
        'time': 1760000000200,
        'data': {'id': 'ap-1', 'toolName': 'bash'},
      });
      e as ApprovalAskedEvent;
      expect(e.data.toolName, 'bash');
      expect(e.data.callId, isNull);
      expect(e.data.reason, isNull);
    });

    test('tool/call', () {
      final e = SessionEvent.fromJson({
        'type': 'tool/call',
        'seq': 6,
        'time': 1760000000300,
        'data': {
          'arguments': '{"cmd":"ls"}',
          'callId': 'c1',
          'name': 'bash',
          'step': 1,
          'turn': 1,
        },
      });
      e as ToolCallEvent;
      expect(e.data.name, 'bash');
      expect(e.data.arguments, '{"cmd":"ls"}');
    });

    test('surface events expose append and replace surface ops', () {
      final surface = events.firstWhere((e) => e['surface'] == true);
      final seen = <Type>{};
      for (var pick = 0; pick < 4; pick++) {
        final json = envelope(surface, Synth(decls, pick: pick, full: true));
        final e = SessionEvent.fromJson(json);
        seen.add(e.surfaceOp.runtimeType);
        expect(e.surfaceOp, isNotNull);
      }
      expect(
        seen,
        containsAll(<Type>[SessionSurfaceOpAppend, SessionSurfaceOpReplace]),
      );
    });

    test('replace surface op carries its seq range', () {
      final surface = events.firstWhere((e) => e['surface'] == true);
      final json = envelope(surface, Synth(decls, pick: 0, full: true));
      json['surfaceOp'] = {'op': 'replace', 'startSeq': 3, 'endSeq': 9};
      final op =
          SessionEvent.fromJson(json).surfaceOp as SessionSurfaceOpReplace;
      expect(op.startSeq, 3);
      expect(op.endSeq, 9);
    });
  });

  group('unknown and malformed events', () {
    test('an unknown ignorable event is kept raw and skippable', () {
      final raw = {
        'type': 'plugin/future-thing',
        'seq': 9,
        'time': 1760000000400,
        'ignorable': true,
        'data': {
          'whatever': [1, 2, 3],
        },
        'surfaceOp': 'append',
      };
      final e = SessionEvent.fromJson(raw);
      expect(e, isA<UnknownSessionEvent>());
      expect(e.isKnown, isFalse);
      expect(e.isSkippable, isTrue);
      expect(e.ignorable, isTrue);
      expect((e as UnknownSessionEvent).mustUnderstand, isFalse);
      expect(e.type, 'plugin/future-thing');
      expect(e.seq, 9);
      expect(e.toJson(), raw);
    });

    test('an unknown event without ignorable must be understood', () {
      final e = SessionEvent.fromJson({
        'type': 'plugin/required',
        'seq': 10,
        'time': 1,
        'data': null,
      });
      e as UnknownSessionEvent;
      expect(e.isSkippable, isFalse);
      expect(e.mustUnderstand, isTrue);
    });

    test('a known type missing a required field names the path', () {
      expect(
        () => SessionEvent.fromJson({
          'type': 'turn/start',
          'seq': 2,
          'time': 3,
          'data': <String, Object?>{},
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            r'$.data.turn: required field is missing',
          ),
        ),
      );
      expect(
        () => SessionEvent.fromJson({
          'type': 'turn/start',
          'time': 3,
          'data': {'turn': 1},
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            r'$.seq: required field is missing',
          ),
        ),
      );
    });

    test('extra fields are ignored', () {
      final e = SessionEvent.fromJson({
        'type': 'turn/start',
        'seq': 2,
        'time': 3,
        'brandNew': 1,
        'data': {'turn': 1, 'alsoNew': 'x'},
      });
      expect((e as TurnStartEvent).data.turn, 1);
      expect(e.toJson(), {
        'type': 'turn/start',
        'seq': 2,
        'time': 3,
        'data': {'turn': 1},
      });
    });

    test('a non-object event is rejected', () {
      expect(() => SessionEvent.fromJson('turn/start'), throwsFormatException);
    });
  });
}
