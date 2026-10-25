import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const i18n = DshI18n(DshLocale.en);
const reply = QuestionReplyData(
  callId: 'ask-fixture',
  text: 'Raw synthetic answer',
  time: 0,
  questions: [
    {
      'id': 'q',
      'question': 'Which option?',
      'header': 'Choice',
      'detail': 'Pick a fixture',
      'options': [
        {'label': 'One', 'description': 'First'},
      ],
    },
    {'id': 'skip', 'question': 'Any extras?'},
  ],
  answers: [
    {
      'id': 'q',
      'selected': ['One'],
      'custom': '  Extra  ',
    },
  ],
);
void main() {
  testWidgets(
    'keyboard disclosure retains detailed questions, options and skipped answers',
    (tester) async {
      await tester.pumpWidget(
        dshTestApp(const QuestionReplyView(data: reply, i18n: i18n)),
      );
      expect(find.text('One, Extra'), findsOneWidget);
      expect(find.text('Which option?'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Which option?'), findsOneWidget);
      expect(find.text('Pick a fixture'), findsOneWidget);
      expect(find.text('• One — First'), findsOneWidget);
      expect(
        find.textContaining('Skipped', findRichText: true),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.text('Which option?'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'copy always uses all answers and malformed payload opens as plain text',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await tester.pumpWidget(
        dshTestApp(const QuestionReplyView(data: reply, i18n: i18n)),
      );
      await tester.tap(find.bySemanticsLabel('Copy'));
      await tester.pump();
      expect(copied, replyClipboardText(reply, i18n));
      expect(copied, contains('Choice — Which option?'));
      expect(copied, contains('Any extras?'));
      await tester.pumpWidget(
        dshTestApp(
          QuestionReplyView(
            key: const ValueKey('opaque'),
            data: const QuestionReplyData(
              callId: 'bad',
              text: '<literal>\n**not Markdown**',
              time: 0,
              questions: [],
              answers: [],
            ),
            i18n: i18n,
            initiallyOpen: true,
          ),
        ),
      );
      expect(find.text('<literal>\n**not Markdown**'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    },
  );
}
