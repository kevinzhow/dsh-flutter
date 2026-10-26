import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_agent_management/dsh_feature_agent_management.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class Sessions implements InputSessionPort {
  bool subagent = false;
  final opened = <String>[];
  Future<void>? gate;
  @override
  Future<void> ensureOpen(String id, AbortSignal signal) async {
    opened.add(id);
    await gate;
    signal.throwIfAborted();
  }

  @override
  bool isSubagentTranscript(String id) => subagent;
  @override
  String get hostHome => '';
  @override
  SessionSummary? summary(String id) => null;
  final files = <String>[];
  @override
  void openFile(String id, String path) => files.add('$id:$path');
}

CandidateRequest req([AbortSignal? signal]) => CandidateRequest(
  query: '',
  quoted: false,
  position: TriggerPosition.leading,
  drilled: false,
  signal: signal ?? AbortSignal.never,
);
const catalog = {
  'skills': [
    {
      'name': 'review',
      'description': 'Review changes',
      'modelInvocable': false,
      'path': 'skills/review/SKILL.md',
    },
  ],
};
void main() {
  test('request cancellation preserves shared warmup; preset/reset invalidation excludes late catalogs', () async {
    final host = FakeHost(), sessions = Sessions();
    final source = SkillSource(
      remotes: host.remotes,
      sessions: sessions,
      i18n: () => const DshI18n(DshLocale.en),
    );
    final gate = Completer<Object?>();
    host.handlers['skills/list'] = (_) => gate.future;
    source.warm('s');
    final cancel = AbortController();
    final old = source.candidates('s', req(cancel.signal));
    cancel.abort();
    await Future<void>.delayed(Duration.zero);
    expect(host.callsTo('skills/list'), hasLength(1));
    gate.complete(catalog);
    expect(await old, isEmpty);
    expect(source.names('s'), ['review']);
    final rows = await source.candidates('s', req());
    expect(rows.single.description, contains('Review changes'));
    expect(rows.single.hint, isNull);
    expect(source.openReference('s', '/review', 'skill'), true);
    expect(sessions.files, ['s:skills/review/SKILL.md']);
    host.emit('agent-preset/selected', ['s', 'minimal']);
    expect(source.names('s'), isNull);
    final stale = Completer<Object?>();
    host.handlers['skills/list'] = (_) => stale.future;
    final pending = source.candidates('s', req());
    final rejected = expectLater(pending, throwsA(anything));
    await Future<void>.delayed(Duration.zero);
    host.emit('plugin-manager/changed');
    stale.complete(catalog);
    await rejected;
    expect(source.names('s'), isNull);
    sessions.subagent = true;
    expect(await source.candidates('child', req()), isEmpty);
    await source.dispose();
    await host.close();
  });

  test(
    'only caller-confirmed complete slash tokens become skill references',
    () {
      final registry = UserTextRegistry()..register(skillReferenceRule);
      final doc = registry.createDocument();
      const text = '/review /unknown /review, x/review\n/review';
      expect(doc.evaluate(text).where((n) => n.id == 'skill'), isEmpty);
      final nodes = doc
          .evaluate(
            text,
            facts: {
              'skillNames': ['review'],
            },
          )
          .where((n) => n.id == 'skill')
          .toList();
      expect(nodes.map((n) => n.raw(text)), ['/review', '/review']);
      expect(nodes.map((n) => n.start), [0, text.lastIndexOf('/review')]);
    },
  );

  testWidgets(
    'durable skill result owns its name, error and bounded selectable instructions',
    (tester) async {
      final call = ToolResult(
        callId: 'c',
        name: 'skill',
        args: PartialArguments.empty,
        subCalls: const [],
        seq: 2,
        time: 1,
        callArgsRaw: '{"name":"review\\nsecond"}',
        content: const [
          {'type': 'text', 'text': 'First error\nUseful instructions'},
        ],
        isError: true,
      );
      final data = skillRowData(call);
      expect(data.name, 'review');
      expect(data.errorSummary, 'First error');
      expect(data.state, 'error');
      await tester.pumpWidget(
        dshTestApp(SkillRow(call: call, i18n: const DshI18n(DshLocale.en))),
      );
      await tester.tap(find.text('First error'));
      await tester.pumpAndSettle();
      expect(find.text('First error\nUseful instructions'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
