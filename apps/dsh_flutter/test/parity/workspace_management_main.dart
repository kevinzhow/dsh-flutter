import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_feature_chat/src/stream/message_actions.dart';
import 'package:dsh_feature_session/dsh_feature_session.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/material.dart';

import 'helpers/workspace_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPinnedFontsFromEnvironment();
  await WindowChrome.init();
  final dark =
      const bool.fromEnvironment('PARITY_DARK') ||
      Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark';
  final zh =
      const String.fromEnvironment('PARITY_LOCALE') == 'zh' ||
      (Platform.environment['LC_ALL'] ?? '').startsWith('zh');
  final brightness = dark ? Brightness.dark : Brightness.light;
  final theme = resolveTheme(officialPack, ThemeSettings(), brightness);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: brightness, extensions: [theme]),
      home: Scaffold(
        backgroundColor: theme.bgBase,
        body: SafeArea(
          child: Fixture(DshI18n(zh ? DshLocale.zh : DshLocale.en)),
        ),
      ),
    ),
  );
}

class Fixture extends StatefulWidget {
  const Fixture(this.i18n, {super.key});
  final DshI18n i18n;
  @override
  State<Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<Fixture> {
  final actions = SyntheticWorkspaceManagement();
  final view = WorkspaceViewState()
    ..setGroupExpanded('a', true)
    ..setGroupExpanded('b', true);
  final slots = SlotRegistry();
  int tab = 0;
  @override
  void initState() {
    super.initState();
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
    registerSessionRowFeatures(slots, i18n: () => widget.i18n);
  }

  @override
  void dispose() {
    view.dispose();
    actions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: actions,
    builder: (context, _) {
      final title =
          actions.sessions.items.firstWhere((r) => r.sessionId == 's1').title ??
          '';
      final snapshot = actions.workspaces;
      return Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                for (final (i, label) in ['Browser', 'Actions'].indexed)
                  Expanded(
                    child: TextButton(
                      onPressed: () => setState(() => tab = i),
                      child: Text(label),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: tab == 0
                ? Center(
                    child: SizedBox(
                      width: 280,
                      child: WorkspaceBrowser(
                        snapshot: actions.sessions,
                        workspaces: [
                          for (final row in snapshot.items)
                            TreeWorkspace(
                              workspaceId: row.workspaceId,
                              title: row.title,
                              path: row.path,
                              createdAt: DateTime.parse(row.createdAt)
                                  .millisecondsSinceEpoch,
                              sessionIds: row.sessionIds,
                            ),
                        ],
                        view: view,
                        rowState: SessionRowState(
                          pinned: snapshot.pinnedSessionIds,
                          archived: snapshot.archivedSessionIds,
                        ),
                        management: actions,
                        slots: slots,
                        i18n: widget.i18n,
                        currentId: 's1',
                        onOpen: (id) => unawaited(actions.openSession(id)),
                        now: () => DateTime.fromMillisecondsSinceEpoch(
                          SyntheticWorkspaceManagement.now,
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        WorkspaceSessionMenu(
                          actions: actions,
                          slots: slots,
                          i18n: widget.i18n,
                          sessionId: 's1',
                          title: title,
                          pinned: snapshot.pinnedSessionIds.contains('s1'),
                          archived: snapshot.archivedSessionIds.contains('s1'),
                          builder: (_, menu) => TextButton(
                            onPressed: menu.toggle,
                            child: const Text('Session actions'),
                          ),
                        ),
                        TextButton(
                          onPressed: () => unawaited(
                            renameWorkspaceDialog(
                              context,
                              actions,
                              widget.i18n,
                              'a',
                              snapshot.byId('a')?.title ?? 'Synthetic project',
                            ),
                          ),
                          child: const Text('Rename workspace'),
                        ),
                        TextButton(
                          onPressed: () => unawaited(
                            deleteWorkspaceDialog(
                              context,
                              actions,
                              widget.i18n,
                              'a',
                              snapshot.byId('a')?.title ?? 'Synthetic project',
                            ),
                          ),
                          child: const Text('Delete workspace'),
                        ),
                        MessageActions(
                          text: 'Synthetic answer',
                          i18n: widget.i18n,
                          clockFirst: false,
                          onBranch: () async {
                            await actions.forkSession(
                              's1',
                              atSeq: 6,
                              open: true,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
          ),
          Text('Fixture action: ${actions.outcome}'),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    actions.reset();
                    view.setOrderBy(SessionOrderBy.updated, const {});
                  },
                  child: const Text('Reset'),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: actions.toggleRefusal,
                  child: Text(actions.refuse ? 'Allow' : 'Refuse'),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
