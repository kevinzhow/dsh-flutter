import 'dart:convert';
import 'dart:io';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

class _Reader implements ContextReader {
  @override
  PreviousContext? previous(String kind) => null;
}

NodeContext context(Object? state) => NodeContext(
  key: 'd',
  kind: 'deliverables',
  id: '1',
  matches: [],
  start: null,
  state: state,
  current: {},
);
Map<String, Object?> producedJson(ProducedPath p) => {
  'seq': p.seq,
  'path': p.path,
  if (p.argumentPath != null) 'argumentPath': p.argumentPath,
};
Map<String, Object?> presentedJson(PresentedPath p) => {
  'seq': p.seq,
  'index': p.index,
  'path': p.path,
  if (p.description != null) 'description': p.description,
};
Map<String, Object?> dataJson(DeliverablesTurnData d) => {
  'produced': d.produced.map(producedJson).toList(),
  'presented': d.presented.map(presentedJson).toList(),
  if (d.changes != null) 'changes': {'seq': d.changes!.seq},
};
Object? normalized(Object? value) {
  if (value is List) return value.map(normalized).toList();
  if (value is Map) {
    return {
      for (final e in value.entries) e.key: normalized(e.value),
      if (value.containsKey('produced') && !value.containsKey('presented'))
        'presented': [],
    };
  }
  return value;
}

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/deliverables_behavior.json').readAsStringSync(),
  ) as Map;
  final expected = fixture['expected'] as Map;
  const def = DeliverablesDefinition();
  test(
    'Host DTO validators match the actual published TypeScript contracts',
    () {
      bool valid(Object? value, Object? Function(Object?) parse) {
        try {
          parse(value);
          return true;
        } on FormatException {
          return false;
        }
      }

      final parsers = <String, Object? Function(Object?)>{
        'changedFiles': ChangedFile.fromJson,
        'summaries': ChangesSummary.fromJson,
        'diffs': ChangesDiff.fromJson,
        'hosts': PresentedHost.fromJson,
        'applications': (value) {
          if (value is! List) throw const FormatException();
          return value.map(NativeFileApplication.fromJson).toList();
        },
      };
      for (final entry in parsers.entries) {
        expect(
          (fixture[entry.key] as List)
              .map((value) => valid(value, entry.value))
              .toList(),
          (expected['records'] as Map)[entry.key],
          reason: entry.key,
        );
      }
    },
  );

  test(
    'turn facts and closing cutoffs match the actual production definition',
    () {
      final sequences = fixture['sequences'] as List;
      for (var i = 0; i < sequences.length; i++) {
        final c = sequences[i] as Map;
        final states = <String, Object>{};
        final result = <Object?>[];
        for (final raw in c['events'] as List) {
          final event = ConvEvent(
            EventEntry(Map<String, Object?>.from(raw as Map)),
          );
          final match = def.match(event);
          if (match != null) {
            final full = ConversationMatch(
              event,
              match.role,
              const UnresolvedLocation(),
            );
            if (match.role == MatchRole.start) {
              states[match.id] = def.start(context(null), full, _Reader());
            } else if (states.containsKey(match.id)) {
              states[match.id] = def.update(context(states[match.id]), full);
            }
          }
          final state = states['${c['turn']}'];
          final data = state == null
              ? null
              : def
                        .buildLocationData(
                          context(state),
                          LocationScope.turn,
                          null,
                        )!
                        .value
                    as DeliverablesTurnData;
          result.add({
            'data': data == null ? null : dataJson(data),
            'produced': producedForClosing(data, c['closing'] as num),
            'presented': presentedForClosing(
              data,
              c['closing'] as num,
            ).map(presentedJson).toList(),
            'changes': data?.changes == null
                ? null
                : {'seq': data!.changes!.seq},
          });
        }
        expect(
          result,
          normalized((expected['sequences'] as List)[i]),
          reason: 'sequence $i',
        );
      }
    },
  );
  test('only successful supported mutations and recorded canonical targets produce files', () {
    final cases = fixture['mutations'] as List;
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i] as Map;
      final argument = mutationPath(
        c['name'] as String,
        c['raw'] as String? ?? jsonEncode(c['args']),
      );
      final path =
          argument == null ||
              c['error'] == true ||
              (c['surface'] ?? 'append') != 'append'
          ? null
          : mutationResultPath(argument, c['meta']);
      expect(
        path == null
            ? []
            : [
                {
                  'seq': 2,
                  'path': path,
                  if (path != argument) 'argumentPath': argument,
                },
              ],
        (expected['mutations'] as List)[i],
        reason: 'mutation $i',
      );
    }
  });
  test('closing mentions stay inert for unknown or ambiguous paths', () {
    final cases = fixture['mentions'] as List;
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i] as Map;
      expect(
        resolveProducedFileMention(
          (c['paths'] as List).cast<String>(),
          c['value'] as String,
          operations: [
            for (final p in c['operations'] as List? ?? [])
              ProducedPath(
                seq: 0,
                path: p['path'] as String,
                argumentPath: p['argumentPath'] as String?,
              ),
          ],
        ),
        (expected['mentions'] as List)[i],
        reason: 'mention $i',
      );
    }
    expect({
      'files': (fixture['files'] as List).map(isPresentedFile).toList(),
      'deliveries': (fixture['deliveries'] as List)
          .map(isPresentedData)
          .toList(),
      'changes': (fixture['changes'] as List).map(isChangesEvent).toList(),
    }, expected['validation']);
  });
  test('engine publishes turn-isolated state without extra view rows or identity churn', () {
    final registries = defaultChatRegistries();
    final engine = ConversationAssembler(registries.events, registries.views);
    final events = ((fixture['sequences'] as List).first['events'] as List)
        .map((e) => ConvEvent(EventEntry(Map<String, Object?>.from(e as Map))))
        .toList();
    engine.replaceWindow(events, false);
    engine.flush();
    final first = engine.timeline.turns[1]!.data.get(
      'deliverables',
    ) as DeliverablesTurnData;
    final second = engine.timeline.turns[2]!.data.get(
      'deliverables',
    ) as DeliverablesTurnData;
    expect(producedForClosing(first), ['/synthetic/report.md']);
    expect(producedForClosing(second), ['other.txt']);
    final initial = def.start(
      context(null),
      ConversationMatch(
        events.first,
        MatchRole.start,
        const UnresolvedLocation(),
      ),
      _Reader(),
    );
    final published = def.buildLocationData(
      context(initial),
      LocationScope.turn,
      null,
    )!;
    final next = def.update(
      context(initial),
      ConversationMatch(
        events[1],
        MatchRole.update,
        const UnresolvedLocation(),
      ),
    );
    expect(
      identical(
        def.buildLocationData(context(next), LocationScope.turn, published),
        published,
      ),
      isTrue,
    );
  });
}
