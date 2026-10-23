import 'dart:convert';

import '../contract.dart';
import '../event.dart';
import 'nodes.dart';
import 'partial_arguments.dart';
import 'projection.dart';

const chatTarget = 'chat';

/// Relative positions in one durable event's seq neighbourhood (dsh
/// `CHAT_SYNTHETIC_SEQ_OFFSETS`).
abstract final class ChatSeqOffsets {
  static const interruptedAssistant = -0.9;
  static const interruptedFollowup = -0.8;
  static const processControl = -0.1;
  static const maxTokensNotice = 0.05;
  static const finalizedFollowup = 0.1;
}

/// A final chat node: [ViewNode] on the `chat` target.
ViewNode chatNode(
  NodeContext context,
  String kind,
  num anchorSeq,
  Object? data, {
  ConversationLocation? location,
  bool visible = true,
  String? groupTree,
}) => ViewNode(
  key: context.key,
  kind: kind,
  id: context.id,
  target: chatTarget,
  anchorSeq: anchorSeq,
  location: location ?? context.location,
  visible: visible,
  data: data,
  groupTree: groupTree,
);

// ---- inbox ------------------------------------------------------------

class InboxIdentity {
  const InboxIdentity(this.id, this.sourceKind);
  final String id;
  final String? sourceKind;
}

/// Persistent Inbox state after one durable Inbox splice (dsh `InboxState`).
class InboxState {
  const InboxState({
    required this.pending,
    required this.currentClaimed,
    required this.claimSeq,
    required this.claimedHuman,
  });
  final List<InboxIdentity> pending;
  final Set<String> currentClaimed;
  final num claimSeq;
  final bool claimedHuman;
}

List<InboxIdentity> _identities(Object? list) => [
  if (list is List)
    for (final m in list)
      if (m is Map<String, Object?>)
        InboxIdentity('${m['id']}', asRecord(m['source'])?['kind'] as String?),
];

/// Array#splice on a copy: removes up to [removed] from [start] and inserts.
List<InboxIdentity> _splice(
  List<InboxIdentity> list,
  int start,
  int removed,
  List<InboxIdentity> inserted, [
  List<InboxIdentity>? removedOut,
]) {
  final copy = [...list];
  final s = start < 0
      ? (copy.length + start).clamp(0, copy.length)
      : start.clamp(0, copy.length);
  final end = (s + removed).clamp(s, copy.length);
  removedOut?.addAll(copy.sublist(s, end));
  copy.replaceRange(s, end, inserted);
  return copy;
}

InboxState _applySplice(
  PreviousContext? previous,
  Map<String, Object?> splice,
  num seq,
) {
  final prior = previous?.state as InboxState?;
  final priorPending = prior?.pending ?? const <InboxIdentity>[];
  final inserted = _identities(splice['inserted']);
  final removedCount = coordinate(splice['removedCount']) ?? 0;
  final start = (splice['start'] as num?)?.truncate() ?? 0;
  if (removedCount > 0 && splice['outcome'] != 'canceled') {
    final removed = <InboxIdentity>[];
    final pending = _splice(
      priorPending,
      start,
      removedCount,
      inserted,
      removed,
    );
    return InboxState(
      pending: pending,
      currentClaimed: {for (final r in removed) r.id},
      claimSeq: seq,
      claimedHuman: removed.any((m) => m.sourceKind == 'user'),
    );
  }
  var claimed = prior?.currentClaimed ?? const <String>{};
  if (inserted.any((m) => claimed.contains(m.id))) {
    claimed = {...claimed}..removeAll(inserted.map((m) => m.id));
  }
  return InboxState(
    pending: _splice(priorPending, start, removedCount, inserted),
    currentClaimed: claimed,
    claimSeq: prior?.claimSeq ?? -1,
    claimedHuman: prior?.claimedHuman ?? false,
  );
}

/// Persistent claims of one inbox target (dsh `inboxDefinition`).
class InboxDefinition extends ConversationDefinition {
  InboxDefinition(this.target_) : kind = 'inbox-$target_';
  final String target_;
  @override
  final String kind;
  @override
  Set<String>? get eventTypes => null;

  @override
  MatchResult? match(ConvEvent event) =>
      event.type == 'agent/inbox/spliced' && event.data['target'] == target_
      ? MatchResult(seqText(event.seq), MatchRole.start)
      : null;

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => _applySplice(reader.previous(kind), match.event.data, match.event.seq);

  @override
  Object update(NodeContext context, ConversationMatch match) => context.state!;

  @override
  Publication publication(ConversationMatch match) => Publication.none;
}

// ---- messages -----------------------------------------------------------

bool _isCompactionCheckpoint(ConvEvent e) =>
    e.type == 'user/message' &&
    e.isReplacementSurface &&
    asRecord(e.data['source'])?['kind'] == 'compact-checkpoint';

MessageData _contextMessage(
  ConvEvent e,
  Map<String, Object?> message, {
  bool waking = false,
}) {
  final source = asRecord(message['source']);
  final producer = contextProducer(source);
  return MessageData(
    kind: 'context',
    seq: e.seq,
    time: e.time,
    content: (message['content'] as List?)?.cast<Object?>() ?? const [],
    source: source,
    producerRole: producer.role,
    producerLabel: producer.label,
    form: contextForm(source),
    waking: waking,
  );
}

/// User, steering, and injected-context message classification (dsh
/// `messageDefinition`, kind `input-message`).
class MessageDefinition extends ConversationDefinition {
  const MessageDefinition({this.developer = false});
  final bool developer;

  @override
  String get kind => developer ? 'developer-message' : 'input-message';
  @override
  String? get target => chatTarget;
  @override
  Set<String>? get eventTypes => {
    developer ? 'developer/message' : 'user/message',
  };

