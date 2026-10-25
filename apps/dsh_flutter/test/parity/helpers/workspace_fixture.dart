import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_workspace.dart' as ws;
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/foundation.dart';

/// In-memory Host answers for native action replay. Real application routing
/// is exercised separately by workspace_management_flow_test.dart.
class SyntheticWorkspaceManagement extends ChangeNotifier
    implements WorkspaceManagement {
  SyntheticWorkspaceManagement() {
    reset();
  }
  static final now = DateTime.utc(2026, 10, 1, 12).millisecondsSinceEpoch;
  bool refuse = false, active = true;
  int forks = 0;
  String outcome = '';
  late List<ws.WorkspaceView> rows;
  late List<SessionListEntry> entries;
  List<String> archived = [], pinned = [];
  void reset() {
    rows = [
      for (final id in ['a', 'b'])
        ws.WorkspaceView(
          workspaceId: id,
          title: id == 'a' ? 'Synthetic project' : 'Second project',
          path: '/synthetic/$id',
          sessionIds: id == 'a' ? ['s1', 's2'] : ['s3'],
          createdAt: '2026-10-01T00:00:00.000Z',
          updatedAt: '2026-10-01T00:00:00.000Z',
        ),
    ];
    entries = [
      for (var i = 1; i <= 3; i++)
        SessionListEntry(
          SessionSummary(
            sessionId: 's$i',
            updatedAt: now - i * 60000,
            running: false,
            blank: false,
            agentAvailable: true,
            cwd: '/synthetic/a',
          ),
          'Synthetic session $i',
        ),
    ];
    archived = [];
    pinned = [];
    outcome = '';
    active = true;
    refuse = false;
    notifyListeners();
  }

  @override
  WorkspaceSnapshot get workspaces => WorkspaceSnapshot(
    items: rows,
    archivedSessionIds: archived,
    pinnedSessionIds: pinned,
    phase: WorkspacePhase.ready,
  );
  @override
  SessionListSnapshot get sessions =>
      SessionListSnapshot(items: entries, phase: ListPhase.ready);
  void toggleRefusal() {
    refuse = !refuse;
    notifyListeners();
  }

  void mutate(String action, void Function() write) {
    if (refuse) {
      // A one-shot refusal lets a real modal retry without a test backdoor.
      refuse = false;
      notifyListeners();
      throw RemoteException('fixture/refused', 'Synthetic refusal');
    }
    write();
    outcome = action;
    notifyListeners();
  }

  @override
  Future<void> renameSession(String id, String title) async =>
      mutate('rename:$id:$title', () {
        entries = [
          for (final row in entries)
            if (row.sessionId == id)
              SessionListEntry(row.summary, title)
            else
              row,
        ];
      });
  @override
  Future<String> forkSession(String id, {int? atSeq, bool open = false}) async {
    final child = 'fork-${++forks}';
    final source = entries.firstWhere((r) => r.sessionId == id);
    mutate('fork:$id:${atSeq ?? 'latest'}', () {
      entries = [
        ...entries,
        SessionListEntry(
          SessionSummary(
            sessionId: child,
            parentSessionId: id,
            updatedAt: now,
            running: false,
            blank: false,
            agentAvailable: true,
          ),
          increasedForkTitle(source.title ?? ''),
        ),
      ];
      rows = [
        for (final row in rows)
          if (row.sessionIds.contains(id))
            ws.WorkspaceView.fromJson({
              ...row.toJson(),
              'sessionIds': [...row.sessionIds, child],
            })
          else
            row,
      ];
    });
    return child;
  }

  @override
  Future<void> archiveSession(String id, {bool stopActivity = false}) async {
    if (active && !stopActivity) {
      throw RemoteException(
        'workspace/session-active',
        'Synthetic work is active',
        {
          'activity': [
            {
              'kind': 'job',
              'items': [
                {'id': 'job', 'label': 'Synthetic check'},
              ],
            },
          ],
        },
      );
    }
    mutate('archive:$id', () {
      active = false;
      archived = {...archived, id}.toList();
      pinned = pinned.where((v) => v != id).toList();
    });
  }

  @override
  Future<void> unarchiveSession(String id) async => mutate('unarchive:$id', () {
    archived = archived.where((v) => v != id).toList();
  });
  @override
  Future<void> pinSession(String id) async => mutate('pin:$id', () {
    pinned = [id, ...pinned.where((v) => v != id)];
  });
  @override
  Future<void> unpinSession(String id) async => mutate('unpin:$id', () {
    pinned = pinned.where((v) => v != id).toList();
  });
  @override
  Future<void> renameWorkspace(String id, String title) async =>
      mutate('workspace-rename:$id:$title', () {
        rows = [
          for (final row in rows)
            if (row.workspaceId == id)
              ws.WorkspaceView.fromJson({...row.toJson(), 'title': title})
            else
              row,
        ];
      });
  @override
  Future<void> deleteWorkspace(String id) async =>
      mutate('workspace-delete:$id', () {
        rows = rows.where((r) => r.workspaceId != id).toList();
      });
  @override
  Future<void> insertWorkspaceBefore(String id, String? before) async =>
      mutate('workspace-order:$id:${before ?? 'end'}', () {
        final moved = rows.firstWhere((r) => r.workspaceId == id);
        rows = rows.where((r) => r.workspaceId != id).toList();
        final index = before == null
            ? rows.length
            : rows.indexWhere((r) => r.workspaceId == before);
        rows.insert(index, moved);
      });
  @override
  Future<void> insertSessionBefore(
    String workspaceId,
    String id,
    String? before,
  ) async {
    throw StateError('Browser Session order must stay local');
  }

  @override
  Future<void> openSession(String id) async {
    outcome = 'open:$id';
    notifyListeners();
  }
}
