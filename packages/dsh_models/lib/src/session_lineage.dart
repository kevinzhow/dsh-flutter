import 'session_manager.dart';

class SessionCrumb {
  const SessionCrumb(this.sessionId, this.title, {this.subagent = false});
  final String sessionId, title;
  final bool subagent;
}

/// Upstream header ancestry follows only subagent parentage. A fork's parent
/// is a list placement hint, not another header crumb. Missing parents and
/// cycles stop the walk without inventing hidden catalog entries.
List<SessionCrumb> deriveSessionAncestry(
  SessionListSnapshot list,
  String id, {
  required String untitled,
}) {
  final byId = {for (final row in list.items) row.sessionId: row};
  final chain = <SessionCrumb>[];
  final seen = <String>{};
  String? cursor = id;
  while (cursor != null && seen.add(cursor)) {
    final row = byId[cursor];
    if (row == null) break;
    chain.insert(
      0,
      SessionCrumb(
        cursor,
        row.title ?? untitled,
        subagent: row.summary.origin == 'subagent',
      ),
    );
    if (row.summary.origin != 'subagent') break;
    cursor = row.summary.parentSessionId;
  }
  return chain;
}
