/// The workspace browser's tree (dsh `ui-workspace` `tree.ts`): Sessions
/// grouped by Workspace, ordered, filtered by the archived choice, with the
/// pure row facts the widgets draw. Nothing here touches Flutter.
library;

import 'package:dsh_models/dsh_models.dart';

/// Group key of Sessions outside every Workspace.
const String ungroupedKey = '';

/// Group key of the flat list's saved order.
const String flatOrderKey = '\u0000flat';

/// How the browser groups Sessions.
enum SessionGroupBy { workspace, workspaceTree, flat }

/// Session order selected by the browser.
enum SessionOrderBy { manual, updated }

/// Archived-row visibility: the default hides archived rows, `show` mixes them
/// into their kept slots, `only` restricts the view (and search) to them.
enum ArchivedFilter { hide, show, only }

/// One Workspace as the browser needs it (dsh `WorkspaceView`).
class TreeWorkspace {
  const TreeWorkspace({
    required this.workspaceId,
    required this.title,
    required this.path,
    required this.createdAt,
    required this.sessionIds,
  });

  final String workspaceId;
  final String title;
  final String path;

  /// Creation time, epoch ms.
  final int createdAt;
  final List<String> sessionIds;
}

/// Pin and archive sets plus the archived choice (dsh `SessionRowState`).
class SessionRowState {
  const SessionRowState({
    this.pinned = const [],
    this.archived = const [],
    this.filter = ArchivedFilter.hide,
  });

  final List<String> pinned;
  final List<String> archived;
  final ArchivedFilter filter;
}

/// A pending interaction with its own row presentation.
enum PendingInteraction { approval, planReview, question }

/// Live facts the list summary does not carry (dsh `SessionStatusSnapshot`).
class SessionStatusFacts {
  const SessionStatusFacts({
    this.running,
    this.pending,
    this.completionUnread = false,
    this.runningSubagents = 0,
  });

  final bool? running;
  final PendingInteraction? pending;
  final bool completionUnread;
  final int runningSubagents;
}

/// One top-level Session row.
class SessionNode {
  const SessionNode({
    required this.id,
    required this.title,
    required this.blank,
    required this.running,
    required this.runningSubagents,
    required this.completed,
    required this.pinned,
    required this.archived,
    required this.updatedAt,
    this.pending,
  });

  final String id;

  /// Stored title, or empty (the renderer localizes blank and unnamed labels).
  final String title;
  final bool blank;
  final PendingInteraction? pending;
  final bool running;
  final int runningSubagents;

  /// Finished running while not selected and not yet opened.
  final bool completed;
  final bool pinned;
  final bool archived;
  final num updatedAt;
}

/// One group section.
class GroupNode {
  const GroupNode({
    required this.key,
    required this.workspaceId,
    required this.cwd,
    required this.createdAt,
    required this.label,
    required this.sessionCount,
    required this.expanded,
    required this.containsCurrent,
    required this.sessions,
  });

  final String key;
  final String? workspaceId;
  final String? cwd;
  final int? createdAt;
  final String label;
  final int sessionCount;
  final bool expanded;
  final bool containsCurrent;

  /// Visible rows (empty while the group is folded).
  final List<SessionNode> sessions;
}

/// One flat search row.
class SearchResultNode {
  const SearchResultNode({
    required this.id,
    required this.title,
    required this.workspace,
    required this.running,
    required this.completed,
    required this.archived,
    this.pending,
    this.snippet,
  });

  final String id;
  final String title;
  final String workspace;
  final PendingInteraction? pending;
  final bool running;
  final bool completed;
  final bool archived;
  final String? snippet;
}

/// One content-search hit of the host (`session/search`).
class ContentMatch {
  const ContentMatch(this.sessionId, this.snippet);
  final String sessionId;
  final String? snippet;
}

/// Bounded merged search rows plus the refine-the-query hint.
class SearchResultSet {
  const SearchResultSet(this.items, this.hasMore);
  final List<SearchResultNode> items;
  final bool hasMore;
}

/// The basename of [cwd] (both separators), the raw path when it has none, or
/// empty for the ungrouped bucket.
String workspaceLabel(String? cwd) {
  if (cwd == null || cwd.isEmpty) return '';
  final trimmed = cwd.replaceAll(RegExp(r'[\\/]+$'), '');
  final cut = trimmed.lastIndexOf(RegExp(r'[\\/]'));
  final base = cut < 0 ? trimmed : trimmed.substring(cut + 1);
  return base.isEmpty ? cwd : base;
}

