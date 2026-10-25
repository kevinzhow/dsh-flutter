import '../contract.dart';
import '../event.dart';
import 'definitions.dart';
import 'projection.dart';

/// Settlement of a durable slash command. Text is kept verbatim.
class CommandOutcome {
  const CommandOutcome({required this.kind, this.text, this.sourceEventSeq});
  final String kind;
  final String? text;
  final num? sourceEventSeq;
}

class CommandData {
  const CommandData({
    required this.seq,
    required this.time,
    required this.commandId,
    this.name,
    this.args,
    this.outcome,
  });
  final num seq, time;
  final Object? commandId;
  final String? name, args;
  final CommandOutcome? outcome;
}

/// A landed marker, never the model-facing replacement envelope.
class CompactionData {
  const CompactionData({
    required this.seq,
    required this.time,
    this.summary,
    this.summaryEventSeq,
    this.shadowedItemCount,
    this.shadowedTokenCount,
  });
  final num seq, time;
  final String? summary;
  final num? summaryEventSeq;
  final int? shadowedItemCount, shadowedTokenCount;
}

class ManualCompactionData {
  const ManualCompactionData(this.command, this.compaction);
  final CommandData command;
  final CompactionData? compaction;
}

int? _safeNatural(Object? value) =>
    value is num &&
        value.isFinite &&
        value >= 0 &&
        value <= 9007199254740991 &&
        value == value.truncate()
    ? value.toInt()
    : null;

({String id, Object? commandId, bool manual})? _checkpoint(ConvEvent event) {
  if (event.type != 'user/message' || !event.isReplacementSurface) return null;
  final source = asRecord(event.data['source']);
  final id = source?['compactionId'];
  if (source?['kind'] != 'compact-checkpoint' || id is! String) return null;
  return (
    id: id,
    commandId: source?['sourceCommandId'],
    manual: source!.containsKey('sourceCommandId'),
  );
}

class _Evidence {
  const _Evidence({this.summary, this.checkpoint});
  factory _Evidence.fromMatches(List<ConversationMatch> matches) => _Evidence(
    summary: matches
        .where((m) => m.event.type == 'compaction/summary')
        .firstOrNull,
    checkpoint: matches.where((m) => _checkpoint(m.event) != null).firstOrNull,
  );
  final ConversationMatch? summary, checkpoint;
  _Evidence apply(ConversationMatch match) {
    if (match.event.type == 'compaction/summary') {
      return _Evidence(summary: match, checkpoint: checkpoint);
    }
    if (_checkpoint(match.event) != null) {
      return _Evidence(summary: summary, checkpoint: match);
    }
    return this;
  }

  CompactionData? get marker {
    final landed = checkpoint?.event;
    if (landed == null) return null;
    final data = summary?.event.data;
    final blocks = data?['summary'];
    final text = blocks is List
        ? [
            for (final block in blocks)
              if (block is Map && block['type'] == 'text') block['text'] ?? '',
          ].join()
        : '';
    final seqs = data?['shadowedSeqs'];
    return CompactionData(
      seq: landed.seq,
      time: landed.time,
      summary: text.trim().isEmpty ? null : text,
      summaryEventSeq: summary?.event.seq,
      shadowedItemCount:
          seqs is List && seqs.every((s) => _safeNatural(s) != null)
          ? seqs.length
          : null,
      shadowedTokenCount: _safeNatural(data?['shadowedTokenCount']),
    );
  }
}

const _lifecycle = {'compaction/start', 'compaction/summary', 'compaction/end'};

