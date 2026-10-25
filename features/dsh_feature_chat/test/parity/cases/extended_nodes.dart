import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> extendedInputCases = {
  for (final family in ['command-input', 'context-injection'])
    'chat.$family': ParityCase(
      widgets: [
        'dsh_feature_chat:${family == 'command-input' ? 'GoalCommandInputView' : 'ContextInjectionView'}',
      ],
      build: (ctx) {
        final d = (ctx.props['data'] as Map).cast<String, Object?>();
        final i18n = DshI18n(DshLocale.fromTag(ctx.locale));
        return Align(
          alignment: Alignment.topLeft,
          child: parityItem(
            'node-el',
            SizedBox(
              width: (ctx.props['width'] as num).toDouble(),
              child: parityItem(
                'node-toggle',
                family == 'command-input'
                    ? GoalCommandInputView(
                        data: CommandInputData(
                          commandId: d['commandId'],
                          text: d['text'] as String,
                          time: d['time'] as num,
                        ),
                        i18n: i18n,
                      )
                    : ContextInjectionView(
                        data: MessageData(
                          kind: 'context',
                          seq: d['seq'] as num,
                          time: d['time'] as num,
                          content: d['content'] as List,
                          source: (d['source'] as Map).cast<String, Object?>(),
                          form: d['form'] as String?,
                          producerRole:
                              (d['producer'] as Map)['role'] as String,
                          producerLabel:
                              (d['producer'] as Map)['label'] as String?,
                        ),
                        i18n: i18n,
                      ),
              ),
            ),
          ),
        );
      },
    ),
};
