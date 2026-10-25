import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> lateReplyCases = {
  'chat.question-reply': ParityCase(
    widgets: const ['dsh_feature_user_questions:QuestionReplyView'],
    build: (ctx) {
      final d = (ctx.props['data'] as Map).cast<String, Object?>();
      return Align(
        alignment: Alignment.topLeft,
        child: parityItem(
          'node-el',
          SizedBox(
            width: (ctx.props['width'] as num).toDouble(),
            child: Stack(
              children: [
                QuestionReplyView(
                  data: QuestionReplyData(
                    callId: d['callId'] as String,
                    text: d['text'] as String,
                    time: d['time'] as num,
                    questions: [
                      for (final q in d['questions'] as List)
                        (q as Map).cast<String, Object?>(),
                    ],
                    answers: [
                      for (final a in d['answers'] as List)
                        (a as Map).cast<String, Object?>(),
                    ],
                  ),
                  i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
                ),
                Positioned(
                  right: 50,
                  top: 23,
                  child: IgnorePointer(
                    child: parityItem(
                      'node-toggle',
                      const SizedBox.square(dimension: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  ),
};