/// Known members newest first, identity as the deterministic tie-break.
List<String> orderByRecency(
  Iterable<String> sessionIds,
  Map<String, SessionListEntry> byId,
) {
  final known = [
    for (final id in sessionIds)
      if (byId[id] != null) id,
  ];
  known.sort((a, b) {
    final x = byId[a]!.summary.updatedAt;
    final y = byId[b]!.summary.updatedAt;
    if (x != y) return y.compareTo(x);
    return a.compareTo(b);
  });
  return known;
}

/// Saved relative positions plus missing members ordered by pin, fork source,
/// recency and archive status (dsh `reconcileManualOrder`).
List<String> reconcileManualOrder(
  Iterable<String> memberIds,
  List<String>? saved,
  Map<String, SessionListEntry> byId, [
  SessionRowState? rowState,
]) {
  final members = {for (final id in memberIds) id};
  final included = <String>{};
  final ordered = <String>[];
  for (final key in saved ?? const <String>[]) {
    if (!members.contains(key) || !included.add(key)) continue;
    ordered.add(key);
  }
  final archived = {...?rowState?.archived};
  final pins = <String>[];
  for (final id in rowState?.pinned ?? const <String>[]) {
    if (!members.contains(id) ||
        included.contains(id) ||
        archived.contains(id) ||
        byId[id] == null) {
      continue;
    }
    pins.add(id);
    included.add(id);
  }
  final ordinary = <String>[];
  final archives = <String>[];
  for (final id in orderByRecency(
    members.where((id) => !included.contains(id)),
    byId,
  )) {
    (archived.contains(id) ? archives : ordinary).add(id);
  }
  final result = [...pins, ...ordered, ...ordinary, ...archives];
  final pending = {...ordinary};
  void placeFork(String id) {
    if (!pending.remove(id)) return;
    final parent = byId[id]?.summary.parentSessionId;
    if (parent == null || parent == id || !result.contains(parent)) return;
    placeFork(parent);
    result.remove(id);
    result.insert(result.indexOf(parent), id);
  }

  for (final id in ordinary.reversed) {
    placeFork(id);
  }
  return result;
}

/// Keep the selected provisional New Session ahead of either base order.
List<String> pinCurrentBlank(List<String> order, String? currentBlank) {
  if (currentBlank == null) return [...order];
  return [currentBlank, ...order.where((id) => id != currentBlank)];
}

bool _visible(
  SessionListEntry entry,
  String? current,
  Set<String> archived,
  ArchivedFilter filter,
) {
  final s = entry.summary;
  if (s.origin == 'subagent') return false;
  if (s.blank && s.sessionId != current) return false;
  return switch (filter) {
    ArchivedFilter.hide => !archived.contains(s.sessionId),
    ArchivedFilter.show => true,
    ArchivedFilter.only => archived.contains(s.sessionId),
  };
}

String _sessionTitle(SessionListEntry e) =>
    e.summary.blank ? '' : (e.title?.trim() ?? '');

List<SessionListEntry> _sectionMembers(
  List<SessionListEntry> members,
  Set<String> pinned,
  Set<String> archived,
) {
  final placeholders = <SessionListEntry>[];
  final leading = <SessionListEntry>[];
  final rest = <SessionListEntry>[];
  for (final m in members) {
    if (m.summary.blank) {
      placeholders.add(m);
    } else if (!archived.contains(m.sessionId) &&
        pinned.contains(m.sessionId)) {
      leading.add(m);
    } else {
      rest.add(m);
    }
  }
  return [...placeholders, ...leading, ...rest];
}

SessionNode _node(
  SessionListEntry e,
  Map<String, SessionStatusFacts> statuses,
  Set<String> pinned,
  Set<String> archived,
) {
  final s = e.summary;
  final status = statuses[s.sessionId];
  return SessionNode(
    id: s.sessionId,
    title: _sessionTitle(e),
    blank: s.blank,
    running: status?.running ?? s.running,
    runningSubagents: status?.runningSubagents ?? 0,
    completed: status?.completionUnread ?? false,
    pinned: !archived.contains(s.sessionId) && pinned.contains(s.sessionId),
    archived: archived.contains(s.sessionId),
    updatedAt: s.updatedAt,
    pending: status?.pending,
  );
}

/// The Workspace group that owns [sessionId], or [ungroupedKey].
String owningGroupKey(List<TreeWorkspace> workspaces, String sessionId) {
  for (final w in workspaces) {
    if (w.sessionIds.contains(sessionId)) return w.workspaceId;
  }
  return ungroupedKey;
}

