import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_agent_management/dsh_feature_agent_management.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';
import 'package:dsh_ui/dsh_ui.dart';

import '../helpers/agents_tasks_fixture.dart';

final Map<String, ParityCase> agentsTasksCases = {
  for (final family in ['preset', 'goal', 'skill', 'jobs', 'manager'])
    'agents-tasks.$family': ParityCase(
      widgets: ['dsh_feature_agent_management:$family'],
      build: (ctx) => _Surface(
        family: family,
        name: ctx.props['name'] as String,
        width: (ctx.props['width'] as num).toDouble(),
        height: (ctx.props['height'] as num).toDouble(),
        i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
      ),
    ),
};

class _Surface extends StatefulWidget {
  const _Surface({
    required this.family,
    required this.name,
    required this.width,
    required this.height,
    required this.i18n,
  });
  final String family, name;
  final double width, height;
  final DshI18n i18n;
  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  final fixture = SyntheticAgentsTasks();
  @override
  void initState() {
    super.initState();
    if (widget.name == 'basic')
      fixture.tools.publish(
        const ConfigFormSnapshot(
          status: ConfigFormStatus.ready,
          value: {'enabled': false},
          writable: true,
          revision: 2,
        ),
      );
    if (widget.name == 'empty') fixture.tasks.clear();
    if (widget.family == 'goal') {
      fixture.goal = {
        ...fixture.goal,
        'phase': widget.name,
        if (widget.name == 'blocked')
          'blockedReason': {
            'code': 'synthetic',
            'message': 'Synthetic blocked reason',
          },
      };
      fixture.session.projections.apply('goal', {
        'goal': fixture.goal,
      }, ++fixture.projectionSeq);
    }
  }

  @override
  void dispose() {
    unawaited(fixture.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    ToolCall skill() => name == 'running'
        ? StartedToolCall(
            callId: 'synthetic-skill',
            name: 'skill',
            args: PartialArguments.fromText('{"name":"review"}'),
            subCalls: const [],
            argsRaw: '{"name":"review"}',
            turn: 1,
            step: 1,
            time: 1000,
          )
        : ToolResult(
            callId: 'synthetic-skill',
            name: 'skill',
            args: PartialArguments.fromText('{"name":"review"}'),
            subCalls: const [],
            seq: 10,
            time: 1000,
            content: [
              {
                'type': 'text',
                'text': name == 'error' ? 'Synthetic failure\nFurther details' : 'Synthetic review instructions\nCheck the diff and report findings.',
              },
            ],
            isError: name == 'error',
            callArgsRaw: '{"name":"review"}',
          );
    final body = switch (widget.family) {
      'preset' => SingleChildScrollView(
        child: AgentPresetSection(
          model: fixture.presets,
          i18n: widget.i18n,
          startCreator: () {},
        ),
      ),
      'goal' => Align(
        alignment: Alignment.topCenter,
        child: GoalBar(model: fixture.goalModel, i18n: widget.i18n),
      ),
      'skill' => Align(
        alignment: Alignment.topLeft,
        child: SkillRow(call: skill(), i18n: widget.i18n),
      ),
      'jobs' => Align(
        alignment: Alignment.topLeft,
        child: JobListAction(
          service: fixture.jobs,
          sessionId: 'synthetic-session',
          i18n: widget.i18n,
        ),
      ),
      _ => TaskManagerPage(
        service: fixture.schedules,
        i18n: widget.i18n,
        onNew: () {},
        onOpenSession: (_) {},
      ),
    };
    return SizedBox(
      key: const ValueKey('agents-tasks-surface'),
      width: widget.width,
      height: widget.height,
      child: DefaultTextStyle(
        style: context.dsh
            .textStyle('--dsw-font-s-14')
            .copyWith(color: context.dsh.labelPrimary),
        child: body,
      ),
    );
  }
}
