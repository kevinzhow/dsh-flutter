// Behaviour vectors for the conversation port. Each fixture is a scrubbed trace
// of a real dsh session replayed through dsh's own TypeScript conversation
// engine and chat Definitions (tool/vectors/ts) to produce `expectedChat`; the
// Dart port must produce the same chat snapshot after every step.
import 'dart:convert';
import 'dart:io';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/testing.dart';
import 'package:test/test.dart';

import 'support/chat_projection.dart';

const fixtures = [
  '../dsh_models/test/fixtures/session_window_vector.json',
  'test/fixtures/conversation_edge_vector.json',
  'test/fixtures/plan_todo_vector.json',
  'test/fixtures/attachment_vector.json',
  'test/fixtures/tool_turn_vector.json',
  'test/fixtures/system_prompt_vector.json',
  'test/fixtures/model_retry_vector.json',
];

void main() {
  for (final path in fixtures.where((p) => File(p).existsSync())) {
    final file = File(path);
    group(path.split('/').last, () {
      late Map<String, Object?> fixture;
      setUpAll(
        () => fixture =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      );

      test('carries TS-produced chat expectations', () {
        final by = fixture['expectedBy']! as Map<String, Object?>;
        expect(by['model'], contains('conversation engine'));
        expect(fixture['expectedChat'], isA<List<Object?>>());
        expect((fixture['expectedChat']! as List).length, greaterThan(5));
      });

      test('Dart chat snapshot equals the TS one after every step', () async {
        late ConversationBinding binding;
        final actual = await replayFixture(
          fixture,
          attach: (session) {
            binding = ConversationBinding.chat(
              session.eventSource,
              scheduler: FlushScheduler.immediate(),
            );
          },
          project: () => {
            'chat': projectChat(
              binding.chat.value,
              binding.openTurn.value,
              binding.todoHistory.value,
              fixture['projectSystemPrompts'] == true,
            ),
          },
        );
        final expected = (fixture['expectedChat']! as List)
            .cast<Map<String, Object?>>();
        expect(actual.length, expected.length);
        for (var i = 0; i < expected.length; i++) {
          final step = expected[i]['step'];
          final want = Map<String, Object?>.of(expected[i])..remove('step');
          final got = actual[i]['chat']! as Map<String, Object?>;
          expect(actual[i]['step'], step);
          for (final key in want.keys) {
            expect(
              got[key],
              equals(want[key]),
              reason: '$key at step $step of ${path.split('/').last}',
            );
          }
        }
        await binding.dispose();
      });
    });
  }
}
