import 'dart:convert';
import 'dart:io';

import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final data = jsonDecode(
    File('test/fixtures/plan_reviews.json').readAsStringSync(),
  ) as Map;
  for (final (index, row) in (data['cases'] as List).indexed) {
    test('actual TS plan review intent $index', () {
      final value = planReviewOf([
        for (final q in row['questions'] as List)
          QuestionItem.fromWire(Map<String, Object?>.from(q as Map)),
      ]);
      if (value == null) {
        expect(row['expected'], isNull);
        return;
      }
      expect({
        'id': value.id,
        'question': value.question,
        'plan': value.plan,
        if (value.callId != null) 'callId': value.callId,
        'approve': {
          'label': value.approve.label,
          if (value.approve.description != null)
            'description': value.approve.description,
        },
        if (value.decline != null)
          'decline': {
            'label': value.decline!.label,
            if (value.decline!.description != null)
              'description': value.decline!.description,
          },
      }, row['expected']);
    });
  }
}