/// Group Sessions by Workspace: one group per Host-ordered Workspace with
/// members from its (caller-ordered) `sessionIds`, then the Ungrouped bucket
/// in [ungroupedOrder] (recency while unset). Sessions populate only under
/// expanded groups.
List<GroupNode> deriveGroups({
  required List<SessionListEntry> items,
  required List<TreeWorkspace> workspaces,
  required SessionRowState rowState,
  required Map<String, SessionStatusFacts> statuses,
  required Set<String> expandedGroups,
  required String? current,
  List<String>? ungroupedOrder,
}) {
  final byId = {for (final e in items) e.sessionId: e};
  final archived = {...rowState.archived};
  final pinned = {...rowState.pinned};
  final currentGroup = current == null
      ? null
      : owningGroupKey(workspaces, current);
  final raw =
      <
        ({
          String key,
          String? wid,
          String? cwd,
          int? at,
          String label,
          List<SessionListEntry> sessions,
        })
      >[];
  final accounted = <String>{};
  for (final w in workspaces) {
    final members = <SessionListEntry>[];
    for (final id in w.sessionIds) {
      final e = byId[id];
      if (e == null) continue;
      accounted.add(id);
      if (!_visible(e, current, archived, rowState.filter)) continue;
      members.add(e);
    }
    if (rowState.filter == ArchivedFilter.only && members.isEmpty) continue;
    raw.add((
      key: w.workspaceId,
      wid: w.workspaceId,
      cwd: w.path,
      at: w.createdAt,
      label: w.title,
      sessions: members,
    ));
  }
  final stray = [
    for (final e in items)
      if (!accounted.contains(e.sessionId) &&
          _visible(e, current, archived, rowState.filter))
        e,
  ];
  if (stray.isNotEmpty) {
    final ids = [for (final e in stray) e.sessionId];
    final order = ungroupedOrder == null
        ? orderByRecency(ids, byId)
        : reconcileManualOrder(ids, ungroupedOrder, byId);
    raw.add((
      key: ungroupedKey,
      wid: null,
      cwd: null,
      at: null,
      label: '',
      sessions: [for (final id in order) byId[id]!],
    ));
  }
  return [
    for (final g in raw)
      GroupNode(
        key: g.key,
        workspaceId: g.wid,
        cwd: g.cwd,
        createdAt: g.at,
        label: g.label,
        sessionCount: g.sessions.length,
        expanded: expandedGroups.contains(g.key),
        containsCurrent: g.key == currentGroup,
        sessions: expandedGroups.contains(g.key)
            ? [
                for (final e in _sectionMembers(g.sessions, pinned, archived))
                  _node(e, statuses, pinned, archived),
              ]
            : const [],
      ),
  ];
}

/// Flat rows from the complete ordered ids, pinned rows fronted.
List<SessionNode> deriveFlat({
  required List<SessionListEntry> items,
  required List<String> sessionIds,
  required SessionRowState rowState,
  required Map<String, SessionStatusFacts> statuses,
  required String? current,
}) {
  final byId = {for (final e in items) e.sessionId: e};
  final archived = {...rowState.archived};
  final pinned = {...rowState.pinned};
  final members = [
    for (final id in sessionIds)
      if (byId[id] case final e?
          when _visible(e, current, archived, rowState.filter))
        e,
  ];
  return [
    for (final e in _sectionMembers(members, pinned, archived))
      _node(e, statuses, pinned, archived),
  ];
}

/// Complete flat membership, independent of archive visibility.
List<String> sessionMemberIds(List<SessionListEntry> items, String? current) =>
    [
      for (final e in items)
        if (_visible(e, current, const {}, ArchivedFilter.show)) e.sessionId,
    ];