  @override
  MatchResult? match(ConvEvent event) {
    if (developer) {
      if (event.type != 'developer/message') return null;
      final m = asRecord(event.data['message']);
      return MatchResult('${m?['id']}', MatchRole.start);
    }
    if (event.type == 'user/message') {
      return event.isAppendSurface && !_isCompactionCheckpoint(event)
          ? MatchResult('${event.data['id']}', MatchRole.start)
          : null;
    }
    return null;
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) {
    final e = match.event;
    if (developer) {
      return _contextMessage(e, asRecord(e.data['message']) ?? const {});
    }
    final data = e.data;
    final source = asRecord(data['source']);
    final id = '${data['id']}';
    if (source?['kind'] != 'user') {
      final nextTurn = reader.previous('inbox-next-turn')?.state as InboxState?;
      final nextStep = reader.previous('inbox-next-step')?.state as InboxState?;
      final location = match.location;
      final turnStart = location is StepScopedLocation
          ? location.turn.start?.seq
          : null;
      // An idle steer opens Step 1 without a next-turn claim in this Turn.
      final idleSteer =
          location is StepScopedLocation &&
          location.step.step == 1 &&
          turnStart != null &&
          (nextStep?.claimSeq ?? -1) > turnStart &&
          (nextTurn?.claimSeq ?? -1) < turnStart &&
          nextStep?.claimedHuman == false &&
          nextStep!.currentClaimed.contains(id);
      return _contextMessage(
        e,
        data,
        waking: (nextTurn?.currentClaimed.contains(id) ?? false) || idleSteer,
      );
    }
    final claimed =
        (reader.previous('inbox-next-step')?.state as InboxState?)
            ?.currentClaimed
            .contains(id) ??
        false;
    return MessageData(
      kind: claimed ? 'steering' : 'user',
      messageId: id,
      seq: e.seq,
      time: e.time,
      content: (data['content'] as List?)?.cast<Object?>() ?? const [],
      source: source,
    );
  }

  @override
  Object update(NodeContext context, ConversationMatch match) => context.state!;

  @override
  ViewNode? buildViewNode(NodeContext context) {
    final state = context.state as MessageData?;
    if (state == null) return null;
    final waking =
        state.kind == 'context' &&
        context.start?.event.type == 'user/message' &&
        state.waking;
    final location = context.location;
    final human = state.kind == 'user' || state.kind == 'steering';
    final opensExchange =
        human && location is StepScopedLocation && location.step.step == 1;
    return chatNode(
      context,
      waking ? 'turn-trigger' : state.kind,
      state.seq,
      state,
      location: location,
      groupTree: opensExchange
          ? 'exchange'
          : (human || waking)
          ? 'input'
          : null,
    );
  }
}

/// Claims `system/message` and surface replacements so the unknown fallback
/// never shows them. dsh renders a system-prompt card here; chat hides those
/// rows (`isVisibleChatNode`), and the card itself is deferred, so this
/// Definition builds no node.
class SystemMessageDefinition extends ConversationDefinition {
  const SystemMessageDefinition();
  @override
  String get kind => 'system-message';
  @override
  String? get target => chatTarget;

  @override
  MatchResult? match(ConvEvent event) =>
      event.type == 'system/message' ||
          (event.entry.event.containsKey('surfaceOp') &&
              event.surfaceOp != 'append')
      ? MatchResult(seqText(event.seq), MatchRole.start)
      : null;

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => const Object();

  @override
  Object update(NodeContext context, ConversationMatch match) => context.state!;
}

// ---- assistant ------------------------------------------------------------

class _AssistantState {
  const _AssistantState({
    required this.turn,
    required this.step,
    this.blocks = const [],
    this.visibleBlocks = 0,
    this.firstVisibleSeq,
    this.firstVisibleTime,
    this.firstTokenTime,
    this.finalMatch,
    this.usage,
  });
  final int turn;
  final int step;
  final List<AssistantBlock?> blocks;
  final int visibleBlocks;
  final num? firstVisibleSeq;
  final num? firstVisibleTime;
  final num? firstTokenTime;
  final ConversationMatch? finalMatch;
  final Object? usage;

  _AssistantState copy({
    List<AssistantBlock?>? blocks,
    int? visibleBlocks,
    num? firstVisibleSeq,
    num? firstVisibleTime,
    num? firstTokenTime,
    ConversationMatch? finalMatch,
    Object? usage,
    bool setUsage = false,
  }) => _AssistantState(
    turn: turn,
    step: step,
    blocks: blocks ?? this.blocks,
    visibleBlocks: visibleBlocks ?? this.visibleBlocks,
    firstVisibleSeq: firstVisibleSeq ?? this.firstVisibleSeq,
    firstVisibleTime: firstVisibleTime ?? this.firstVisibleTime,
    firstTokenTime: firstTokenTime ?? this.firstTokenTime,
    finalMatch: finalMatch ?? this.finalMatch,
    usage: setUsage ? usage : this.usage,
  );
}

List<AssistantBlock> _compact(List<AssistantBlock?> blocks) => [
  for (final b in blocks)
    if (b != null) b,
];

bool _blockVisible(AssistantBlock? b) => switch (b) {
  null || ToolCallRefBlock() => false,
  TextBlock(:final text) || ReasoningBlock(:final text) => text.trim() != '',
  _ => true,
};

bool _hasVisibleContent(List<AssistantBlock> blocks) =>
    blocks.any(_blockVisible);

bool _hasInterruptionEvidence(List<AssistantBlock> blocks) => blocks.any(
  (b) => switch (b) {
    TextBlock(:final text) || ReasoningBlock(:final text) => text.trim() != '',
    _ => true,
  },
);

_AssistantState _resetForRetry(_AssistantState s) => _AssistantState(
  turn: s.turn,
  step: s.step,
  firstTokenTime: s.firstTokenTime,
);

