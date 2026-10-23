import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeActions actions;
  late Session session;
  late SessionOwner owner;
  late SlotRegistry slots;

  setUp(() {
    actions = FakeActions();
    session = Session('s1', FakeTransport());
    owner = testSessionOwner('s1', session: session, actions: actions);
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerConversationFeature(slots, i18n: () => const DshI18n(DshLocale.en));
  });

  Widget composer() => dshTestApp(
    DefaultComposer(owner: owner, i18n: const DshI18n(DshLocale.en)),
  );

  testWidgets(
    'typing enables send; send clears the field and calls the service',
    (t) async {
      await t.pumpWidget(composer());
      final send = find.byKey(const ValueKey('composer-send'));
      await t.tap(send); // disabled: nothing
      expect(actions.sent, isEmpty);
      await t.enterText(find.byType(EditableText), '  hello world ');
      await t.pump();
      await t.tap(send);
      await t.pump();
      expect(actions.sent, ['hello world']);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
    },
  );

  testWidgets('a refused send keeps the text and says so', (t) async {
    actions.failSend = StateError('host refused');
    await t.pumpWidget(composer());
    await t.enterText(find.byType(EditableText), 'try this');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('composer-send')));
    await t.pump();
    expect(find.byKey(const ValueKey('composer-error')), findsOneWidget);
    expect(
      t.widget<EditableText>(find.byType(EditableText)).controller.text,
      'try this',
    );
  });

  testWidgets('the stop button appears while a turn runs and cancels it', (
    t,
  ) async {
    await t.pumpWidget(composer());
    expect(find.byKey(const ValueKey('composer-cancel')), findsNothing);
    session.handleRunning(true);
    await t.pump();
    expect(find.byKey(const ValueKey('composer-cancel')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('composer-cancel')));
    expect(actions.cancels, 1);
    session.handleRunning(false);
    await t.pump();
    expect(find.byKey(const ValueKey('composer-cancel')), findsNothing);
  });

  group('model indicator', () {
    test('prefers the next selection, falls back to the last used one', () {
      expect(
        modelIndicator({
          'next': {'model': 'm-next', 'reasoningEffort': 'high'},
          'lastUsed': {'model': 'm-last'},
        }),
        (model: 'm-next', effort: 'high'),
      );
      expect(
        modelIndicator({
          'lastUsed': {'model': 'm-last', 'reasoningEffort': ''},
        }),
        (model: 'm-last', effort: null),
      );
      expect(modelIndicator(null), isNull);
    });

    testWidgets('the header shows title and model from projections', (t) async {
      session.projections.apply('title', 'My task', 1);
      session.projections.apply('modelSelection', {
        'next': {'model': 'deepseek-x', 'reasoningEffort': 'max'},
      }, 1);
      await t.pumpWidget(dshTestApp(slots.renderSingle(headerSlot, owner)!));
      expect(find.text('My task'), findsOneWidget);
      expect(find.text('deepseek-x · max'), findsOneWidget);
      session.projections.apply('title', 'Renamed', 2);
      await t.pump();
      expect(find.text('Renamed'), findsOneWidget);
    });

    testWidgets('without a selection the indicator says so', (t) async {
      await t.pumpWidget(dshTestApp(slots.renderSingle(headerSlot, owner)!));
      expect(find.text('Model not set'), findsOneWidget);
      expect(find.text('Untitled session'), findsOneWidget);
    });
  });
}
