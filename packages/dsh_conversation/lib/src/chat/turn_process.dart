import '../contract.dart';
import '../event.dart';
import 'definitions.dart';
import 'nodes.dart';
import 'projection.dart';

/// Turn-owned process range; the final reply remains outside this range.
class TurnProcessData {
  const TurnProcessData({
    required this.turn,
    required this.controlAnchorSeq,
    required this.processStartSeq,
    required this.answerAnchorSeq,
    required this.answerStep,
    required this.inlineReasoning,
    required this.messageCount,
    required this.toolCallCount,
    required this.subagentCount,
  });
  final int turn;
  final num controlAnchorSeq, processStartSeq;
  final num? answerAnchorSeq;
  final int? answerStep;
  final bool inlineReasoning;
  final int messageCount, toolCallCount, subagentCount;
}

bool hasAssistantReply(List<AssistantBlock> blocks) => blocks.any(
  (b) => switch (b) {
    TextBlock(:final text) => text.trim().isNotEmpty,
    ReasoningBlock() || ToolCallRefBlock() => false,
    _ => true,
  },
);

bool isSubagentDelegation(String name) =>
    name == 'subagent' || name.startsWith('subagent_');

TurnLocation? owningTurn(ConversationLocation location) => switch (location) {
  TurnScopedLocation(:final turn) || StepScopedLocation(:final turn) => turn,
  _ => null,
};

bool turnProcessAlwaysOpen(ViewNode node) {
  final turn = owningTurn(node.location);
  final reason = asRecord(turn?.end?.data['reason'])?['kind'];
  return turn?.status == BoundaryStatus.open ||
      const {'aborted', 'interrupted', 'error'}.contains(reason);
}

class _ProcessState {
  const _ProcessState({
    required this.turn,
    this.assistantStarts = const {},
    this.messages = const {},
    this.otherStart,
    this.controlAnchor,
    this.toolCalls = 0,
    this.subagents = 0,
  });
  final int turn, toolCalls, subagents;
  final Map<int, num> assistantStarts;
  final Map<int, int> messages;
  final num? otherStart, controlAnchor;

  _ProcessState apply(ConvEvent event) {
    var starts = assistantStarts, counts = messages;
    var other = otherStart, anchor = controlAnchor;
    var tools = toolCalls, agents = subagents;
    final step = event.data['step'] as int?;
    if (event.type == 'assistant/message' && event.isAppendSurface) {
      final blocks = toAssistantBlocks(
        asRecord(event.data['message'])?['content'],
      );
      if (step != null && hasAssistantReply(blocks)) {
        counts = {...counts, step: (counts[step] ?? 0) + 1};
      }
    }
    if (event.type == 'tool/call') {
      if (isSubagentDelegation(event.data['name'] as String)) {
        agents++;
      } else {
        tools++;
      }
    }
    if (event.type == 'tool/call' ||
        (event.type == 'tool/result' && event.isAppendSurface) ||
        event.type == 'llm/retry') {
      if (other == null) {
        other = event.seq;
        anchor = anchor == null || event.seq < anchor ? event.seq : anchor;
      }
    } else if (step != null &&
        _visibleAssistant(event) &&
        !starts.containsKey(step)) {
      starts = {...starts, step: event.seq};
      anchor = anchor == null || event.seq < anchor ? event.seq : anchor;
    }
    return _ProcessState(
      turn: turn,
      assistantStarts: starts,
      messages: counts,
      otherStart: other,
      controlAnchor: anchor,
      toolCalls: tools,
      subagents: agents,
    );
  }
}

bool _visibleAssistant(ConvEvent event) {
  bool visible(AssistantBlock block) => switch (block) {
    TextBlock(:final text) ||
    ReasoningBlock(:final text) => text.trim().isNotEmpty,
    ToolCallRefBlock() => false,
    _ => true,
  };
  if (event.type == 'assistant/message' && event.isAppendSurface) {
    return toAssistantBlocks(asRecord(event.data['message'])?['content'])
        .any(visible);
  }
  if (event.type != 'assistant/live-chunk') return false;
  final chunk = asRecord(event.data['chunk']);
  switch (chunk?['type']) {
    case 'text-delta' || 'reasoning-delta':
      return (chunk?['text'] as String? ?? '').trim().isNotEmpty;
    case 'block-start':
      return !const {
        'text',
        'reasoning',
        'tool-call',
      }.contains(chunk?['blockType']);
    case 'block-end':
      return visible(toAssistantBlock(chunk?['block']));
    default:
      return false;
  }
}

