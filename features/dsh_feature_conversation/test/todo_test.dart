import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const en = DshI18n(DshLocale.en);

const items = [
  TodoItem('Write notes', 'completed'),
  TodoItem('Review PRs', 'in_progress'),
  TodoItem('Tag', 'pending'),
  TodoItem('Announce', 'pending'),
];

void main() {
  test('the projection value is read tolerantly', () {
    expect(todosOf(null), isEmpty);
    expect(todosOf('x'), isEmpty);
    final todos = todosOf([
      {'content': 'a', 'status': 'pending'},
      {'status': 'pending'},
      7,
    ]);
    expect(todos.length, 1);
    expect(todos.single.content, 'a');
  });

  test('the progress label omits empty segments', () {
    final label = todoProgressLabel(items, en);
    expect(label, contains('1 completed'));
    expect(label, contains('1 in progress'));
    expect(label, contains('2 pending'));
    expect(
      todoProgressLabel(const [TodoItem('a', 'completed')], en),
      '1 completed',
    );
    expect(
      todoProgressLabel(const [
        TodoItem('a', 'completed'),
      ], const DshI18n(DshLocale.zh)),
      '1 已完成',
    );
  });

  testWidgets(
    'the panel is collapsed with a summary; tapping lists the items',
    (t) async {
      await t.pumpWidget(dshTestApp(const TodoPanel(todos: items, i18n: en)));
      expect(find.text('To-dos'), findsOneWidget);
      expect(find.byKey(const ValueKey('todo-item-0')), findsNothing);
      await t.tap(find.byKey(const ValueKey('todo-header')));
      await t.pump();
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(ValueKey('todo-item-$i')), findsOneWidget);
      }
      expect(find.text('Review PRs'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('todo-header')));
      await t.pump();
      expect(find.byKey(const ValueKey('todo-item-0')), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('an empty list renders nothing', (t) async {
    await t.pumpWidget(dshTestApp(const TodoPanel(todos: [], i18n: en)));
    expect(find.byKey(const ValueKey('todo-panel')), findsNothing);
  });

  testWidgets('the dock follows the todos projection live', (t) async {
    final owner = testSessionOwner('s1');
    final slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    registerConversationFeature(slots, i18n: () => en);
    final dock = slots
        .renderList(
          DshSlots.conversationInputDock.typed<SessionOwner, Widget>(),
          owner,
        )
        .single;
    await t.pumpWidget(dshTestApp(dock));
    expect(find.byKey(const ValueKey('todo-panel')), findsNothing);
    owner.session.projections.apply('todos', [
      {'content': 'Only item', 'status': 'in_progress'},
    ], 5);
    await t.pump();
    expect(find.byKey(const ValueKey('todo-panel')), findsOneWidget);
    owner.session.projections.apply('todos', <Object?>[], 6);
    await t.pump();
    expect(find.byKey(const ValueKey('todo-panel')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
