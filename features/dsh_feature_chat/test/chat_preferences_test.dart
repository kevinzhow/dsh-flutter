import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:flutter_test/flutter_test.dart';

ConfigFormSnapshot ready(Map<String, Object?> value, {int revision = 0}) =>
    ConfigFormSnapshot(
      status: ConfigFormStatus.ready,
      value: value,
      base: const {},
      user: const {},
      revision: revision,
      writable: true,
    );
void main() {
  test('client defaults and legacy values are read without writing', () async {
    final prefs = ChatPreferences(desktop: true);
    final form = FakeConfigForm(ready({}));
    prefs.bind(form);
    expect(prefs.mode.value, TranscriptViewMode.standard);
    expect(form.writes, isEmpty);
    form.publish(ready({'transcriptView': 'expanded'}));
    expect(prefs.mode.value, TranscriptViewMode.detailed);
    form.publish(ready({'transcriptView': 'normal'}));
    expect(prefs.mode.value, TranscriptViewMode.detailed);
    form.publish(ready({'transcriptView': 'invalid'}));
    expect(prefs.mode.value, TranscriptViewMode.standard);
    expect(form.writes, isEmpty);
    await prefs.dispose();
  });
  test(
    'explicit choices write independent fields and restore on another client',
    () async {
      final prefs = ChatPreferences();
      final form = FakeConfigForm(ready({}));
      prefs.bind(form);
      prefs.setMode(TranscriptViewMode.compact);
      prefs.setTiming(CollapseTiming.nextInput);
      expect(prefs.mode.value, TranscriptViewMode.compact);
      expect(prefs.timing.value, CollapseTiming.nextInput);
      await Future<void>.delayed(Duration.zero);
      expect(form.written, {
        'transcriptView': 'compact',
        'collapseTiming': 'next-input',
      });
      form.publish(
        ready({
          'transcriptView': 'verbose',
          'collapseTiming': 'completion',
        }, revision: 3),
      );
      expect(prefs.mode.value, TranscriptViewMode.verbose);
      expect(prefs.timing.value, CollapseTiming.completion);
      await prefs.dispose();
    },
  );
  test('missing host preserves explicit choices within this process', () async {
    final prefs = ChatPreferences();
    prefs.setMode(TranscriptViewMode.verbose);
    prefs.setTiming(CollapseTiming.nextInput);
    expect(prefs.mode.value, TranscriptViewMode.verbose);
    expect(prefs.timing.value, CollapseTiming.nextInput);
    prefs.bind(null);
    expect(prefs.mode.value, TranscriptViewMode.detailed);
    await prefs.dispose();
  });
  test(
    'a refused write keeps the choice until an accepted host section arrives',
    () async {
      final prefs = ChatPreferences();
      final form = FakeConfigForm(ready({'transcriptView': 'detailed'}))
        ..answer = false;
      prefs.bind(form);
      prefs.setMode(TranscriptViewMode.verbose);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.mode.value, TranscriptViewMode.verbose);
      form.publish(ready({'transcriptView': 'standard'}, revision: 2));
      expect(prefs.mode.value, TranscriptViewMode.standard);
      await prefs.dispose();
    },
  );
}