_AssistantState _updateChunk(
  _AssistantState state,
  Map<String, Object?> chunk,
  num seq,
  num time,
) {
  final type = chunk['type'];
  final index = (chunk['index'] as num?)?.toInt() ?? 0;
  AssistantBlock? previousAt(List<AssistantBlock?> bl) =>
      index < bl.length ? bl[index] : null;
  if (type == 'tool-call-delta') {
    final previous = previousAt(state.blocks);
    if (previous is ToolCallRefBlock &&
        previous.callId != '' &&
        (chunk['name'] == null || chunk['name'] == previous.name) &&
        (state.firstTokenTime != null || !isTokenDelta(chunk))) {
      return state;
    }
  }
  final blocks = [...state.blocks];
  void put(AssistantBlock b) {
    while (blocks.length <= index) {
      blocks.add(null);
    }
    blocks[index] = b;
  }

  var previousVisible = false;
  switch (type) {
    case 'block-start':
      previousVisible = _blockVisible(previousAt(blocks));
      put(emptyAssistantBlock(chunk['blockType']));
    case 'text-delta':
      final p = previousAt(blocks);
      previousVisible = _blockVisible(p);
      put(
        TextBlock((p is TextBlock ? p.text : '') + (chunk['text'] as String)),
      );
    case 'reasoning-delta':
      final p = previousAt(blocks);
      previousVisible = _blockVisible(p);
      put(
        ReasoningBlock(
          (p is ReasoningBlock ? p.text : '') + (chunk['text'] as String),
        ),
      );
    case 'tool-call-delta':
      final p = previousAt(blocks);
      previousVisible = _blockVisible(p);
      final prevId = p is ToolCallRefBlock ? p.callId : '';
      put(
        ToolCallRefBlock(
          callId: prevId != '' ? prevId : '${chunk['id']}',
          name:
              (chunk['name'] as String?) ??
              (p is ToolCallRefBlock ? p.name : ''),
          argsRaw: p is ToolCallRefBlock ? p.argsRaw : '',
        ),
      );
    case 'block-end':
      previousVisible = _blockVisible(previousAt(blocks));
      put(toAssistantBlock(chunk['block']));
    case 'usage':
      return state.copy(usage: chunk['usage'], setUsage: true);
    default:
      return state;
  }
  final visibleBlocks =
      state.visibleBlocks -
      (previousVisible ? 1 : 0) +
      (_blockVisible(previousAt(blocks)) ? 1 : 0);
  final firstToken = isTokenDelta(chunk);
  return state.copy(
    blocks: blocks,
    visibleBlocks: visibleBlocks,
    firstVisibleSeq: visibleBlocks > 0 && state.firstVisibleSeq == null
        ? seq
        : null,
    firstVisibleTime: visibleBlocks > 0 && state.firstVisibleSeq == null
        ? time
        : null,
    firstTokenTime: firstToken && state.firstTokenTime == null ? time : null,
  );
}

_AssistantState _settleMessage(_AssistantState state, ConversationMatch match) {
  final message = asRecord(match.event.data['message']);
  final blocks = toAssistantBlocks(message?['content']);
  return state.copy(
    blocks: blocks,
    visibleBlocks: blocks.where(_blockVisible).length,
    finalMatch: match,
    usage: match.event.data['usage'],
    setUsage: true,
  );
}

AssistantMessage? _finalNode(_AssistantState state, NodeContext context) {
  final fin = state.finalMatch;
  if (fin != null && fin.event.type == 'assistant/message') {
    final e = fin.event;
    final message = asRecord(e.data['message']);
    return AssistantMessage(
      seq: e.seq,
      messageId: message?['id'] == null ? null : '${message!['id']}',
      time: e.time,
      turn: state.turn,
      step: state.step,
      blocks: toAssistantBlocks(message?['content']),
      usage: e.data['usage'],
      stepStartTime: context.start?.event.time,
      firstTokenTime: state.firstTokenTime,
      completedTime: e.time,
      interrupted: e.data['interrupted'] == true,
    );
  }
  final location =
      context.start?.location ?? context.matches.lastOrNull?.location;
  final boundary = location == null ? null : closedBoundary(location);
  if (boundary == null) return null;
  final blocks = _compact(state.blocks);
  if (!_hasInterruptionEvidence(blocks)) return null;
  return AssistantMessage(
    seq: boundary.seq + ChatSeqOffsets.interruptedAssistant,
    time: boundary.time,
    turn: state.turn,
    step: state.step,
    blocks: blocks,
    interrupted: true,
  );
}

_AssistantState? _assistantFallback(NodeContext context) {
  _AssistantState? state;
  for (final match in context.matches) {
    final e = match.event;
    if (e.type == 'assistant/live-chunk') {
      state ??= _AssistantState(
        turn: coordinate(e.data['turn']) ?? 0,
        step: coordinate(e.data['step']) ?? 0,
      );
      state = _updateChunk(
        state,
        asRecord(e.data['chunk']) ?? const {},
        e.seq,
        e.time,
      );
      continue;
    }
    if (e.type == 'assistant/message') {
      state ??= _AssistantState(
        turn: coordinate(e.data['turn']) ?? 0,
        step: coordinate(e.data['step']) ?? 0,
      );
      state = _settleMessage(state, match);
      continue;
    }
    if (e.type == 'llm/retry' && state != null) state = _resetForRetry(state);
  }
  return state;
}

