import 'dart:async';

import 'package:dsh_client/generated_workspace.dart' show WorkspaceView;

import 'session_manager.dart';
import 'session_summary.dart';
import 'workspace_list.dart';

/// How a new conversation chooses and opens its workspace and session (dsh
/// `UiWorkspaceService.startSession` / `openWorkspace` / `connectWorkspace`).
///
/// A newer navigation supersedes a pending one: its answer never opens a
/// session over the newer choice.
class WorkspaceNavigation {
  WorkspaceNavigation({
    required WorkspaceList workspaces,
    required SessionManager sessions,
    required String? Function() current,
    required Future<void> Function(String sessionId) show,
    required void Function() clear,
    required void Function(Object error) onFailure,
  }) : _workspaces = workspaces,
       _sessions = sessions,
       _current = current,
       _show = show,
       _clear = clear,
       _onFailure = onFailure;

  final WorkspaceList _workspaces;
  final SessionManager _sessions;
  final String? Function() _current;
  final Future<void> Function(String sessionId) _show;
  final void Function() _clear;
  final void Function(Object error) _onFailure;

  int _navigation = 0;
  final Map<String, Future<String>> _connecting = {};

  /// The workspace with the most recent activity (dsh `recentWorkspace`): the
  /// latest `updatedAt` of its sessions, or its creation time when none of
  /// them is listed; the earlier row wins a tie.
  static String? recentWorkspace(
    List<WorkspaceView> items,
    Map<String, SessionSummary> byId,
  ) {
    String? selected;
    num? selectedTime;
    for (final workspace in items) {
      num? latest;
      for (final id in workspace.sessionIds) {
        final updated = byId[id]?.updatedAt;
        if (updated != null && (latest == null || updated > latest)) {
          latest = updated;
        }
      }
      latest ??= DateTime.tryParse(workspace.createdAt)?.millisecondsSinceEpoch
          .toDouble();
      latest ??= double.negativeInfinity;
      if (selected == null || latest > selectedTime!) {
        selected = workspace.workspaceId;
        selectedTime = latest;
      }
    }
    return selected;
  }

  Map<String, SessionSummary> get _byId => {
    for (final e in _sessions.list.value.items) e.sessionId: e.summary,
  };

  /// New session ("+"): a fresh session in [workspaceId], else in the workspace
  /// of the session in view, else in the most recent workspace. With none to
  /// choose from the view clears, which shows the workspace chooser.
  Future<void> startSession([String? workspaceId]) async {
    final snapshot = _workspaces.value;
    final current = _current();
    final currentWorkspace = current == null
        ? null
        : snapshot.ofSession(current)?.workspaceId;
    final ready =
        snapshot.phase == WorkspacePhase.ready &&
        _sessions.list.value.phase == ListPhase.ready;
    final recent = ready ? recentWorkspace(snapshot.items, _byId) : null;
    final target = workspaceId ?? currentWorkspace ?? recent;
    if (target == null) {
      _navigation++;
      _clear();
      return;
    }
    await _open(target, reuse: false);
  }

  /// Pick a workspace for the conversation being prepared: its first reusable
  /// blank session opens, else a new one. [beforeOpen] runs with the session
  /// about to show (the draft moves over there).
  Future<void> openWorkspace(
    String workspaceId, {
    void Function(String sessionId)? beforeOpen,
  }) => _open(workspaceId, reuse: true, beforeOpen: beforeOpen);

  /// The session of [workspaceId]'s first reusable blank row, or a new one.
  Future<String> connectWorkspace(String workspaceId) =>
      _connect(workspaceId, reuse: true);

  Future<void> _open(
    String workspaceId, {
    required bool reuse,
    void Function(String sessionId)? beforeOpen,
  }) async {
    final navigation = ++_navigation;
    final String sessionId;
    try {
      sessionId = await _connect(workspaceId, reuse: reuse);
    } on Object catch (error) {
      if (navigation == _navigation) _onFailure(error);
      rethrow;
    }
    if (navigation != _navigation) return;
    beforeOpen?.call(sessionId);
    await _show(sessionId);
  }

  Future<String> _connect(String workspaceId, {required bool reuse}) {
    final workspace = _workspaces.value.byId(workspaceId);
    if (workspace == null) {
      return Future.error(
        StateError('workspace navigation: unknown workspace $workspaceId'),
      );
    }
    if (!reuse) return _create(workspaceId);
    return _connecting[workspaceId] ??=
        _create(workspaceId, blank: _blankOf(workspace)).whenComplete(() {
          // A block body: returning the removed future would make it wait on itself.
          _connecting.remove(workspaceId);
        });
  }

  String? _blankOf(WorkspaceView workspace) {
    final archived = _workspaces.value.archivedSessionIds;
    for (final entry in _sessions.list.value.items) {
      final s = entry.summary;
      if (s.blank &&
          s.cwd == workspace.path &&
          workspace.sessionIds.contains(s.sessionId) &&
          !archived.contains(s.sessionId)) {
        return s.sessionId;
      }
    }
    return null;
  }

  Future<String> _create(String workspaceId, {String? blank}) async {
    final session = await _sessions.create(
      workspaceId: workspaceId,
      sessionId: blank,
      placeholderCwd: _workspaces.value.byId(workspaceId)?.path,
    );
    return session.sessionId;
  }
}
