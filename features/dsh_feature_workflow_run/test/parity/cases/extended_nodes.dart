import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_workflow_run/dsh_feature_workflow_run.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> workflowCases = {
  'chat.workflow-run': ParityCase(
    widgets: const ['dsh_feature_workflow_run:WorkflowRunPanel'],
    build: (ctx) {
      final d = (ctx.props['data'] as Map).cast<String, Object?>();
      return Align(
        alignment: Alignment.topLeft,
        child: parityItem(
          'node-el',
          SizedBox(
            width: (ctx.props['width'] as num).toDouble(),
            child: parityItem(
              'node-toggle',
              WorkflowRunPanel(
                data: WorkflowRunData(
                  name: d['name'] as String,
                  status: WorkflowRunStatus.values.byName(
                    d['status'] as String,
                  ),
                  phases: [
                    for (final p in d['phases'] as List)
                      WorkflowRunPhase((p as Map)['phase'] as String?, [
                        for (final m in p['members'] as List)
                          WorkflowRunMember(
                            seq: (m as Map)['seq'] as num,
                            label: m['label'] as String,
                            childId: m['childId'] as String,
                            status: WorkflowRunStatus.values.byName(
                              m['status'] as String,
                            ),
                          ),
                      ]),
                  ],
                ),
                i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
                canOpen: (m) => m.status == WorkflowRunStatus.running,
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
    },
  ),
};
