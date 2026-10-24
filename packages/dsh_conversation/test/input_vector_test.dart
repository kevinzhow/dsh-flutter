import 'dart:convert';
import 'dart:io';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:test/test.dart';

/// The trigger pipeline's pure core against dsh's own TypeScript: every case of
/// `input_vector.json` was answered by the real `detectTrigger`, `activeAtToken`,
/// `formatFileMention` and the menu reducer (tool/vectors/gen_input_expected.py).
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/input_vector.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final cases = (fixture['cases']! as List).cast<Map<String, Object?>>();

  Map<String, Object?>? encodeHit(TriggerHit? h) => h == null
      ? null
      : {
          'trigger': h.trigger.char,
          'query': h.query,
          'quoted': h.quoted,
          'position': h.position.name,
          'start': h.span.start,
          'end': h.span.end,
        };

  TriggerHit hitOf(Map<String, Object?> h) => TriggerHit(
    trigger: TriggerChar.of(h['trigger']! as String)!,
    query: h['query']! as String,
    quoted: h['quoted'] == true,
    position: h['position'] == 'inline'
        ? TriggerPosition.inline
        : TriggerPosition.leading,
    span: TokenSpan(
      h['start']! as int,
      h['end']! as int,
      (h['draftRev'] ?? 1) as int,
    ),
  );

  Map<String, Object?> encodeState(MenuState s) => {
    'open': s.open,
    'hit': s.hit == null
        ? null
        : {
            'trigger': s.hit!.trigger.char,
            'query': s.hit!.query,
            'start': s.hit!.span.start,
            'end': s.hit!.span.end,
          },
    'generation': s.generation,
    'groups': [
      for (final g in s.groups)
        {
          'source': g.source,
          'showGroupTitle': g.showGroupTitle,
          'status': g.ready ? 'ready' : 'pending',
          'items': [for (final i in g.items) i.name],
        },
    ],
    'highlight': s.highlight == null
        ? null
        : {'source': s.highlight!.source, 'index': s.highlight!.index},
  };

  List<Map<String, Object?>> runMenu(Map<String, Object?> entry) {
    final sources = [
      for (final s in (entry['sources']! as List).cast<Map<String, Object?>>())
        (
          name: s['name']! as String,
          showGroupTitle: s['showGroupTitle'] != false,
        ),
    ];
    var state = menuClosed;
    final out = <Map<String, Object?>>[];
    for (final ev in (entry['events']! as List).cast<Map<String, Object?>>()) {
      switch (ev['type']) {
        case 'seed':
          state = seedGroups(state, sources);
        case 'hit':
          final h = ev['hit'] as Map<String, Object?>?;
          state = menuReduce(state, MenuHit(h == null ? null : hitOf(h)));
        case 'settled':
          state = menuReduce(
            state,
            MenuSourceSettled(
              ev['generation']! as int,
              ev['source']! as String,
              [
                for (final n in (ev['items']! as List))
                  InputTriggerCandidate(name: n! as String),
              ],
            ),
          );
        case 'failed':
          state = menuReduce(
            state,
            MenuSourceFailed(ev['generation']! as int, ev['source']! as String),
          );
        case 'move':
          state = menuReduce(state, MenuMove(ev['dir']! as int));
        case 'hover':
          state = menuReduce(
            state,
            MenuHover(ev['source']! as String, ev['index']! as int),
          );
        case 'close':
          state = menuReduce(state, const MenuClose());
        case 'exact':
          break;
        default:
          fail('unknown event ${ev['type']}');
      }
      final encoded = encodeState(state);
      if (ev['type'] == 'exact') {
        encoded['exact'] = exactMatch(
          state.groups,
          ev['source']! as String,
          ev['name']! as String,
        )?.name;
      }
      out.add(encoded);
    }
    return out;
  }

  Object? roundTrip(Object? v) => jsonDecode(jsonEncode(v));

  test('the fixture covers every op', () {
    final ops = {for (final c in cases) c['op']};
    expect(
      ops,
      containsAll(['detect', 'atToken', 'mention', 'rank', 'time', 'menu']),
    );
    expect(cases.length, greaterThan(1000));
  });

  test('trigger detection answers like dsh for every caret and tier', () {
    var n = 0;
    for (final c in cases.where((c) => c['op'] == 'detect')) {
      final tier = TriggerTier.values.byName(c['tier']! as String);
      final got = encodeHit(
        detectTrigger(c['draft']! as String, c['caret']! as int, tier),
      );
      expect(
        roundTrip(got),
        c['expect'],
        reason: 'detect ${jsonEncode(c['draft'])} @${c['caret']} ${c['tier']}',
      );
      n++;
    }
    expect(n, greaterThan(500));
  });

  test('the @ token grammar answers like dsh', () {
    for (final c in cases.where((c) => c['op'] == 'atToken')) {
      final at = activeAtToken(c['line']! as String, c['cursor']! as int);
      final got = at == null
          ? null
          : {'prefix': at.prefix, 'query': at.query, 'quoted': at.quoted};
      expect(
        got,
        c['expect'],
        reason: 'atToken ${jsonEncode(c['line'])} @${c['cursor']}',
      );
    }
  });

  test('a chosen path is written back as dsh writes it', () {
    for (final c in cases.where((c) => c['op'] == 'mention')) {
      final got = formatFileMention(
        FileCandidate(
          path: c['path']! as String,
          isDirectory: c['kind'] == 'directory',
        ),
        c['preserveQuote']! as bool,
      );
      expect(got, c['expect'], reason: 'mention ${jsonEncode(c)}');
    }
  });

  test('the menu reducer follows dsh through every scripted trace', () {
    for (final c in cases.where((c) => c['op'] == 'menu')) {
      expect(roundTrip(runMenu(c)), c['expect'], reason: '${c['name']}');
    }
  });
}