({AssistantData data, num anchorSeq, bool visible, AssistantMessage? settled})?
_projectAssistant(NodeContext context) {
  final state =
      (context.state as _AssistantState?) ?? _assistantFallback(context);
  if (state == null) return null;
  final settled = _finalNode(state, context);
  final blocks = settled?.blocks ?? _compact(state.blocks);
  final visible = settled == null
      ? state.visibleBlocks > 0
      : _hasVisibleContent(blocks);
  final status = settled?.interrupted == true
      ? 'interrupted'
      : settled == null
      ? 'running'
      : 'settled';
  final anchorSeq =
      (settled?.interrupted == true
          ? settled!.seq
          : state.firstVisibleSeq ?? settled?.seq) ??
      context.matches.firstOrNull?.event.seq ??
      0;
  final time =
      settled?.time ??
      state.firstVisibleTime ??
      context.matches.firstOrNull?.event.time ??
      0;
  return (
    anchorSeq: anchorSeq,
    visible: visible,
    settled: settled,
    data: AssistantData(
      status: status,
      turn: state.turn,
      step: state.step,
      blocks: blocks,
      time: time,
      usage: state.usage,
      finalNode: settled,
    ),
  );
}

AssistantData? _publishedAssistantData(NodeContext context) {
  final location =
      context.start?.location ?? context.matches.lastOrNull?.location;
  return location is StepScopedLocation
      ? location.step.data.get('assistant-step') as AssistantData?
      : null;
}

/// Per-step Assistant lifecycle (dsh `assistantDefinition`).
class AssistantDefinition extends ConversationDefinition {
  const AssistantDefinition();
  @override
  String get kind => 'assistant-step';
  @override
  String? get target => chatTarget;
  @override
  Set<String>? get eventTypes => const {
    'step/start',
    'assistant/live-chunk',
    'assistant/message',
    'llm/retry',
  };

  @override
  MatchResult? match(ConvEvent event) {
    final id =
        '${jsString(event.data, 'turn')}:${jsString(event.data, 'step')}';
    if (event.type == 'step/start') return MatchResult(id, MatchRole.start);
    if (event.type == 'assistant/live-chunk' ||
        (event.type == 'assistant/message' && event.surfaceOp == 'append')) {
      return MatchResult(id, MatchRole.update);
    }
    if (event.type == 'llm/retry') return MatchResult(id, MatchRole.update);
    return null;
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => _AssistantState(
    turn: coordinate(match.event.data['turn']) ?? 0,
    step: coordinate(match.event.data['step']) ?? 0,
  );

  @override
  Object update(NodeContext context, ConversationMatch match) {
    final state = context.state! as _AssistantState;
    final e = match.event;
    if (e.type == 'assistant/live-chunk') {
      return _updateChunk(
        state,
        asRecord(e.data['chunk']) ?? const {},
        e.seq,
        e.time,
      );
    }
    if (e.type == 'assistant/message') return _settleMessage(state, match);
    if (e.type == 'llm/retry') return _resetForRetry(state);
    return state;
  }

  @override
  Publication publication(ConversationMatch match) {
    if (match.event.type == 'step/start') return Publication.none;
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
    if (scope != LocationScope.step) return null;
    final projected = _projectAssistant(context);
    if (projected == null) return null;
    return LocationData.step(
      turn: projected.data.turn,
      step: projected.data.step,
      key: 'assistant-step',
      value: projected.data,
    );
  }

  @override
  ViewNode? buildViewNode(NodeContext context) {
    final current = context.current[chatTarget];
    final state =
        (context.state as _AssistantState?) ?? _assistantFallback(context);
    final data = _publishedAssistantData(context);
    if (state == null || data == null) {
      return current?.hidden();
    }
    final settled = data.finalNode;
    final visible = settled == null
        ? state.visibleBlocks > 0
        : _hasVisibleContent(data.blocks);
    if (settled == null && !visible && current == null) return null;
    final anchorSeq =
        (settled?.interrupted == true
            ? settled!.seq
            : state.firstVisibleSeq ?? settled?.seq) ??
        context.matches.firstOrNull?.event.seq ??
        0;
    return chatNode(
      context,
      'assistant-step',
      anchorSeq,
      data,
      visible: settled?.interrupted == true || visible,
    );
  }
}

// ---- tools ------------------------------------------------------------

String _jsonArguments(Object? v) => jsonEncode(v);

const _maxDepth = 256;

class _ToolState {
  const _ToolState({
    this.root,
    this.children = const {},
    this.parents = const {},
  });
  final ToolCall? root;
  final Map<String, List<ToolCall>> children;
  final Map<String, String> parents;

