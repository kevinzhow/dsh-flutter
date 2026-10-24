import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/material.dart' show TextField;
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

  group('the composer card', () {
    testWidgets(
      'is one rounded box: the draft on top, the controls row inside it',
      (t) async {
        await t.pumpWidget(composer());
        final card = t.getRect(find.byType(ComposerCard));
        final field = t.getRect(find.byType(TextField));
        final tools = t.getRect(find.byKey(const ValueKey('composer-tools')));
        final send = t.getRect(find.byKey(const ValueKey('composer-send')));
        expect(card.contains(field.topLeft), isTrue);
        expect(card.contains(tools.bottomRight - const Offset(1, 1)), isTrue);
        expect(tools.top, greaterThan(field.bottom));
        expect(send.size, const Size(34, 34));
        expect(send.right, lessThan(card.right));
      },
    );

    testWidgets(
      'the draft keeps dsh\'s 36px floor docked and 52px in the hero',
      (t) async {
        await t.pumpWidget(composer());
        expect(t.getSize(find.byType(TextField)).height, lessThanOrEqualTo(36));
        await t.pumpWidget(
          dshTestApp(
            DefaultComposer(
              owner: owner,
              i18n: const DshI18n(DshLocale.en),
              hero: true,
            ),
          ),
        );
        final card = t.getRect(find.byType(ComposerCard));
        final tools = t.getRect(find.byKey(const ValueKey('composer-tools')));
        // 8 top + 52 draft + 12 gap before the controls row.
        expect(tools.top - card.top, greaterThanOrEqualTo(8 + 52 + 12));
      },
    );

    testWidgets(
      'side clearance of 16px, and a long draft grows the card up to 14 lines',
      (t) async {
        t.view.physicalSize = const Size(400, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(composer());
        expect(t.getRect(find.byType(ComposerCard)).left, 16);
        expect(t.getRect(find.byType(ComposerCard)).right, 384);
        final one = t.getSize(find.byType(ComposerCard)).height;
        await t.enterText(
          find.byType(EditableText),
          List.filled(30, 'line').join('\n'),
        );
        await t.pump();
        final many = t.getSize(find.byType(ComposerCard)).height;
        expect(many, greaterThan(one));
        // 14 lines of 24px plus the rest of the card.
        expect(many, lessThanOrEqualTo(one - 36 + 4 + 14 * 24 + 1));
      },
    );

    testWidgets('the send circle is dimmed while there is nothing to send', (
      t,
    ) async {
      await t.pumpWidget(composer());
      Opacity opacityOf() => t.widget<Opacity>(
        find.descendant(
          of: find.byKey(const ValueKey('composer-send')),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacityOf().opacity, 0.4);
      await t.enterText(find.byType(EditableText), 'hi');
      await t.pump();
      expect(opacityOf().opacity, 1);
    });
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
