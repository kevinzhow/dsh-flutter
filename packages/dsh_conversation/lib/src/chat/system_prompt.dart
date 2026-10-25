import 'dart:convert';

import '../contract.dart';
import '../event.dart';
import 'definitions.dart' show chatNode, chatTarget;
import 'projection.dart' show asRecord;

/// Complete prompt text at one historical card; it is not a transcript row.
class SystemPromptData {
  const SystemPromptData(this.text, {this.update = false});
  final String text;
  final bool update;
}

class SystemPromptFact {
  const SystemPromptFact({
    required this.seq,
    required this.time,
    required this.turn,
    required this.step,
    required this.text,
    required this.update,
  });
  final num seq, time;
  final int turn, step;
  final String text;
  final bool update;
}

typedef PositionedSystemPrompt = ({num position, SystemPromptFact node});

/// Immutable prompt facts after a log prefix, including positional replacements.
class SystemPromptState {
  const SystemPromptState({
    required this.firstSeq,
    required this.uncertain,
    required this.nodes,
    required this.replacements,
    this.effective,
    this.introduced,
  });
  final num firstSeq;
  final bool uncertain;
  final List<PositionedSystemPrompt> nodes;
  final Map<num, num> replacements;
  final SystemPromptFact? effective, introduced;
}

/// dsh's inspectSystemPrompt: replacements inherit their start endpoint's
/// surface position. An unknown older endpoint withholds facts until prepend.
SystemPromptState inspectSystemPrompt(
  SystemPromptState? previous,
  ConvEvent event,
) {
  final op = event.isSurfaceEvent ? asRecord(event.surfaceOp) : null;
  final firstSeq = previous?.firstSeq ?? event.seq;
  var nodes = previous?.nodes ?? const <PositionedSystemPrompt>[];
  var replacements = previous?.replacements ?? const <num, num>{};
  bool unknown(num seq) => seq < firstSeq && !replacements.containsKey(seq);
  final uncertain =
      previous?.uncertain == true ||
      (op != null &&
          (unknown(op['startSeq']! as num) || unknown(op['endSeq']! as num)));
  if (uncertain) {
    return SystemPromptState(
      firstSeq: firstSeq,
      uncertain: true,
      nodes: const [],
      replacements: const {},
    );
  }
  num position = event.seq;
  if (op != null) {
    position = replacements[op['startSeq']] ?? op['startSeq']! as num;
    final end = replacements[op['endSeq']] ?? op['endSeq']! as num;
    nodes = nodes
        .where((n) => n.position < position || n.position > end)
        .toList();
    replacements = {
      for (final e in replacements.entries)
        if (e.value < position || e.value > end) e.key: e.value,
      event.seq: position,
    };
  }
  SystemPromptFact? introduced;
  if (event.type == 'system/message') {
    final message = asRecord(event.data['message']);
    final content = message?['content'];
    introduced = SystemPromptFact(
      seq: event.seq,
      time: event.time,
      turn: coordinate(event.data['turn']) ?? 0,
      step: coordinate(event.data['step']) ?? 0,
      text: [
        if (content is List)
          for (final block in content)
            if (block is Map && block['type'] == 'text')
              block['text'] as String,
      ].join(),
      update:
          event.surfaceOp == 'append' &&
          previous?.nodes.any((n) => n.node.text.isNotEmpty) == true,
    );
    nodes = [...nodes, (position: position, node: introduced)]
      ..sort((a, b) => a.position.compareTo(b.position));
  }
  SystemPromptFact? lastNonempty(List<PositionedSystemPrompt>? values) =>
      values?.where((n) => n.node.text.isNotEmpty).lastOrNull?.node;
  final surviving = lastNonempty(nodes);
  final effective = identical(surviving, lastNonempty(previous?.nodes))
      ? previous?.effective
      : introduced != null && identical(introduced, surviving)
      ? introduced
      : SystemPromptFact(
          seq: event.seq,
          time: event.time,
          turn: surviving?.turn ?? 0,
          step: surviving?.step ?? 0,
          text: surviving?.text ?? '',
          update: false,
        );
  return SystemPromptState(
    firstSeq: firstSeq,
    uncertain: false,
    nodes: List.unmodifiable(nodes),
    replacements: Map.unmodifiable(replacements),
    effective: effective,
    introduced: introduced,
  );
}

