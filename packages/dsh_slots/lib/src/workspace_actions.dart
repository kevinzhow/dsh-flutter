import 'package:dsh_models/dsh_models.dart';

/// Injected Host operations shared by sidebar rows, the conversation header
/// and message-level branch controls. No feature imports another feature.
abstract interface class WorkspaceManagement {
  WorkspaceSnapshot get workspaces;
  SessionListSnapshot get sessions;
  Future<void> renameSession(String sessionId, String title);
  Future<String> forkSession(String sessionId, {int? atSeq, bool open = false});
  Future<void> archiveSession(String sessionId, {bool stopActivity = false});
  Future<void> unarchiveSession(String sessionId);
  Future<void> pinSession(String sessionId);
  Future<void> unpinSession(String sessionId);
  Future<void> renameWorkspace(String workspaceId, String title);
  Future<void> deleteWorkspace(String workspaceId);
  Future<void> insertWorkspaceBefore(
    String workspaceId,
    String? beforeWorkspaceId,
  );
  Future<void> insertSessionBefore(
    String workspaceId,
    String sessionId,
    String? beforeSessionId,
  );
  Future<void> openSession(String sessionId);
}
