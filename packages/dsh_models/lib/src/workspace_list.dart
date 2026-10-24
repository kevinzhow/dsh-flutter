import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_workspace.dart' as ws;

import 'observable.dart';

/// Arrival lifecycle of the workspace list (dsh `WorkspaceListPhase`).
enum WorkspacePhase { pending, ready }

/// One immutable view of the Host's workspaces (dsh `WorkspaceSnapshot`).
class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    this.items = const [],
    this.archivedSessionIds = const [],
    this.pinnedSessionIds = const [],
    this.phase = WorkspacePhase.pending,
    this.error,
  });

  /// Workspaces in the Host's display order.
  final List<ws.WorkspaceView> items;

  /// The registry-global archive set.
  final List<String> archivedSessionIds;

  /// The registry-global pin set, most recently pinned first.
  final List<String> pinnedSessionIds;
  final WorkspacePhase phase;

  /// The last failure of `workspace/create` or the follow stream, if any.
  final Object? error;

  ws.WorkspaceView? byId(String id) {
    for (final w in items) {
      if (w.workspaceId == id) return w;
    }
    return null;
  }

  /// The workspace that accounts [sessionId], if any.
  ws.WorkspaceView? ofSession(String sessionId) {
    for (final w in items) {
      if (w.sessionIds.contains(sessionId)) return w;
    }
    return null;
  }
}

/// The follow stream of the workspace registry (`workspace/follow`): the
/// opening frame of every connection generation, in the shape [WorkspaceList]
/// consumes.
typedef WorkspaceFollow = Stream<GenerationFrame> Function();

/// The client workspace list (dsh `ClientWorkspaceModel`, the part Whalee
/// uses): every generation opens with a complete baseline that replaces all
/// state; increments merge rows, order, and the archive and pin sets; a
/// `create` or `initializeDefault` answer is merged at once so the new row is
/// there before the stream echoes it. Host workspace ids are never reused, so
/// a removed id is never resurrected by delayed data.
class WorkspaceList {
  WorkspaceList({
    required ws.WorkspaceRemote remote,
    required WorkspaceFollow follow,
  }) : _remote = remote,
       _follow = follow;

  final ws.WorkspaceRemote _remote;
  final WorkspaceFollow _follow;
  final Observable<WorkspaceSnapshot> state = Observable(
    const WorkspaceSnapshot(),
  );
  final Set<String> _removed = {};
  StreamSubscription<GenerationFrame>? _sub;
  bool _disposed = false;

  WorkspaceSnapshot get value => state.value;

  /// Begin following the registry; every generation delivers its baseline.
  void start() {
    _sub ??= _follow().listen(
      _onFrame,
      onError: (Object e) {
        if (_disposed) return;
        state.set(_copy(error: e));
      },
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    await state.dispose();
  }

  void _onFrame(GenerationFrame frame) {
    if (_disposed) return;
    switch (frame) {
      case StreamOpened() || StreamEnded():
        return;
      case StreamItem(:final value):
        _apply(ws.WorkspaceFollowFrame.fromJson(value, 'workspace/follow'));
    }
  }

  void _apply(ws.WorkspaceFollowFrame frame) {
    switch (frame) {
      case ws.WorkspaceFollowFrameBaseline(:final value) ||
          ws.WorkspaceFollowFrameReplace(:final value):
        _removed.clear();
        state.set(
          WorkspaceSnapshot(
            items: List.unmodifiable(value.items),
            archivedSessionIds: List.unmodifiable(value.archivedSessionIds),
            pinnedSessionIds: List.unmodifiable(value.pinnedSessionIds),
            phase: WorkspacePhase.ready,
          ),
        );
      case ws.WorkspaceFollowFrameUpsert(:final workspace):
        _upsert(workspace);
      case ws.WorkspaceFollowFrameRemove(:final workspaceId):
        _removed.add(workspaceId);
        state.set(
          _copy(
            items: [
              for (final w in value.items)
                if (w.workspaceId != workspaceId) w,
            ],
          ),
        );
      case ws.WorkspaceFollowFrameOrder(:final workspaceIds):
        final byId = {for (final w in value.items) w.workspaceId: w};
        state.set(
          _copy(
            items: [
              for (final id in workspaceIds)
                if (byId[id] case final w?) w,
              for (final w in value.items)
                if (!workspaceIds.contains(w.workspaceId)) w,
            ],
          ),
        );
      case ws.WorkspaceFollowFrameArchived(:final archivedSessionIds):
        state.set(_copy(archived: archivedSessionIds));
      case ws.WorkspaceFollowFramePinned(:final pinnedSessionIds):
        state.set(_copy(pinned: pinnedSessionIds));
      case ws.WorkspaceFollowFrameUnrecognized():
        break;
    }
  }

  void _upsert(ws.WorkspaceView workspace) {
    if (_removed.contains(workspace.workspaceId)) return;
    final items = [...value.items];
    final at = items.indexWhere((w) => w.workspaceId == workspace.workspaceId);
    if (at >= 0) {
      items[at] = workspace;
    } else {
      items.add(workspace);
    }
    state.set(_copy(items: items));
  }

  WorkspaceSnapshot _copy({
    List<ws.WorkspaceView>? items,
    List<String>? archived,
    List<String>? pinned,
    Object? error,
  }) => WorkspaceSnapshot(
    items: items ?? value.items,
    archivedSessionIds: archived ?? value.archivedSessionIds,
    pinnedSessionIds: pinned ?? value.pinnedSessionIds,
    phase: value.phase,
    error: error,
  );

  /// Adopt an existing host directory as a workspace (`workspace/create`) and
  /// merge the answer. The Host resolves a directory that is already a
  /// workspace to that row; failures (`workspace/invalid-path`) throw.
  Future<ws.WorkspaceView> create(String path) async {
    final created = await _remote.create(ws.WorkspaceCreateRequest(path: path));
    _upsert(created.workspace);
    return created.workspace;
  }

  /// First-use initialization (`workspace/initializeDefault`): the default
  /// workspace, or null when the Host finds the account ineligible.
  Future<ws.WorkspaceView?> initializeDefault() async {
    final value = await _remote.initializeDefault();
    if (value == null) return null;
    _upsert(value.workspace);
    return value.workspace;
  }
}
