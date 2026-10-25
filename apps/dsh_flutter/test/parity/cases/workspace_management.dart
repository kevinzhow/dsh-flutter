import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_session/dsh_feature_session.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import '../helpers/workspace_fixture.dart';

const activity = <Object?>[
  {'kind': 'turn'},
  {
    'kind': 'job',
    'items': [
      {'id': 'check', 'label': 'Synthetic check'},
    ],
  },
];
Widget browser(ParityContext ctx, {bool group = false}) {
  final name = ctx.props['name'];
  final actions = SyntheticWorkspaceManagement();
  final i18n = DshI18n(DshLocale.fromTag(ctx.locale));
  final slots = SlotRegistry();
  for (final slot in DshSlots.all) {
    slots.declare(slot);
  }
  registerSessionRowFeatures(slots, i18n: () => i18n);
  final view = WorkspaceViewState()
    ..setGroupBy(group ? SessionGroupBy.workspace : SessionGroupBy.flat)
    ..setArchivedFilter(ArchivedFilter.show)
    ..setGroupExpanded('a', true);
  final now = DateTime.fromMillisecondsSinceEpoch(
    SyntheticWorkspaceManagement.now,
  );
  return SizedBox(
    width: (ctx.props['width'] as num).toDouble(),
    height: 400,
    child: WorkspaceBrowser(
      snapshot: SessionListSnapshot(
        phase: ListPhase.ready,
        items: [
          SessionListEntry(
            SessionSummary(
              sessionId: 's1',
              updatedAt: now.millisecondsSinceEpoch - 300000,
              running: name == 'running',
              blank: false,
              agentAvailable: true,
            ),
            ctx.props['long'] == true
                ? 'Synthetic session title that continues well beyond the available width'
                : 'Synthetic session',
          ),
        ],
      ),
      workspaces: group
          ? [
              TreeWorkspace(
                workspaceId: 'a',
                title: 'Synthetic project',
                path: '/synthetic/a',
                createdAt: now.millisecondsSinceEpoch,
                sessionIds: const ['s1'],
              ),
            ]
          : const [],
      view: view,
      i18n: i18n,
      currentId: null,
      onOpen: (_) {},
      management: actions,
      slots: slots,
      rowState: SessionRowState(
        pinned: name == 'pinned' ? const ['s1'] : const [],
        archived: name == 'archived' ? const ['s1'] : const [],
      ),
      statuses: name == 'pending'
          ? const {
              's1': SessionStatusFacts(pending: PendingInteraction.question),
            }
          : const {},
      now: () => now,
      onStartInWorkspace: (_) {},
    ),
  );
}

final Map<String, ParityCase> workspaceManagementCases = {
  'workspace-management.row': ParityCase(
    widgets: const ['dsh_feature_session:WorkspaceBrowser session row'],
    build: (ctx) => browser(ctx),
  ),
  'workspace-management.group': ParityCase(
    widgets: const ['dsh_feature_session:WorkspaceBrowser workspace row'],
    build: (ctx) => browser(ctx, group: true),
  ),
  'workspace-management.dialog': ParityCase(
    widgets: const ['dsh_feature_session:WorkspaceActionForm'],
    framed: false,
    build: (ctx) {
      final i18n = DshI18n(DshLocale.fromTag(ctx.locale));
      final archive = ctx.props['archive'] == true;
      return ColoredBox(
        color: ctx.theme.bgBase,
        child: ColoredBox(
          color: ctx.theme.color('--dsw-alias-bg-mask-1'),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.topLeft,
              child: DshDialogFrame(
                key: const ValueKey('workspace-management-dialog'),
                width: 380,
                child: WorkspaceActionForm(
                  title: i18n.t(
                    'workspace',
                    archive ? 'archive.confirm.title' : 'rename.session.title',
                  ),
                  confirmLabel: i18n.t(
                    'workspace',
                    archive ? 'archive.confirm.action' : 'rename',
                  ),
                  i18n: i18n,
                  initial: archive ? null : 'Synthetic session',
                  fieldLabel: archive
                      ? null
                      : i18n.t('workspace', 'field.sessionName'),
                  danger: archive,
                  description: archive
                      ? i18n.t(
                          'workspace',
                          'archive.confirm.desc',
                          params: {'title': 'Synthetic session'},
                        )
                      : null,
                  detail: archive
                      ? WorkspaceArchiveActivity(activity: activity, i18n: i18n)
                      : null,
                  pendingLabel: archive
                      ? i18n.t('workspace', 'archive.confirm.pending')
                      : null,
                  submit: (_) async {
                    if (ctx.props['name'] == 'pending') {
                      await Completer<void>().future;
                    }
                    if (ctx.props['name'] == 'refused') {
                      throw RemoteException(
                        'fixture/refused',
                        'Synthetic refusal',
                      );
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  ),
};
