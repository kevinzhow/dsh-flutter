import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'secret_text.dart';

void registerSecretMaskFeature(
  SlotRegistry slots, {
  required UserTextRegistry userText,
  required DshI18n Function() i18n,
}) {
  userText.register(createSecretRule());
  slots.register<UserTextNodeOwner, InlineSpan>(
    DshSlots.conversationUserTextNode.typed<UserTextNodeOwner, InlineSpan>(),
    (owner) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: SecretText(
        key: ValueKey(owner.identity),
        raw: owner.raw,
        masked: owner.node.data['masked'] as String,
        interactive: owner.interactive,
        ellipsis: owner.ellipsis,
        i18n: i18n(),
      ),
    ),
    key: 'secret',
  );
}