/// Automatic compaction is visible only after its replacement lands. The
/// transcript it shadowed remains in the chat snapshot.
class CompactionDefinition extends ConversationDefinition {
  const CompactionDefinition();
  @override
  String get kind => 'compaction';
  @override
  String? get target => chatTarget;
  @override
  Set<String>? get eventTypes => const {..._lifecycle, 'user/message'};
  @override
  MatchResult? match(ConvEvent event) {
    final checkpoint = _checkpoint(event);
    if (checkpoint != null && !checkpoint.manual) {
      return MatchResult(checkpoint.id, MatchRole.update);
    }
    if (!_lifecycle.contains(event.type) ||
        event.data.containsKey('sourceCommandId')) {
      return null;
    }
    final id = event.data['compactionId'];
    if (id is! String || id.isEmpty) return null;
    return MatchResult(
      id,
      event.type == 'compaction/start' ? MatchRole.start : MatchRole.update,
    );
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => const _Evidence();
  @override
  Object update(NodeContext context, ConversationMatch match) =>
      (context.state! as _Evidence).apply(match);
  @override
  ViewNode? buildViewNode(NodeContext context) {
    final marker =
        (context.state as _Evidence? ?? _Evidence.fromMatches(context.matches))
            .marker;
    return marker == null ? null : chatNode(context, kind, marker.seq, marker);
  }
}

CommandData _fromRun(ConversationMatch match) {
  final e = match.event;
  return CommandData(
    seq: e.seq,
    time: e.time,
    commandId: e.data['commandId'],
    name: e.data['name'] as String?,
    args: e.data['args'] as String?,
  );
}

CommandData _fromDone(ConversationMatch match, [CommandData? previous]) {
  final e = match.event;
  return CommandData(
    seq: previous?.seq ?? e.seq,
    time: previous?.time ?? e.time,
    commandId: e.data['commandId'],
    name: previous?.name,
    args: previous?.args,
    outcome: CommandOutcome(
      kind: e.data['kind']! as String,
      text: e.data['text'] as String?,
      sourceEventSeq: e.data['kind'] == 'success'
          ? _safeNatural(e.data['sourceEventSeq'])
          : null,
    ),
  );
}

class _CommandState {
  const _CommandState(this.command, [this.evidence = const _Evidence()]);
  final CommandData command;
  final _Evidence evidence;
}

_CommandState? _fallback(NodeContext context) {
  final done = context.matches
      .where((m) => m.event.type == 'command/done')
      .firstOrNull;
  final evidence = _Evidence.fromMatches(context.matches);
  final checkpoint = evidence.checkpoint?.event;
  final source = checkpoint == null ? null : _checkpoint(checkpoint);
  if (source == null || !source.manual) {
    return done == null ? null : _CommandState(_fromDone(done));
  }
  final command = done == null ? null : _fromDone(done);
  return _CommandState(
    CommandData(
      seq: command?.seq ?? checkpoint!.seq,
      time: command?.time ?? checkpoint!.time,
      commandId: source.commandId,
      name: 'compact',
      outcome: command?.outcome,
    ),
    evidence,
  );
}

/// Ordinary commands and manual compaction share one correlation identity,
/// including soft fallbacks when an older run event is outside the window.
class CommandDefinition extends ConversationDefinition {
  const CommandDefinition();
  @override
  String get kind => 'command';
  @override
  String? get target => chatTarget;
  @override
  Set<String>? get eventTypes => const {
    'command/run',
    'command/done',
    'user/message',
    ..._lifecycle,
  };
  @override
  MatchResult? match(ConvEvent event) {
    if (event.type == 'command/run' || event.type == 'command/done') {
      return MatchResult(
        jsString(event.data, 'commandId'),
        event.type == 'command/run' ? MatchRole.start : MatchRole.update,
      );
    }
    final source = _checkpoint(event);
    if (source != null && source.manual) {
      return MatchResult(
        jsString({'id': source.commandId}, 'id'),
        MatchRole.update,
      );
    }
    if (_lifecycle.contains(event.type) &&
        event.data.containsKey('sourceCommandId')) {
      return MatchResult(
        jsString(event.data, 'sourceCommandId'),
        MatchRole.update,
      );
    }
    return null;
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => _CommandState(_fromRun(match));
  @override
  Object update(NodeContext context, ConversationMatch match) {
    final state = context.state! as _CommandState;
    return match.event.type == 'command/done'
        ? _CommandState(_fromDone(match, state.command), state.evidence)
        : _CommandState(state.command, state.evidence.apply(match));
  }

  @override
  ViewNode? buildViewNode(NodeContext context) {
    final state = context.state as _CommandState? ?? _fallback(context);
    if (state == null) return null;
    if (state.command.name != 'compact') {
      return chatNode(context, kind, state.command.seq, state.command);
    }
    final marker = state.evidence.marker;
    return chatNode(
      context,
      'manual-compaction',
      marker?.seq ?? state.command.seq,
      ManualCompactionData(state.command, marker),
    );
  }
}