  _ToolState copy({
    ToolCall? root,
    Map<String, List<ToolCall>>? children,
    Map<String, String>? parents,
  }) => _ToolState(
    root: root ?? this.root,
    children: children ?? this.children,
    parents: parents ?? this.parents,
  );
}

StartedToolCall _rootCall(ConversationMatch match, [ToolCall? previous]) {
  final d = match.event.data;
  final raw = '${d['arguments']}';
  return StartedToolCall(
    callId: '${d['callId']}',
    name: '${d['name']}',
    argsRaw: raw,
    args: previous == null
        ? PartialArguments.fromText(raw)
        : previous.args.settle(raw),
    turn: coordinate(d['turn']) ?? 0,
    step: coordinate(d['step']) ?? 0,
    time: match.event.time,
    subCalls: const [],
  );
}

_ToolState _applyDelta(_ToolState state, ConversationMatch match) {
  final e = match.event;
  if (e.type != 'assistant/live-chunk') return state;
  final chunk = asRecord(e.data['chunk']) ?? const {};
  final root = state.root;
  if (chunk['type'] == 'block-end' &&
      asRecord(chunk['block'])?['type'] == 'tool-call') {
    if (root is! PreparingToolCall) return state;
    final block = asRecord(chunk['block'])!;
    return state.copy(
      root: PreparingToolCall(
        callId: root.callId,
        name: '${block['name']}',
        args: root.args.settle('${block['arguments']}'),
        subCalls: root.subCalls,
        turn: root.turn,
        step: root.step,
        time: root.time,
      ),
    );
  }
  if (chunk['type'] != 'tool-call-delta') return state;
  final delta = (chunk['argumentsDelta'] as String?) ?? '';
  if (root == null) {
    final name = chunk['name'] as String?;
    if (name == null || name.isEmpty) return state;
    final args = PartialArguments()..append(delta);
    return state.copy(
      root: PreparingToolCall(
        callId: '${chunk['id']}',
        name: name,
        turn: coordinate(e.data['turn']) ?? 0,
        step: coordinate(e.data['step']) ?? 0,
        time: e.time,
        subCalls: const [],
        args: args,
      ),
    );
  }
  if (root is! PreparingToolCall || root.args.isSealed) return state;
  root.args.append(delta);
  return state;
}

ToolResult? _rootResult(ConversationMatch match, [StartedToolCall? previous]) {
  if (match.event.type != 'tool/result') return null;
  final d = match.event.data;
  final message = asRecord(d['message']) ?? const {};
  final source = asRecord(message['source']) ?? const {};
  return ToolResult(
    seq: match.event.seq,
    time: match.event.time,
    callId: '${source['callId']}',
    name: previous?.name ?? '',
    args: previous?.args ?? PartialArguments.empty,
    callArgsRaw: previous?.argsRaw,
    callTime: previous?.time,
    content: (message['content'] as List?)?.cast<Object?>() ?? const [],
    isError: message['isError'] == true,
    error: asRecord(d['error']),
    meta: d['meta'],
    subCalls: const [],
  );
}

int _locTurn(ConversationMatch m) => locationTurn(m.location) ?? 0;
int _locStep(ConversationMatch m) => locationStep(m.location) ?? 0;

StartedToolCall _childCall(ConversationMatch match, Map<String, Object?> d) =>
    StartedToolCall(
      callId: '${d['subCallId']}',
      parentCallId: '${d['parentCallId']}',
      name: '${d['name']}',
      argsRaw: _jsonArguments(d['arguments']),
      args: PartialArguments.fromObject(d['arguments']),
      turn: _locTurn(match),
      step: _locStep(match),
      time: match.event.time,
      subCalls: const [],
    );

ToolResult _childResult(
  ConversationMatch match,
  Map<String, Object?> d, [
  ToolCall? previous,
]) => ToolResult(
  seq: match.event.seq,
  time: match.event.time,
  callId: '${d['subCallId']}',
  parentCallId: '${d['parentCallId']}',
  name: '${d['name']}',
  args: previous != null && previous is! ToolResult
      ? previous.args
      : PartialArguments.fromObject(d['arguments']),
  callArgsRaw: _jsonArguments(d['arguments']),
  callTime: previous == null ? null : _callTime(previous),
  content: (d['content'] as List?)?.cast<Object?>() ?? const [],
  meta: d['meta'],
  isError: d['isError'] == true,
  error: asRecord(d['error']),
  subCalls: const [],
);

num? _callTime(ToolCall c) => switch (c) {
  StartedToolCall(:final time) => time,
  PreparingToolCall(:final time) => time,
  ToolResult(:final time) => time,
};

bool _acceptsEdge(_ToolState state, String parent, String child) {
  if (parent == child || state.parents.containsKey(child)) return false;
  String? cursor = parent;
  var parentDepth = 0;
  final ancestors = <String>{};
  while (cursor != null) {
    if (cursor == child || ancestors.contains(cursor)) return false;
    ancestors.add(cursor);
    parentDepth++;
    cursor = state.parents[cursor];
  }
  final pending = [(callId: child, depth: 1)];
  final descendants = <String>{};
  var subtreeDepth = 0;
  for (var i = 0; i < pending.length; i++) {
    final c = pending[i];
    if (!descendants.add(c.callId)) return false;
    if (c.depth > subtreeDepth) subtreeDepth = c.depth;
    for (final nested in state.children[c.callId] ?? const <ToolCall>[]) {
      pending.add((callId: nested.callId, depth: c.depth + 1));
    }
  }
  return parentDepth + subtreeDepth <= _maxDepth;
}

_ToolState _updateDispatch(_ToolState state, ConversationMatch match) {
  final e = match.event;
  if (e.type != 'tool/ptc-dispatch-start' && e.type != 'tool/ptc-dispatch') {
    return state;
  }
  final d = e.data;
  final parentCallId = '${d['parentCallId']}';
  final subCallId = '${d['subCallId']}';
  final siblings = state.children[parentCallId] ?? const <ToolCall>[];
  final index = siblings.indexWhere((c) => c.callId == subCallId);
  if (e.type == 'tool/ptc-dispatch-start') {
    if (index >= 0 || !_acceptsEdge(state, parentCallId, subCallId)) {
      return state;
    }
    return state.copy(
      children: {
        ...state.children,
        parentCallId: [...siblings, _childCall(match, d)],
      },
      parents: {...state.parents, subCallId: parentCallId},
    );
  }
  if (index < 0 && !_acceptsEdge(state, parentCallId, subCallId)) return state;
  final previous = index < 0 ? null : siblings[index];
  final settled = _childResult(match, d, previous);
  return state.copy(
    children: {
      ...state.children,
      parentCallId: index < 0
          ? [...siblings, settled]
          : [
              for (var i = 0; i < siblings.length; i++)
                i == index ? settled : siblings[i],
            ],
    },
    parents: index < 0
        ? {...state.parents, subCallId: parentCallId}
        : state.parents,
  );
}

ToolCall _projectBlock(
  ToolCall block,
  _ToolState state,
  ({num seq, num time})? interruptedAt, [
  Set<String> visited = const {},
  int depth = 1,
]) {
  if (block is PreparingToolCall) return block;
  if (visited.contains(block.callId) || depth > _maxDepth) {
    return _withSubCalls(block, const []);
  }
  final nextVisited = {...visited, block.callId};
  final children = [
    for (final c in state.children[block.callId] ?? block.subCalls)
      _projectBlock(c, state, interruptedAt, nextVisited, depth + 1),
  ];
  if (block is ToolResult || interruptedAt == null) {
    return _withSubCalls(block, children);
  }
  final started = block as StartedToolCall;
  return ToolResult(
    seq: interruptedAt.seq + ChatSeqOffsets.interruptedFollowup,
    time: interruptedAt.time,
    callId: started.callId,
    parentCallId: started.parentCallId,
    name: started.name,
    args: started.args,
    callArgsRaw: started.argsRaw,
    callTime: started.time,
    content: const [],
    isError: true,
    error: const {'name': 'Interrupted', 'code': 'interrupted'},
    subCalls: children,
  );
}

ToolCall _withSubCalls(ToolCall b, List<ToolCall> children) => switch (b) {
  PreparingToolCall() => b,
  StartedToolCall() => StartedToolCall(
    callId: b.callId,
    parentCallId: b.parentCallId,
    name: b.name,
    args: b.args,
    argsRaw: b.argsRaw,
    turn: b.turn,
    step: b.step,
    time: b.time,
    subCalls: children,
  ),
  ToolResult() => ToolResult(
    callId: b.callId,
    parentCallId: b.parentCallId,
    name: b.name,
    args: b.args,
    seq: b.seq,
    time: b.time,
    callArgsRaw: b.callArgsRaw,
    callTime: b.callTime,
    content: b.content,
    isError: b.isError,
    error: b.error,
    meta: b.meta,
    subCalls: children,
  ),
};

({num seq, num time})? _interruption(NodeContext context) {
  final location = context.start?.location;
  if (location is StepScopedLocation &&
      location.step.status == BoundaryStatus.closed) {
    final end = location.step.end;
    return end == null ? null : (seq: end.seq, time: end.time);
  }
  final turn = switch (location) {
    StepScopedLocation(:final turn) => turn,
    TurnScopedLocation(:final turn) => turn,
    _ => null,
  };
  if (turn != null && turn.status == BoundaryStatus.closed) {
    final end = turn.end;
    return end == null ? null : (seq: end.seq, time: end.time);
  }
  return null;
}

_ToolState? _toolFallback(NodeContext context) {
  final match = context.matches
      .where((m) => m.event.type == 'tool/result')
      .firstOrNull;
  final root = match == null ? null : _rootResult(match);
  if (root == null) return null;
  var state = _ToolState(root: root);
  for (final m in context.matches) {
    state = _updateDispatch(state, m);
  }
  return state;
}

/// Root Tool preparation, dispatch, result, and nested PTC calls (dsh
/// `toolDefinition`).
class ToolDefinition extends ConversationDefinition {
  const ToolDefinition();
  @override
  String get kind => 'tool-call';
  @override
  String? get target => chatTarget;
  @override
  Set<String>? get eventTypes => const {
    'assistant/live-chunk',
    'tool/call',
    'tool/result',
    'tool/ptc-dispatch-start',
    'tool/ptc-dispatch',
  };

