import 'dart:convert';
import 'dart:io';

import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:flutter_test/flutter_test.dart';

ConfigFormSnapshot ready(Map<String, Object?> value) => ConfigFormSnapshot(
  status: ConfigFormStatus.ready,
  value: value,
  base: const {},
  user: const {},
  writable: true,
);
void main() {
  test('16 actual upstream delivery expectations', () {
    final vector = jsonDecode(
      File('test/fixtures/submission_policy.json').readAsStringSync(),
    ) as Map;
    expect(vector['cases'], hasLength(16));
    for (final row in vector['cases'] as List) {
      expect(
        resolveSubmitMode(
          row['preferred'] as String,
          row['running'] as bool,
          accelerated: row['gesture'] == 'accelerated',
          steeringAvailable: row['available'] as bool,
        ),
        row['expected'],
        reason: '$row',
      );
    }
  });
  test(
    'Host preference adopts across clients without writing; Host switch resets',
    () async {
      final p = ConversationPreferences();
      final host = FakeConfigForm(ready({'busyEnter': 'steer'}));
      p.bind(host);
      expect(p.busyEnter.value, 'steer');
      expect(host.writes, isEmpty);
      host.publish(ready({'busyEnter': 'queue'}));
      expect(p.busyEnter.value, 'queue');
      p.setBusyEnter('steer');
      await Future<void>.delayed(Duration.zero);
      expect(host.written, {'busyEnter': 'steer'});
      p.bind(null);
      expect(p.busyEnter.value, 'queue');
      host.publish(ready({'busyEnter': 'steer'}));
      expect(p.busyEnter.value, 'queue');
      await p.dispose();
    },
  );
  test('refusal preserves explicit preference until next accepted section, invalid values default', () async {
    final p = ConversationPreferences();
    final host = FakeConfigForm(ready({}))..answer = false;
    p.bind(host);
    p.setBusyEnter('steer');
    await Future<void>.delayed(Duration.zero);
    expect(p.busyEnter.value, 'steer');
    host.publish(ready({'busyEnter': 'invalid'}));
    expect(p.busyEnter.value, 'queue');
    p.setBusyEnter('invalid');
    expect(p.busyEnter.value, 'queue');
    await p.dispose();
  });
}