/// Port of dsh's turnProcessDefinition. Location data is published after Step
/// data, so answer selection reads the actual settled last Assistant Step.
class TurnProcessDefinition extends ConversationDefinition {
  const TurnProcessDefinition();
  @override
  String get kind => 'turn-process';
  @override
  String? get target => chatTarget;
  @override
  Set<String>? get eventTypes => const {
    'turn/start',
    'assistant/live-chunk',
    'assistant/message',
    'tool/call',
    'tool/result',
    'llm/retry',
    'step/start',
    'step/end',
    'turn/end',
  };
  @override
  MatchResult? match(ConvEvent event) {
    final turn = event.data['turn'];
    if (turn is! num) return null;
    return MatchResult(
      '$turn',
      event.type == 'turn/start' ? MatchRole.start : MatchRole.update,
    );
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => _ProcessState(turn: (match.event.data['turn'] as num).toInt());
  @override
  Object update(NodeContext context, ConversationMatch match) =>
      (context.state! as _ProcessState).apply(match.event);
  @override
  Publication publication(ConversationMatch match) {
    if (match.event.type != 'assistant/live-chunk') {
      return Publication.immediate;
    }
    final type = asRecord(match.event.data['chunk'])?['type'];
    return type == 'usage' || type == 'finish'
        ? Publication.none
        : Publication.animationFrame;
  }

  @override
  LocationData? buildLocationData(
    NodeContext context,
    LocationScope scope,
    LocationData? previous,
  ) {
    if (scope != LocationScope.turn) return null;
    final turn = owningTurn(
      context.start?.location ?? context.matches.last.location,
    );
    if (turn == null) return null;
    var state = context.state as _ProcessState?;
    if (state == null) {
      state = _ProcessState(turn: turn.turn);
      for (final match in context.matches) {
        state = state!.apply(match.event);
      }
    }
    final anchor = state!.controlAnchor ?? turn.start?.seq;
    if (anchor == null) return null;
    final candidate =
        turn.steps.lastOrNull?.data.get('assistant-step') as AssistantData?;
    final answer =
        candidate?.finalNode != null &&
            hasAssistantReply(candidate!.blocks) &&
            !candidate.blocks.any((b) => b is ToolCallRefBlock)
        ? candidate
        : null;
    final external = [
      if (state.otherStart != null) state.otherStart!,
      for (final entry in state.assistantStarts.entries)
        if (answer != null && entry.key < answer.step) entry.value,
    ]..sort();
    final data = TurnProcessData(
      turn: turn.turn,
      controlAnchorSeq: anchor,
      processStartSeq: answer == null
          ? anchor
          : turn.start?.seq ?? external.firstOrNull ?? answer.finalNode!.seq,
      answerAnchorSeq: answer?.finalNode?.seq,
      answerStep: answer?.step,
      inlineReasoning:
          answer?.blocks.any(
            (b) => b is ReasoningBlock && b.text.trim().isNotEmpty,
          ) ??
          false,
      messageCount: state.messages.entries
          .where((e) => answer == null || e.key < answer.step)
          .fold(0, (n, e) => n + e.value),
      toolCallCount: state.toolCalls,
      subagentCount: state.subagents,
    );
    return LocationData.turn(turn: turn.turn, key: kind, value: data);
  }

  @override
  ViewNode? buildViewNode(NodeContext context) {
    final turn = owningTurn(
      context.start?.location ?? context.matches.last.location,
    );
    final data = turn?.data.get(kind) as TurnProcessData?;
    if (data == null) return null;
    return chatNode(
      context,
      kind,
      data.controlAnchorSeq + ChatSeqOffsets.processControl,
      data,
      groupTree: 'turn',
    );
  }
}
