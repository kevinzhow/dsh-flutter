import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> systemPromptCases = {
  'chat.system-prompt': ParityCase(
    widgets: const ['dsh_feature_chat:SystemPromptView'],
    build: (ctx) => Align(
      alignment: Alignment.topLeft,
      child: parityItem(
        'prompt-el',
        SizedBox(
          width: (ctx.props['width'] as num).toDouble(),
          child: parityItem(
            'prompt-toggle',
            SystemPromptView(
              text: ctx.props['text'] as String,
              update: ctx.props['update'] == true,
              i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
            ),
          ),
        ),
      ),
    ),
  ),
};
