import '../contract.dart';
import '../event.dart';
import '../registry.dart';

/// Target holding the recorded todo list preceding each todo call.
const todoHistoryTarget = 'tool-todo-history';

/// One item of a `todo_write` list.
class TodoItem {
  const TodoItem(this.content, this.status);
  final String content;

  /// `pending`, `in_progress` or `completed`.
  final String status;
}

/// The durable list preceding one tool invocation; `todos` is null before the
/// first loaded write (dsh `TodoBaseline`).
class TodoBaseline {
  const TodoBaseline(this.todos);
  final List<TodoItem>? todos;
}

/// Session-owned call lookup (dsh `TodoHistory`).
class TodoHistory {
  const TodoHistory(this._calls);
  static const empty = TodoHistory({});
  final Map<String, TodoBaseline> _calls;

  /// The predecessor of a root or nested call, when its start is loaded.
  TodoBaseline? get(String callId) => _calls[callId];

  int get length => _calls.length;
}

List<TodoItem> _items(Object? todos) => [
  if (todos is List)
    for (final t in todos)
      if (t is Map<String, Object?>)
        TodoItem('${t['content']}', '${t['status']}'),
];

/// Durable writes, indexed independently of tool success receipts (dsh
/// `todoWriteDefinition`): a state-only Context per `todo/write` event.
class TodoWriteDefinition extends ConversationDefinition {
  const TodoWriteDefinition();
  @override
  String get kind => 'tool-todo-write';
  @override
  Set<String>? get eventTypes => const {'todo/write'};
  @override
  MatchResult? match(ConvEvent event) => event.type == 'todo/write'
      ? MatchResult(seqText(event.seq), MatchRole.start)
      : null;
  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => _items(match.event.data['todos']);
  @override
  Object update(NodeContext context, ConversationMatch match) => context.state!;
  @override
  Publication publication(ConversationMatch match) => Publication.none;
}

/// Invocation predecessors, repaired by the assembler when older history
/// arrives (dsh `todoCallDefinition`).
class TodoCallDefinition extends ConversationDefinition {
  const TodoCallDefinition();
  @override
  String get kind => 'tool-todo-call';
  @override
  String? get target => todoHistoryTarget;
  @override
  Set<String>? get eventTypes => const {'tool/call', 'tool/ptc-dispatch-start'};
  @override
  MatchResult? match(ConvEvent event) {
    if (event.type == 'tool/call' && event.data['name'] == 'todo_write') {
      return MatchResult('${event.data['callId']}', MatchRole.start);
    }
    if (event.type == 'tool/ptc-dispatch-start' &&
        event.data['name'] == 'todo_write') {
      return MatchResult('${event.data['subCallId']}', MatchRole.start);
    }
    return null;
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => TodoBaseline(
    reader.previous('tool-todo-write')?.state as List<TodoItem>?,
  );

  @override
  Object update(NodeContext context, ConversationMatch match) => context.state!;

  @override
  ViewNode? buildViewNode(NodeContext context) {
    final state = context.state;
    if (state == null) return null;
    return ViewNode(
      key: context.key,
      kind: kind,
      id: context.id,
      target: todoHistoryTarget,
      anchorSeq: context.start?.event.seq ?? 0,
      location: context.location,
      visible: true,
      data: state,
    );
  }
}

class _TodoHistoryBuilder extends ConversationViewBuilder {
  Map<String, TodoBaseline> _calls = {};

  @override
  TodoHistory replace(List<ViewNode> nodes, ConversationTimeline timeline) {
    _calls = {for (final n in nodes) n.id: n.data! as TodoBaseline};
    return TodoHistory(_calls);
  }

  @override
  TodoHistory apply(List<ViewNode> upserts, ConversationTimeline timeline) {
    if (upserts.isNotEmpty) {
      _calls = {
        ..._calls,
        for (final n in upserts) n.id: n.data! as TodoBaseline,
      };
    }
    return TodoHistory(_calls);
  }
}

/// Incremental lookup snapshots preserve earlier call baselines across later
/// writes (dsh `todoHistoryView`).
class TodoHistoryViewDefinition extends ConversationViewDefinition {
  @override
  String get target => todoHistoryTarget;
  @override
  ConversationViewBuilder create() => _TodoHistoryBuilder();
}
