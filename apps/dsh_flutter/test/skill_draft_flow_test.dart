import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_agent_management/dsh_feature_agent_management.dart';
import 'package:dsh_feature_conversation/src/composer_text.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_models/dsh_models.dart';

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
  testWidgets(
    'live literal lexicon preserves cursor, editing, serialization and original Session preview',
    (t) async {
      final host = FakeHost(), sessions = Sessions();
      host.handlers['skills/list'] = (_) => catalog;
      final source = SkillSource(
        remotes: host.remotes,
        sessions: sessions,
        i18n: () => const DshI18n(DshLocale.en),
      );
      final registry = InputTriggerRegistry();
      final remove = registry.registerSource(source);
      final input = ComposerInput(sessionId: 'original')..bind(registry);
      final text = ComposerTextController(input);
      input.setPlainText('/review /unknown x/review /review,');
      await t.pumpWidget(
        dshTestApp(
          ComposerLiteralPreview(
            controller: text,
            child: TextField(controller: text),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        input.triggers!
            .lexemes(input.snapshot.text)
            .map((l) => (l.start, l.end)),
        [(0, 7)],
      );
      final element = t.element(find.byType(TextField));
      final span = text.buildTextSpan(context: element, withComposing: true);
      expect(span.toPlainText(), input.snapshot.text);
      expect(input.clipboardText, '/review /unknown x/review /review,');
      expect(input.snapshot.chips, isEmpty);
      expect(
        span.children!.whereType<TextSpan>().where((s) => s.recognizer != null),
        isEmpty,
      );
      await t.tapAt(
        t.getTopLeft(find.byType(TextField)) + const Offset(25, 26),
      );
      await t.pump();
      expect(sessions.files, ['original:skills/review/SKILL.md']);
      await t.enterText(find.byType(TextField), '/rev /unknown');
      await t.pump();
      expect(input.triggers!.lexemes(input.snapshot.text), isEmpty);
      expect(input.clipboardText, '/rev /unknown');
      host.emit('agent-preset/selected', ['original', 'minimal']);
      await t.pump();
      expect(source.names('original'), isNull);
      remove();
      await t.pumpWidget(const SizedBox());
      text.dispose();
      input.dispose();
      await t.runAsync(() async {
        await source.dispose();
        await host.close();
      });
      expect(t.takeException(), isNull);
    },
  );
}