num _requestAnchor(
  ConversationMatch match,
  _RequestPromptState? previous,
  bool initial,
) {
  final location = match.location;
  if (location is! StepScopedLocation) return match.event.seq;
  if (previous == null && !initial) return match.event.seq;
  if (previous?.turn == location.turn.turn &&
      previous?.step == location.step.step) {
    return match.event.seq;
  }
  return location.step.step == 1
      ? location.turn.start?.seq ?? location.step.start?.seq ?? match.event.seq
      : location.step.start?.seq ?? match.event.seq;
}

/// Appended system messages own historical cards. Every surface replacement
/// is interpreted here so the unknown fallback cannot show it as a message.
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
  ) => inspectSystemPrompt(
    reader.previous(kind)?.state as SystemPromptState?,
    match.event,
  );
  @override
  Object update(NodeContext context, ConversationMatch match) => context.state!;
  @override
  ViewNode? buildViewNode(NodeContext context) {
    final state = (context.state as SystemPromptState?)?.introduced;
    final start = context.start;
    if (state == null ||
        state.text.isEmpty ||
        start?.event.type != 'system/message' ||
        start?.event.surfaceOp != 'append') {
      return null;
    }
    final anchor = state.update
        ? state.seq
        : _requestAnchor(start!, null, true);
    return chatNode(
      context,
      'system-prompt',
      anchor,
      SystemPromptData(state.text, update: state.update),
    );
  }
}

class _RequestPromptState {
  const _RequestPromptState({
    required this.anchorSeq,
    required this.showsPrompt,
    required this.system,
    required this.tools,
    this.turn,
    this.step,
  });
  final num anchorSeq;
  final bool showsPrompt;
  final String system;
  final List<Object?> tools;
  final int? turn, step;
}

/// Full request headers own resumed/new-series prompt cards. Header config is
/// unrelated to this view; system/tools changes follow inspectRequestPrompt.
class RequestPromptDefinition extends ConversationDefinition {
  const RequestPromptDefinition();
  @override
  String get kind => 'request-prompt';
  @override
  String? get target => chatTarget;
  @override
  Set<String>? get eventTypes => const {'request/header'};
  @override
  MatchResult? match(ConvEvent event) => event.type == 'request/header'
      ? MatchResult(seqText(event.seq), MatchRole.start)
      : null;
  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) {
    final previous = reader.previous(kind)?.state as _RequestPromptState?;
    final systemContext = reader.previous('system-message');
    final system = (systemContext?.state as SystemPromptState?)?.effective;
    final rawTools = asRecord(match.event.data['header'])?['tools'];
    final tools = rawTools is List
        ? List<Object?>.unmodifiable(rawTools)
        : const <Object?>[];
    final text = system?.text ?? '';
    final reason = match.event.data['reason'];
    final systemChanged =
        previous != null && previous.system != text && system?.update != true;
    final toolsChanged =
        previous != null && jsonEncode(previous.tools) != jsonEncode(tools);
    final change = previous == null
        ? (reason == 'initial' ? 'initial' : null)
        : systemChanged
        ? (toolsChanged ? 'system-and-tools' : 'system')
        : toolsChanged
        ? 'tools'
        : null;
    final location = match.location;
    final turn = location is StepScopedLocation ? location.turn.turn : null;
    final step = location is StepScopedLocation ? location.step.step : null;
    final systemEvent = systemContext?.matches.firstOrNull?.event;
    final shownByUpdate =
        system != null &&
        systemEvent?.type == 'system/message' &&
        systemEvent?.surfaceOp == 'append' &&
        (system.update || previous == null) &&
        system.turn == turn &&
        system.step == step;
    final current = context.current[chatTarget];
    return _RequestPromptState(
      anchorSeq: current?.kind == 'system-prompt'
          ? current!.anchorSeq
          : _requestAnchor(match, previous, reason == 'initial'),
      showsPrompt:
          !shownByUpdate &&
          (previous == null ||
              reason != 'change' ||
              match.event.data['startsSeries'] == true ||
              change == 'system' ||
              change == 'system-and-tools'),
      system: text,
      tools: tools,
      turn: turn,
      step: step,
    );
  }

  @override
  Object update(NodeContext context, ConversationMatch match) => context.state!;
  @override
  ViewNode? buildViewNode(NodeContext context) {
    final state = context.state as _RequestPromptState?;
    if (state == null) return null;
    final visible = state.showsPrompt && state.system.isNotEmpty;
    if (!visible && context.current[chatTarget]?.kind != 'system-prompt') {
      return null;
    }
    return chatNode(
      context,
      'system-prompt',
      state.anchorSeq,
      SystemPromptData(state.system),
      visible: visible,
    );
  }
}
