import 'dart:convert';
import 'dart:io';

import 'package:dsh_feature_session/dsh_feature_session.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/workspace_behavior.json').readAsStringSync(),
  ) as Map;
  final expected = fixture['expected'] as Map;
  test('fork titles match the actual pinned private helper', () {
    for (final row in expected['titles'] as List) {
      expect(increasedForkTitle(row['input'] as String), row['expected']);
    }
  });
  test('visible drag matches the actual pinned helper with hidden members', () {
    for (final row in expected['drag'] as List) {
      final rows = [
        for (final raw in row['rows'] as List)
          SessionNode(
            id: raw['id'] as String,
            title: '',
            blank: raw['blank'] == true,
            pinned: raw['pinned'] == true,
            archived: false,
            running: false,
            runningSubagents: 0,
            completed: false,
            updatedAt: 0,
          ),
      ];
      final result = sessionDragOrder(
        (row['order'] as List).cast<String>(),
        rows,
        row['drag']['sessionId'] as String,
        row['drag']['pinned'] == true,
        row['over']['id'] as String,
        after: row['over']['half'] == 'after',
      );
      expect(
        result,
        row['expected'],
        reason: '${row['drag']} => ${row['over']}',
      );
    }
  });
  test(
    'header ancestry matches upstream forks, missing parents and cycles',
    () {
      for (final row in expected['ancestry'] as List) {
        final list = SessionListSnapshot(
          items: [
            for (final raw in (row['list']['byId'] as Map).values)
              SessionListEntry(
                SessionSummary(
                  sessionId: raw['id'] as String,
                  parentSessionId: raw['parentId'] as String?,
                  origin: raw['origin'] as String?,
                  updatedAt: 0,
                  running: false,
                  blank: false,
                  agentAvailable: true,
                ),
                raw['displayTitle'] as String?,
              ),
          ],
        );
        final result = deriveSessionAncestry(
          list,
          row['id'] as String,
          untitled: 'Untitled',
        );
        expect([
          for (final crumb in result)
            {
              'id': crumb.sessionId,
              'displayTitle': crumb.title,
              'subagent': crumb.subagent,
            },
        ], row['expected']);
      }
    },
  );
}
