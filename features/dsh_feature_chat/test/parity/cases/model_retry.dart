import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> modelRetryCases = {
  'chat.model-retry': ParityCase(
    widgets: const ['dsh_feature_chat:ModelRetryView'],
    build: (ctx) => Align(
      alignment: Alignment.topLeft,
      child: parityItem(
        'retry-el',
        SizedBox(
          width: (ctx.props['width'] as num).toDouble(),
          child: ModelRetryView(
            attempt: ModelRetryAttempt(
              seq: 3,
              time: 0,
              retryId: 'fixture',
              turn: 1,
              step: 1,
              retry: 1,
              delayMs: 2500,
              maxRetries: 3,
              failureCode: 'RATE_LIMIT',
              failureMessage: 'Try later',
              state: ModelRetryState.values.byName(
                ctx.props['state'] as String,
              ),
            ),
            i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
            initiallyOpen: ctx.props['open'] == true,
            now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
          ),
        ),
      ),
    ),
  ),
};
