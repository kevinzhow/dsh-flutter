import '../contract.dart';
import '../event.dart';
import 'definitions.dart';

enum WorkflowRunStatus { running, completed, failed, cancelled, interrupted }

class WorkflowRunMember {
  const WorkflowRunMember({
    required this.seq,
    required this.label,
    required this.childId,
    required this.status,
  });
  final num seq;
  final String label, childId;
  final WorkflowRunStatus status;
}

class WorkflowRunPhase {
  const WorkflowRunPhase(this.phase, this.members);
  final String? phase;
  final List<WorkflowRunMember> members;
  // Dart strings count UTF-16 units, matching JavaScript phase.length.
  String get key => phase == null ? 'missing' : 'value:${phase!.length}:$phase';
}

class WorkflowRunData {
  const WorkflowRunData({
    required this.name,
    required this.status,
    required this.phases,
  });
  final String name;
  final WorkflowRunStatus status;
  final List<WorkflowRunPhase> phases;
}

class _State {
  const _State(this.name, this.members, [this.stopReason]);
  final String name;
  final List<Map<String, Object?>> members;
  final String? stopReason;
}

WorkflowRunStatus _status(String value) => value == 'error'
    ? WorkflowRunStatus.failed
    : WorkflowRunStatus.values.firstWhere((s) => s.name == value);

/// Only durable run-end or an abandoned Turn proves liveness has ended.
class WorkflowRunDefinition extends ConversationDefinition {
  const WorkflowRunDefinition();
  @override
  String get kind => 'workflow-run';
  @override
  String get target => chatTarget;
  @override
  Set<String> get eventTypes => const {
    'tool-workflow/run-start',
    'tool-workflow/agent-start',
    'tool-workflow/agent-end',
    'tool-workflow/run-end',
  };
  @override
  MatchResult? match(ConvEvent event) => !eventTypes.contains(event.type)
      ? null
      : MatchResult(
          '${event.data['runId']}',
          event.type == 'tool-workflow/run-start'
              ? MatchRole.start
              : MatchRole.update,
        );
  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => _State(match.event.data['name'] as String, []);
  @override
  Object update(NodeContext context, ConversationMatch match) {
    final s = context.state! as _State, d = match.event.data;
    return switch (match.event.type) {
      'tool-workflow/agent-start' => _State(s.name, [
        ...s.members,
        d,
      ], s.stopReason),
      'tool-workflow/agent-end' => _State(s.name, [
        for (final m in s.members)
          m['seq'] == d['seq'] ? {...m, 'outcome': d['outcome']} : m,
      ], s.stopReason),
      'tool-workflow/run-end' => _State(
        s.name,
        s.members,
        d['stopReason'] as String,
      ),
      _ => s,
    };
  }

  @override
  ViewNode? buildViewNode(NodeContext context) {
    if (context.start == null) return null;
    final s = context.state! as _State;
    final location = context.start!.location;
    final turn = switch (location) {
      StepScopedLocation(:final turn) ||
      TurnScopedLocation(:final turn) => turn,
      _ => null,
    };
    final reason = (turn?.end?.data['reason'] as Map?)?['kind'];
    final interrupted =
        s.stopReason == null && (reason == 'interrupted' || reason == 'forked');
    final groups = <String?, List<WorkflowRunMember>>{};
    for (final m in s.members) {
      groups
          .putIfAbsent(m['phase'] as String?, () => [])
          .add(
            WorkflowRunMember(
              seq: m['seq'] as num,
              label: m['label'] as String,
              childId: m['childId'] as String,
              status: m['outcome'] != null
                  ? _status(m['outcome'] as String)
                  : interrupted
                  ? WorkflowRunStatus.interrupted
                  : WorkflowRunStatus.running,
            ),
          );
    }
    return chatNode(
      context,
      kind,
      context.start!.event.seq,
      WorkflowRunData(
        name: s.name,
        status: s.stopReason != null
            ? _status(s.stopReason!)
            : interrupted
            ? WorkflowRunStatus.interrupted
            : WorkflowRunStatus.running,
        phases: [
          for (final group in groups.entries)
            WorkflowRunPhase(group.key, group.value),
        ],
      ),
      location: location,
    );
  }
}