  @override
  MatchResult? match(ConvEvent event) {
    if (event.type == 'assistant/live-chunk') {
      final chunk = asRecord(event.data['chunk']) ?? const {};
      final block = asRecord(chunk['block']);
      if (chunk['type'] == 'block-end' && block?['type'] == 'tool-call') {
        return MatchResult('${block!['id']}', MatchRole.start);
      }
      return chunk['type'] == 'tool-call-delta'
          ? MatchResult('${chunk['id']}', MatchRole.start)
          : null;
    }
    if (event.type == 'tool/call') {
      return MatchResult('${event.data['callId']}', MatchRole.start);
    }
    if (event.type == 'tool/result' && event.isAppendSurface) {
      final source = asRecord(asRecord(event.data['message'])?['source']);
      return MatchResult('${source?['callId']}', MatchRole.update);
    }
    if (event.type == 'tool/ptc-dispatch-start' ||
        event.type == 'tool/ptc-dispatch') {
      final root = event.data['rootCallId'];
      return root is String && root != ''
          ? MatchResult(root, MatchRole.update)
          : null;
    }
    return null;
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) {
    const empty = _ToolState();
    return match.event.type == 'tool/call'
        ? empty.copy(root: _rootCall(match))
        : _applyDelta(empty, match);
  }

  @override
  Object update(NodeContext context, ConversationMatch match) {
    final state = context.state! as _ToolState;
    final e = match.event;
    if (e.type == 'assistant/live-chunk') return _applyDelta(state, match);
    if (e.type == 'tool/call') {
      return state.copy(root: _rootCall(match, state.root));
    }
    if (e.type == 'tool/result') {
      final root = state.root;
      final running = root is StartedToolCall ? root : null;
      final result = _rootResult(match, running);
      return result == null ? state : state.copy(root: result);
    }
    return _updateDispatch(state, match);
  }

  @override
  Publication publication(ConversationMatch match) =>
      match.event.type == 'assistant/live-chunk'
      ? Publication.animationFrame
      : Publication.immediate;

