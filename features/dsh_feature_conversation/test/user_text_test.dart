import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

SlotRegistry seats() {
  final slots = SlotRegistry();
  for (final s in DshSlots.all) {
    slots.declare(s);
  }
  return slots;
}

void main() {
  testWidgets(
    'missing renderers retain raw text and registry changes reach a mounted document',
    (t) async {
      final registry = UserTextRegistry(), slots = seats();
      addTearDown(registry.dispose);
      registerUserTextFactory(slots, registry);
      await t.pumpWidget(
        dshTestApp(
          slots.renderSingle(
            DshSlots.conversationUserText.typed<UserTextOwner, Widget>(),
            const UserTextOwner(text: 'original'),
          )!,
        ),
      );
      expect(find.text('original', findRichText: true), findsOneWidget);
      final off = registry.register(
        UserTextRule(
          id: 'tag',
          order: 0,
          match: (text, from, c) => from == 0
              ? UserTextNode('tag', 0, text.length, {'label': 'changed'})
              : null,
        ),
      );
      await t.pump();
      expect(find.text('original', findRichText: true), findsOneWidget);
      slots.register<UserTextNodeOwner, InlineSpan>(
        DshSlots.conversationUserTextNode
            .typed<UserTextNodeOwner, InlineSpan>(),
        (owner) => TextSpan(text: owner.node.data['label'] as String),
        key: 'tag',
      );
      await t.pumpWidget(
        dshTestApp(
          ConversationUserText(
            owner: const UserTextOwner(text: 'original'),
            registry: registry,
            slots: slots,
          ),
        ),
      );
      expect(find.text('changed', findRichText: true), findsOneWidget);
      off();
      await t.pump();
      expect(find.text('original', findRichText: true), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
  testWidgets(
    'a failed matcher reports once and publishes the whole original string',
    (t) async {
      final registry = UserTextRegistry(), slots = seats();
      addTearDown(registry.dispose);
      registry.register(
        UserTextRule(
          id: 'bad',
          order: 0,
          match: (text, from, c) => throw StateError('Synthetic refusal'),
        ),
      );
      final errors = <Object>[];
      await t.pumpWidget(
        dshTestApp(
          ConversationUserText(
            owner: const UserTextOwner(text: 'whole original'),
            registry: registry,
            slots: slots,
            reportFailure: errors.add,
          ),
        ),
      );
      await t.pump();
      expect(errors, hasLength(1));
      expect(find.text('whole original', findRichText: true), findsOneWidget);
      await t.pump();
      expect(errors, hasLength(1));
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
}
