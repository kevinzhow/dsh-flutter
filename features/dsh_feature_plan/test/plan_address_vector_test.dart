import 'dart:convert';
import 'dart:io';

import 'package:dsh_feature_plan/dsh_feature_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final data = jsonDecode(
    File('test/fixtures/plan_behavior.json').readAsStringSync(),
  ) as Map;
  for (final (index, row) in (data['expected']['addresses'] as List).indexed) {
    test('actual TS plan address $index', () {
      final parsed = PlanAddress.parse(row['address'] as String);
      expect(
        parsed == null
            ? null
            : {'session': parsed.session, 'callId': parsed.callId},
        row['parsed'],
      );
      expect(parsed?.encoded, row['encoded']);
    });
  }
}