  @override
  ViewNode? buildViewNode(NodeContext context) {
    final current = context.current[chatTarget];
    final state = (context.state as _ToolState?) ?? _toolFallback(context);
    final stateRoot = state?.root;
    if (state == null || stateRoot == null) {
      return current == null
          ? null
          : (current.visible ? current.hidden() : current);
    }
    final interruptedAt = _interruption(context);
    final projected = _projectBlock(stateRoot, state, interruptedAt);
    final anchor =
        context.start?.event.seq ??
        (stateRoot is ToolResult
            ? stateRoot.seq
            : context.matches.firstOrNull?.event.seq ?? 0);
    final preparing = projected is PreparingToolCall;
    final visible = !(preparing && interruptedAt != null);
    return chatNode(
      context,
      'tool-call',
      anchor,
      ToolData(projected),
      visible: visible,
      location: context.location,
    );
  }
}

// ---- turn tail / error / max tokens ----------------------------------------

class _TailState {
  const _TailState(this.turn, [this.end]);
  final int turn;
  final ConversationMatch? end;
}

TurnLocation? _turnLocation(NodeContext c) {
  final l = c.start?.location ?? c.matches.firstOrNull?.location;
  return switch (l) {
    TurnScopedLocation(:final turn) => turn,
    StepScopedLocation(:final turn) => turn,
    _ => null,
  };
}

bool _hasText(AssistantData d) =>
    d.finalNode != null &&
    d.blocks.any((b) => b is TextBlock && b.text.trim() != '');

TurnTailData? _tailData(NodeContext context) {
  final end = context.state == null
      ? context.matches.where((m) => m.event.type == 'turn/end').firstOrNull
      : (context.state! as _TailState).end;
  if (end == null || end.event.type != 'turn/end') return null;
  final turn = _turnLocation(context);
  if (turn == null) return null;
  final assistants = [
    for (final s in turn.steps)
      if (s.data.get('assistant-step') case final AssistantData a) a,
  ];
  final finalized = [
    for (final a in assistants)
      if (a.finalNode != null) a,
  ]..sort((a, b) => a.finalNode!.seq.compareTo(b.finalNode!.seq));
  final closing = finalized.where(_hasText).lastOrNull;
  num? latestTranscriptSeq = finalized.lastOrNull?.finalNode!.seq;
  for (final match in context.matches) {
    final e = match.event;
    final reason = asRecord(e.data['reason']);
    final candidate =
        e.type == 'tool/call' ||
            (e.type == 'tool/result' && e.surfaceOp == 'append') ||
            (e.type == 'turn/end' && reason?['kind'] == 'error') ||
            e.type == 'llm/retry'
        ? e.seq
        : null;
    if (candidate != null &&
        (latestTranscriptSeq == null || candidate > latestTranscriptSeq)) {
      latestTranscriptSeq = candidate;
    }
  }
  return TurnTailData(
    turn: coordinate(end.event.data['turn']) ?? 0,
    seq: end.event.seq,
    time: end.event.time,
    closing: closing,
    branchUnavailable:
        closing == null || latestTranscriptSeq != closing.finalNode!.seq,
  );
}

({int turn, int? step})? _turnCoordinates(ConvEvent e) {
  const stepTyped = {
    'assistant/message',
    'assistant/attempt',
    'assistant/live-chunk',
    'step/start',
    'step/end',
    'llm/retry',
    'llm/retry-started',
  };
  if (!stepTyped.contains(e.type)) return null;
  return (
    turn: coordinate(e.data['turn']) ?? -1,
    step: coordinate(e.data['step']),
  );
}

/// Completed-turn footer Definition (dsh `turnTailDefinition`; token usage
/// accounting is deferred).
class TurnTailDefinition extends ConversationDefinition {
  const TurnTailDefinition();
  @override
  String get kind => 'turn-tail';
  @override
  String? get target => chatTarget;
  @override
  Set<String>? get eventTypes => const {
    'turn/start',
    'turn/end',
    'tool/call',
    'tool/result',
    'assistant/message',
    'assistant/attempt',
    'assistant/live-chunk',
    'step/start',
    'step/end',
    'llm/retry',
    'llm/retry-started',
  };

  @override
  MatchResult? match(ConvEvent event) {
    if (event.type == 'turn/start') {
      return MatchResult(jsString(event.data, 'turn'), MatchRole.start);
    }
    if (event.type == 'turn/end') {
      return MatchResult(jsString(event.data, 'turn'), MatchRole.update);
    }
    if (event.type == 'tool/call' || event.type == 'tool/result') {
      return MatchResult(jsString(event.data, 'turn'), MatchRole.update);
    }
    if (_turnCoordinates(event) != null) {
      return MatchResult(jsString(event.data, 'turn'), MatchRole.update);
    }
    return null;
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => _TailState(coordinate(match.event.data['turn']) ?? 0);

  @override
  Object update(NodeContext context, ConversationMatch match) {
    final state = context.state! as _TailState;
    return match.event.type == 'turn/end'
        ? _TailState(state.turn, match)
        : state;
  }

  @override
  Publication publication(ConversationMatch match) =>
      match.event.type == 'turn/end' ? Publication.immediate : Publication.none;

  @override
  LocationData? buildLocationData(
    NodeContext context,
    LocationScope scope,
    LocationData? previous,
  ) {
    if (scope != LocationScope.turn) return null;
    final value = _tailData(context);
    return value == null
        ? null
        : LocationData.turn(turn: value.turn, key: 'turn-tail', value: value);
  }

  @override
  ViewNode? buildViewNode(NodeContext context) {
    final data = _turnLocation(context)?.data.get('turn-tail') as TurnTailData?;
    return data == null
        ? null
        : chatNode(
            context,
            'turn-tail',
            data.seq + ChatSeqOffsets.finalizedFollowup,
            data,
            groupTree: 'turn',
          );
  }
}

int _lastStep(NodeContext c) {
  final l = c.start?.location ?? c.matches.firstOrNull?.location;
  final turn = switch (l) {
    TurnScopedLocation(:final turn) => turn,
    StepScopedLocation(:final turn) => turn,
    _ => null,
  };
  return turn?.steps.lastOrNull?.step ?? 0;
}

({String message, String? code})? _endFailure(Map<String, Object?>? reason) {
  switch (reason?['kind']) {
    case 'error':
      final err = reason!['error'];
      final rec = asRecord(err);
      return (
        message: rec?['message'] is String ? rec!['message'] as String : '$err',
        code: rec?['code'] as String?,
      );
    case 'aborted':
      final inner = asRecord(reason!['reason']);
      return inner?['kind'] == 'hook' &&
              inner?['reason'] == 'deepseek-account/signed-out'
          ? (
              message: 'Stopped because you signed out of DeepSeek.',
              code: 'ACCOUNT_SIGNED_OUT',
            )
          : null;
    case 'interrupted':
      return (
        message: 'The DSH process exited before this turn finished.',
        code: 'INTERRUPTED',
      );
    default:
      return null;
  }
}

class _ErrorState {
  const _ErrorState(this.turn, [this.failure]);
  final int turn;
  final TurnErrorData? failure;
}

TurnErrorData? _failureFrom(ConversationMatch m) {
  if (m.event.type != 'turn/end') return null;
  final f = _endFailure(asRecord(m.event.data['reason']));
  if (f == null) return null;
  final display = displayFailure({'message': f.message, 'code': f.code});
  return TurnErrorData(
    seq: m.event.seq,
    time: m.event.time,
    turn: coordinate(m.event.data['turn']) ?? 0,
    step: 0,
    message: display.message,
    code: display.code,
  );
}

/// Terminal turn failure Definition (dsh `turnErrorDefinition`).
class TurnErrorDefinition extends ConversationDefinition {
  const TurnErrorDefinition();
  @override
  String get kind => 'turn-error';
  @override
  String? get target => chatTarget;
  @override
  Set<String>? get eventTypes => const {'turn/start', 'turn/end'};

