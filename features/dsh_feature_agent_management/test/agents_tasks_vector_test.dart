import 'dart:convert';
import 'dart:io';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_agent_management/dsh_feature_agent_management.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final f = jsonDecode(
    File('../../packages/dsh_models/test/fixtures/agents_tasks.json')
        .readAsStringSync(),
  ) as Map;
  final expected = f['expected'] as Map;
  test('skill document ranges and data match actual pinned source matcher', () {
    final registry = UserTextRegistry()..register(skillReferenceRule);
    expect([
      for (final v in f['skillDocs'] as List)
        registry
            .createDocument()
            .evaluate(
              v['text'] as String,
              facts: {'skillNames': (v['names'] as List).cast<String>()},
            )
            .map(
              (n) => {
                'id': n.id,
                'start': n.start,
                'end': n.end,
                'data': n.data,
              },
            )
            .toList(),
    ], expected['skillDocs']);
  });
  test('created cards narrow replay JSON exactly as production and reject failed/nested results', () {
    ToolResult call(Object? raw, {bool failed = false, String? parent}) =>
        ToolResult(
          callId: 'call',
          name: 'schedule_create',
          callArgsRaw: '{}',
          args: PartialArguments.fromText('{}'),
          subCalls: const [],
          seq: 5,
          time: 5,
          content: [
            {'type': 'text', 'text': jsonEncode(raw)},
          ],
          isError: failed,
          parentCallId: parent,
        );
    expect([
      for (final v in f['created'] as List)
        createdTask(call(v), 'synthetic-session')?.expectedJson,
    ], expected['records']);
    expect(
      createdTask(call((f['created'] as List).first, failed: true), 's'),
      isNull,
    );
  });
}
