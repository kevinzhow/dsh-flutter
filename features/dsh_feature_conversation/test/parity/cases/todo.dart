// The to-do dock (dsh ui-conversation TodoPanel). Props: {todos: [{content, status}]}.
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';

final Map<String, ParityCase> todoCases = {
  'plan.todo-panel': ParityCase(
    widgets: const ['dsh_feature_conversation:TodoPanel'],
    build: (ctx) => parityItem(
      'todo-panel',
      TodoPanel(
        todos: [
          for (final t
              in (ctx.props['todos'] as List).cast<Map<String, dynamic>>())
            TodoItem(t['content'] as String, t['status'] as String),
        ],
        i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
      ),
    ),
  ),
};