  @override
  MatchResult? match(ConvEvent event) {
    if (event.type == 'turn/start') {
      return MatchResult(jsString(event.data, 'turn'), MatchRole.start);
    }
    if (event.type == 'turn/end' &&
        _endFailure(asRecord(event.data['reason'])) != null) {
      return MatchResult(jsString(event.data, 'turn'), MatchRole.update);
    }
    return null;
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => _ErrorState(coordinate(match.event.data['turn']) ?? 0);

  @override
  Object update(NodeContext context, ConversationMatch match) {
    final state = context.state! as _ErrorState;
    final f = _failureFrom(match);
    return f == null ? state : _ErrorState(state.turn, f);
  }

  @override
  ViewNode? buildViewNode(NodeContext context) {
    var state = context.state as _ErrorState?;
    if (state == null) {
      final end = context.matches
          .where((m) => _failureFrom(m) != null)
          .firstOrNull;
      if (end == null) return null;
      state = _ErrorState(
        coordinate(end.event.data['turn']) ?? 0,
        _failureFrom(end),
      );
    }
    final f = state.failure;
    if (f == null) return null;
    final node = TurnErrorData(
      seq: f.seq,
      time: f.time,
      turn: state.turn,
      step: _lastStep(context),
      message: f.message,
      code: f.code,
    );
    return chatNode(context, 'turn-error', node.seq, node, groupTree: 'turn');
  }
}

class _MaxTokensState {
  const _MaxTokensState(this.turn, this.seq, this.time);
  final int turn;
  final num seq;
  final num time;
}

/// Notice Definition for a turn the provider ended at its output cap (dsh
/// `turnMaxTokensDefinition`).
class TurnMaxTokensDefinition extends ConversationDefinition {
  const TurnMaxTokensDefinition();
  @override
  String get kind => 'turn-max-tokens';
  @override
  String? get target => chatTarget;
  @override
  Set<String>? get eventTypes => const {'turn/end'};

  static bool _is(ConvEvent e) =>
      e.type == 'turn/end' &&
      asRecord(e.data['reason'])?['kind'] == 'max-tokens';

  @override
  MatchResult? match(ConvEvent event) => _is(event)
      ? MatchResult(jsString(event.data, 'turn'), MatchRole.start)
      : null;

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => _MaxTokensState(
    coordinate(match.event.data['turn']) ?? 0,
    match.event.seq,
    match.event.time,
  );

  @override
  Object update(NodeContext context, ConversationMatch match) => context.state!;

  @override
  ViewNode? buildViewNode(NodeContext context) {
    final state = context.state as _MaxTokensState?;
    if (state == null) return null;
    final node = TurnMaxTokensData(
      seq: state.seq,
      time: state.time,
      turn: state.turn,
      step: _lastStep(context),
    );
    final l = context.start?.location ?? context.matches.firstOrNull?.location;
    final turn = switch (l) {
      TurnScopedLocation(:final turn) => turn,
      StepScopedLocation(:final turn) => turn,
      _ => null,
    };
    final closing = (turn?.data.get('turn-tail') as TurnTailData?)?.closing;
    final anchor = turn == null || closing == null
        ? state.seq
        : closing.finalNode!.seq + ChatSeqOffsets.maxTokensNotice;
    return chatNode(
      context,
      'turn-max-tokens',
      anchor,
      node,
      groupTree: 'turn',
    );
  }
}

// ---- unknown fallback ---------------------------------------------------

/// Generic presentation of an unclaimed append-surface event (dsh
/// `unknownFallbackDefinition`).
class UnknownSurfaceDefinition extends ConversationDefinition {
  const UnknownSurfaceDefinition();
  @override
  String get kind => 'unknown-surface';
  @override
  String? get target => chatTarget;

  @override
  MatchResult? match(ConvEvent event) =>
      event.type != 'assistant/live-chunk' && event.isAppendSurface
      ? MatchResult(seqText(event.seq), MatchRole.start)
      : null;

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => UnknownData(
    seq: match.event.seq,
    time: match.event.time,
    type: match.event.type,
    data: match.event.data,
  );

  @override
  Object update(NodeContext context, ConversationMatch match) => context.state!;

  @override
  ViewNode? buildViewNode(NodeContext context) {
    final state = context.state as UnknownData?;
    return state == null
        ? null
        : chatNode(context, 'unknown', state.seq, state);
  }
}
