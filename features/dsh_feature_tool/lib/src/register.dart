import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'model/ask_model.dart';
import 'model/row_model.dart';
import 'toolviews.dart';

/// `conversation.chat.node` as this feature uses it.
final Slot<ChatNodeOwner, Widget> chatNodeSlot = DshSlots.conversationChatNode
    .typed<ChatNodeOwner, Widget>();

/// `tool.call.toolview` as this feature uses it.
final Slot<ToolViewOwner, Widget> toolViewSlot = DshSlots.toolCallToolview
    .typed<ToolViewOwner, Widget>();

/// Occupy `conversation.chat.node[tool-call]` and the built-in entries of
/// `tool.call.toolview` (dsh `ui-tool`): the chat renders a tool row by asking
/// the slot for a view keyed by the tool's wire name, falling back to the
/// generic card. Other features may register further keys.
void registerToolFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  ToolHostActions actions = const ToolHostActions(),
  bool Function(String callId)? expandedByDefault,
}) {
  ToolContext context(ToolViewOwner owner) => ToolContext(
    owner,
    ToolEnv(
      i18n: i18n(),
      actions: actions,
      expandedByDefault: expandedByDefault,
    ),
  );

  void view(
    Iterable<String> names,
    Widget Function(ToolViewOwner owner, ToolContext c) build,
  ) {
    for (final name in names) {
      slots.register<ToolViewOwner, Widget>(
        toolViewSlot,
        (owner) => build(owner, context(owner)),
        key: name,
      );
    }
  }

  view(const ['bash', 'pwsh'], (_, c) => bashView(c));
  view(const ['read'], (_, c) => readView(c));
  view(const ['read_image'], (_, c) => readImageView(c));
  view(const ['edit', 'write'], (_, c) => mutationView(c));
  view(const ['grep', 'glob'], (_, c) => searchView(c));
  view(const ['web_search', 'web_fetch'], (_, c) => webView(c));
  view(const ['todo_write'], (owner, c) => _TodoView(owner: owner, context: c));
  view(const [
    'ask_user_question',
  ], (owner, c) => _AskView(owner: owner, context: c));
  view(detailsTools, (_, c) => detailsView(c));

  slots.register<ChatNodeOwner, Widget>(chatNodeSlot, (owner) {
    final data = owner.node.data as ToolData;
    return ToolCallTree(
      call: data.root,
      owner: owner.session,
      slots: slots,
      context: context,
    );
  }, key: 'tool-call');
}

/// One root call with its recursive sub-calls (dsh `ToolCallTree`): every call
/// dispatches through the keyed slot; children indent under a hairline.
class ToolCallTree extends StatelessWidget {
  const ToolCallTree({
    super.key,
    required this.call,
    required this.owner,
    required this.slots,
    required this.context,
  });

  final ToolCall call;
  final SessionOwner owner;
  final SlotRegistry slots;
  final ToolContext Function(ToolViewOwner) context;

  @override
  Widget build(BuildContext buildContext) {
    final toolOwner = ToolViewOwner(session: owner, call: call);
    final c = context(toolOwner);
    final denied =
        call is ToolResult &&
        toolRowModel(call.name, call).autoReviewDenial != null;
    final row = denied
        ? genericView(c)
        : slots.renderKeyed(toolViewSlot, call.name, toolOwner) ??
              genericView(c);
    final children = call is PreparingToolCall
        ? const <ToolCall>[]
        : call.subCalls;
    if (children.isEmpty) return row;
    final theme = buildContext.dsh;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        Container(
          key: const ValueKey('sub-calls'),
          margin: const EdgeInsets.fromLTRB(22, 4, 0, 2),
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.color('--dsw-alias-border-l2'),
                width: dshHairline,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 4),
                ToolCallTree(
                  key: ValueKey('call-${children[i].callId}'),
                  call: children[i],
                  owner: owner,
                  slots: slots,
                  context: context,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Rebuilds [builder] when any of [streams] emits.
class _Rebuild extends StatefulWidget {
  const _Rebuild({required this.streams, required this.builder});

  final List<Stream<Object?>> streams;
  final WidgetBuilder builder;

  @override
  State<_Rebuild> createState() => _RebuildState();
}

class _RebuildState extends State<_Rebuild> {
  final List<StreamSubscription<Object?>> _subs = [];

  @override
  void initState() {
    super.initState();
    for (final s in widget.streams) {
      _subs.add(s.listen((_) => setState(() {})));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

class _TodoView extends StatelessWidget {
  const _TodoView({required this.owner, required this.context});

  final ToolViewOwner owner;
  final ToolContext context;

  @override
  Widget build(BuildContext buildContext) {
    final binding = owner.session.conversation;
    final session = owner.session.session;
    return _Rebuild(
      streams: [binding.todoHistory.changes, session.snapshot.changes],
      builder: (_) => todoView(
        context,
        binding.todoHistory.value,
        session.snapshot.value.hasMore,
      ),
    );
  }
}

class _AskView extends StatelessWidget {
  const _AskView({required this.owner, required this.context});

  final ToolViewOwner owner;
  final ToolContext context;

  @override
  Widget build(BuildContext buildContext) {
    final projections = owner.session.session.projections;
    final callId = owner.call.callId;
    return _Rebuild(
      streams: [projections.changes],
      builder: (_) {
        final view = projections.get('userQuestions');
        final active = view is Map && view['active'] is List
            ? (view['active'] as List).whereType<Map<String, Object?>>().any(
                (r) => r['callId'] == callId,
              )
            : false;
        List<AskAnswer>? settled;
        if (view is Map && view['settled'] is List) {
          for (final row
              in (view['settled'] as List).whereType<Map<String, Object?>>()) {
            if (row['callId'] == callId && row['answers'] is List) {
              settled = [
                for (final a
                    in (row['answers'] as List)
                        .whereType<Map<String, Object?>>())
                  AskAnswer('${a['id']}', [
                    if (a['selected'] is List)
                      for (final s in a['selected'] as List) '$s',
                  ], a['custom'] as String?),
              ];
            }
          }
        }
        return askView(context, answerable: active, settledAnswers: settled);
      },
    );
  }
}
