// The stream controls of dsh's chat view (ui-chat): the back-to-bottom chevron, the "Loading history…" hint, the "Load
// earlier" control and the clock + copy actions of a message. Props are the React host's
// (tool/parity-ext/build-chat-stream.py): {control} and {clock}.
import 'package:dsh_feature_chat/src/stream/jump_button.dart';
import 'package:dsh_feature_chat/src/stream/load_earlier.dart';
import 'package:dsh_feature_chat/src/stream/loading_hint.dart';
import 'package:dsh_feature_chat/src/stream/message_actions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> chatStreamCases = {
  'chat.stream.control': ParityCase(
    widgets: const [
      'dsh_feature_chat:StreamJumpButton',
      'dsh_feature_chat:LoadingHint',
      'dsh_feature_chat:LoadEarlierButton',
    ],
    build: (ctx) {
      final i18n = DshI18n(DshLocale.fromTag(ctx.locale));
      final Widget control = switch (ctx.props['control']) {
        'to-bottom' => StreamJumpButton(
          label: i18n.t('chat', 'chat.toBottom'),
          onPressed: () {},
          touchTarget: false,
        ),
        'hint' => LoadingHint(i18n.t('chat', 'chat.loadingHistory')),
        'load-earlier' => LoadEarlierButton(
          label: i18n.t('chat', 'chat.loadOlder'),
          onPressed: () {},
          touchTarget: false,
        ),
        _ => LoadEarlierButton(
          label: i18n.t('common', 'loading'),
          onPressed: null,
          touchTarget: false,
        ),
      };
      return Align(
        alignment: Alignment.topLeft,
        child: parityItem('stream-el', control),
      );
    },
  ),
  'chat.stream.actions': ParityCase(
    widgets: const ['dsh_feature_chat:MessageActions'],
    build: (ctx) => Align(
      alignment: Alignment.topLeft,
      child: parityItem(
        'stream-el',
        MessageActions(
          text: 'Copy me',
          i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
          time: DateTime(2020, 3, 4, 10, 5).millisecondsSinceEpoch,
          clockFirst: ctx.props['clock'] != 'end',
          touchTarget: false,
        ),
      ),
    ),
  ),
};