/// Merge immediate title and Workspace substring matches with ranked Host
/// content matches: local rows lead newest first, content-only rows keep the
/// host's order, duplicates take the host's snippet.
SearchResultSet deriveSearchResults({
  required List<SessionListEntry> items,
  required List<TreeWorkspace> workspaces,
  required String query,
  required SessionRowState rowState,
  required Map<String, SessionStatusFacts> statuses,
  required List<ContentMatch> content,
  required bool contentHasMore,
  required int limit,
  required String? current,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const SearchResultSet([], false);
  final byId = {for (final e in items) e.sessionId: e};
  final archived = {...rowState.archived};
  final workspaceBySession = <String, String>{};
  for (final w in workspaces) {
    for (final id in w.sessionIds) {
      workspaceBySession.putIfAbsent(id, () => w.title);
    }
  }
  String labelOf(SessionListEntry e) =>
      workspaceBySession[e.sessionId] ?? workspaceLabel(e.summary.cwd);
  final contentBy = <String, ContentMatch>{};
  for (final m in content) {
    contentBy.putIfAbsent(m.sessionId, () => m);
  }
  final local = <SessionListEntry>[];
  for (final e in items) {
    if (e.summary.blank || !_visible(e, current, archived, rowState.filter)) {
      continue;
    }
    if (_sessionTitle(e).toLowerCase().contains(q) ||
        labelOf(e).toLowerCase().contains(q)) {
      local.add(e);
    }
  }
  final ordered = <SessionListEntry>[];
  final included = <String>{};
  void include(SessionListEntry e) {
    if (included.add(e.sessionId)) ordered.add(e);
  }

  for (final id in orderByRecency([for (final e in local) e.sessionId], byId)) {
    include(byId[id]!);
  }
  for (final m in content) {
    final e = byId[m.sessionId];
    if (e != null &&
        !e.summary.blank &&
        _visible(e, current, archived, rowState.filter)) {
      include(e);
    }
  }
  return SearchResultSet([
    for (final e in ordered.take(limit))
      SearchResultNode(
        id: e.sessionId,
        title: _sessionTitle(e),
        workspace: labelOf(e),
        running: statuses[e.sessionId]?.running ?? e.summary.running,
        completed: statuses[e.sessionId]?.completionUnread ?? false,
        archived: archived.contains(e.sessionId),
        pending: statuses[e.sessionId]?.pending,
        snippet: contentBy[e.sessionId]?.snippet,
      ),
  ], contentHasMore || ordered.length > limit);
}

String _folderPath(String path) {
  final windows =
      RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path) || path.startsWith(r'\\');
  return (windows ? path.replaceAll(r'\', '/') : path).replaceAll(
    RegExp(r'/+$'),
    '',
  );
}

/// The nearest registered ancestor of [path] among [parents], excluding itself.
String? owningParentFolder(String path, List<String> parents) {
  final child = _folderPath(path);
  String? owner;
  var length = -1;
  for (final parent in parents) {
    final root = _folderPath(parent);
    if (root.length > length && child != root && child.startsWith('$root/')) {
      owner = parent;
      length = root.length;
    }
  }
  return owner;
}

/// First rows shown before "N more" (dsh `SESSION_WATERMARK_BASE`).
const int sessionWatermarkBase = 5;

/// Highest watermark that attention-bearing Sessions raise automatically.
const int sessionWatermarkAutoMax = 50;

/// The blank row plus the first [watermark] non-blank rows, in list order.
({List<SessionNode> rows, int hidden}) watermarkRows(
  List<SessionNode> sessions,
  num watermark,
) {
  var count = 0;
  final rows = [
    for (final s in sessions)
      if (s.blank || ++count <= watermark) s,
  ];
  return (rows: rows, hidden: sessions.length - rows.length);
}

/// Smallest watermark covering every attention-bearing row within the
/// automatic maximum (running, pending, completed, current or revealed).
int requiredWatermark(
  List<SessionNode> sessions,
  String? current,
  String? reveal,
) {
  var index = 0;
  var required = 0;
  for (final s in sessions) {
    if (s.blank) continue;
    index++;
    final attention =
        index <= sessionWatermarkAutoMax &&
        (s.running ||
            s.runningSubagents > 0 ||
            s.pending != null ||
            s.completed ||
            s.id == current);
    if (attention || s.id == reveal) required = index;
  }
  return required;
}

/// Apply a visible reorder to the complete account. Hidden/archived members
/// stay in their slots, blanks stay first, and the pinned block is a boundary.
List<String>? sessionDragOrder(
  List<String> order,
  List<SessionNode> rows,
  String sourceId,
  bool pinned,
  String targetId, {
  required bool after,
}) {
  final source = rows.where((r) => r.id == sourceId).firstOrNull;
  final target = rows.where((r) => r.id == targetId).firstOrNull;
  if (source == null ||
      target == null ||
      source.blank ||
      source.pinned != pinned ||
      target.pinned != pinned ||
      source.id == target.id ||
      !order.contains(source.id)) {
    return null;
  }
  final section = rows.where((r) => r.pinned == pinned).toList();
  final sourceIndex = section.indexOf(source);
  final without = section.where((r) => r.id != source.id).toList();
  final insertAt =
      without.indexWhere((r) => r.id == target.id) + (after ? 1 : 0);
  if (insertAt == sourceIndex) return null;
  final next = order.where((id) => id != source.id).toList();
  final targetIndex = next.indexOf(target.id);
  if (targetIndex == -1) return null;
  next.insert(targetIndex + (after ? 1 : 0), source.id);
  return pinCurrentBlank(next, rows.where((r) => r.blank).firstOrNull?.id);
}
