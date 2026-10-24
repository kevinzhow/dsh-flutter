import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// The session's current plan from the `todos` projection (empty when absent
/// or malformed).
List<TodoItem> todosOf(Object? projection) => [
  if (projection is List)
    for (final item in projection)
      if (item is Map<String, Object?> && item['content'] is String)
        TodoItem(item['content']! as String, '${item['status']}'),
];

/// The progress label: per-status counts joined by an en-space dot, zero
/// segments omitted (dsh `progressLabel`).
String todoProgressLabel(List<TodoItem> todos, DshI18n i18n) {
  String c(String key, Map<String, Object?> params) =>
      i18n.t('conversation', key, params: params);
  final done = todos.where((t) => t.status == 'completed').length;
  final active = todos.where((t) => t.status == 'in_progress').length;
  final pending = todos.length - done - active;
  return [
    if (done > 0) c('todo.progress.done', {'done': done}),
    if (active > 0) c('todo.progress.active', {'active': active}),
    if (pending > 0) c('todo.progress.pending', {'pending': pending}),
  ].join(' · ');
}

/// The to-do dock (dsh `TodoPanel`): a collapsed header with the progress
/// summary above the composer; open, one row per item with its status mark.
class TodoPanel extends StatefulWidget {
  const TodoPanel({super.key, required this.todos, required this.i18n});

  final List<TodoItem> todos;
  final DshI18n i18n;

  @override
  State<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends State<TodoPanel> {
  bool _collapsed = true;

  String _c(String key) => widget.i18n.t('conversation', key);

  DshStateDotState _dot(String status) => switch (status) {
    'completed' => DshStateDotState.done,
    'in_progress' => DshStateDotState.ongoing,
    _ => DshStateDotState.idle,
  };

  String _statusLabel(String status) => switch (status) {
    'completed' => _c('todo.status.completed'),
    'in_progress' => _c('todo.status.inProgress'),
    _ => _c('todo.status.pending'),
  };

  @override
  Widget build(BuildContext context) {
    final todos = widget.todos;
    if (todos.isEmpty) return const SizedBox.shrink();
    final theme = context.dsh;
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final base = theme.textStyle('--dsw-font-xs-13');
    final header = GestureDetector(
      key: const ValueKey('todo-header'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _collapsed = !_collapsed),
      child: Row(
        children: [
          // dsh's checklist and chevron artworks default to 14px (viewBox 16).
          DshIcon(DshIcons.checklist, color: tertiary),
          const SizedBox(width: 10),
          DshChromeText(
            _c('todo.title'),
            style: base.copyWith(
              height: 24 / 13,
              fontWeight: FontWeight.w500,
              color: theme.labelPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DshChromeText(
              todoProgressLabel(todos, widget.i18n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: base.copyWith(height: 20 / 13, color: tertiary),
            ),
          ),
          const SizedBox(width: 10),
          DshIcon(
            _collapsed ? DshIcons.chevronUp : DshIcons.chevronDown,
            color: tertiary,
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      label: _c('todo.title'),
      child: DshShadowBox(
        key: const ValueKey('todo-panel'),
        color: blendLikeChromium(
          theme.color('--dsw-specific-menu'),
          // `backdrop-filter: blur(40px) saturate(150%)` over the flat page.
          saturateLikeChromium(theme.bgBase, 1.5),
        ),
        radius: theme.radiusLg,
        // dsh's `.root` rebinds the stroke colour to the l1 border token, so
        // the 0.5px ring is the hairline border, not the 16-20% stroke the
        // resolved `--dsw-elevation-panel` token carries.
        shadows: [
          for (final (i, s) in theme.boxShadow('--dsw-elevation-panel').indexed)
            i == 0
                ? BoxShadow(
                    color: theme.color('--dsw-alias-border-l1'),
                    spreadRadius: s.spreadRadius,
                  )
                : s,
        ],
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (!_collapsed) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < todos.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        Row(
                          key: ValueKey('todo-item-$i'),
                          children: [
                            Semantics(
                              label: _statusLabel(todos[i].status),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: Center(
                                  child: DshStateDot(_dot(todos[i].status)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DshChromeText(
                                todos[i].content,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: base.copyWith(
                                  height: 20 / 13,
                                  color: theme.labelSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders the session's `todos` projection (nothing while it is empty).
class TodoDock extends StatefulWidget {
  const TodoDock({super.key, required this.owner, required this.i18n});

  final SessionOwner owner;
  final DshI18n i18n;

  @override
  State<TodoDock> createState() => _TodoDockState();
}

class _TodoDockState extends State<TodoDock> {
  late final StreamSubscription<Object?> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.owner.session.projections.changes.listen(
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todos = todosOf(widget.owner.session.projections.get('todos'));
    if (todos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.md,
        0,
        DshSpace.md,
        DshSpace.sm,
      ),
      child: TodoPanel(todos: todos, i18n: widget.i18n),
    );
  }
}
