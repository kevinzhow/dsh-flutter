/// The desktop sidebar's browsing region (dsh `ui-workspace` `WorkspaceBrowser`):
/// the section header with search, view options and "Add workspace", the
/// Workspace groups with their Session rows, the flat list, and the search
/// results. Drag reordering, row menus and hover cards are not drawn.
library;

import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_theme/dsh_theme.dart' show DshThemeData;
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'tree.dart';
import 'view_state.dart';

/// Debounce of the host content search (dsh `SEARCH_DEBOUNCE_MS`).
const Duration searchDebounce = Duration(milliseconds: 250);

/// The host's content-search answer.
class RemoteSearchResult {
  const RemoteSearchResult(this.items, this.hasMore);
  final List<ContentMatch> items;
  final bool hasMore;
}

enum _RemoteStatus { idle, loading, ready, error }

/// Copy of the browser: the `workspace` namespace, then `common` (where dsh
/// keeps a few labels the namespace itself lacks).
String browserText(
  DshI18n i18n,
  String key, [
  Map<String, Object?> params = const {},
]) {
  try {
    final text = i18n.t('workspace', key, params: params);
    if (text != key) return text;
  } on Object {
    // fall through to the shared dictionary
  }
  return i18n.t('common', key, params: params);
}

/// The browsing region of the sidebar.
class WorkspaceBrowser extends StatefulWidget {
  const WorkspaceBrowser({
    super.key,
    required this.snapshot,
    required this.workspaces,
    required this.view,
    required this.i18n,
    required this.currentId,
    required this.onOpen,
    this.rowState = const SessionRowState(),
    this.statuses = const {},
    this.wide = true,
    this.onExpand,
    this.onStartInWorkspace,
    this.addControl,
    this.addKeys,
    this.searchKeys,
    this.newKeys,
    this.search,
    this.resultLimit = 50,
    this.now,
    this.workspaceReady = true,
  });

  final SessionListSnapshot snapshot;
  final List<TreeWorkspace> workspaces;
  final WorkspaceViewState view;
  final DshI18n i18n;

  /// The Session in the main panel (null while a global panel covers it).
  final String? currentId;
  final ValueChanged<String> onOpen;
  final SessionRowState rowState;
  final Map<String, SessionStatusFacts> statuses;

  /// The wide column; false draws the rail's two icon controls.
  final bool wide;

  /// Widen the column from the rail (a search there opens the wide column).
  final VoidCallback? onExpand;

  /// Start a Session in a real Workspace (the row's hover button).
  final ValueChanged<String>? onStartInWorkspace;

  /// The add-workspace control (dsh's header button and its directory flow),
  /// drawn at the given edge, glyph size and glyph colour token; null hides it.
  final Widget Function(double box, double icon, String inkToken)? addControl;
  final List<String>? addKeys;
  final List<String>? searchKeys;
  final List<String>? newKeys;

  /// The host's content search; null: titles and workspaces only.
  final Future<RemoteSearchResult> Function(String query)? search;
  final int resultLimit;
  final DateTime Function()? now;

  /// Whether the Workspace baseline arrived (rows wait for it).
  final bool workspaceReady;

  @override
  State<WorkspaceBrowser> createState() => _WorkspaceBrowserState();
}

class _WorkspaceBrowserState extends State<WorkspaceBrowser> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  bool _searchExpanded = false;
  _RemoteStatus _remote = _RemoteStatus.idle;
  List<ContentMatch> _remoteItems = const [];
  bool _remoteMore = false;
  Timer? _debounce;
  int _searchSeq = 0;
  final Map<String, num> _watermarks = {};

  String get _normalized => _query.text.replaceAll('\u0000', '').trim();

  @override
  void initState() {
    super.initState();
    widget.view.addListener(_changed);
    _seenSearchRequest = widget.view.searchRequest;
    _query.addListener(_queryChanged);
  }

  @override
  void didUpdateWidget(WorkspaceBrowser old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view) {
      old.view.removeListener(_changed);
      widget.view.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.view.removeListener(_changed);
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int _seenSearchRequest = 0;

  void _changed() {
    if (!mounted) return;
    if (widget.view.searchRequest != _seenSearchRequest) {
      _seenSearchRequest = widget.view.searchRequest;
      _openSearch();
      return;
    }
    setState(() {});
  }

  void _queryChanged() {
    final q = _normalized;
    _debounce?.cancel();
    final seq = ++_searchSeq;
    final search = widget.search;
    if (q.isEmpty || search == null) {
      setState(() {
        _remote = _RemoteStatus.idle;
        _remoteItems = const [];
        _remoteMore = false;
      });
      return;
    }
    setState(() {
      _remote = _RemoteStatus.loading;
      _remoteItems = const [];
    });
    _debounce = Timer(searchDebounce, () async {
      try {
        final result = await search(q);
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _remote = _RemoteStatus.ready;
          _remoteItems = result.items;
          _remoteMore = result.hasMore;
        });
      } on Object {
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _remote = _RemoteStatus.error;
          _remoteItems = const [];
        });
      }
    });
  }

  String _t(String key, [Map<String, Object?> params = const {}]) =>
      browserText(widget.i18n, key, params);

  /// The pin and archive sets the host reports, with the viewer's archived
  /// choice.
  SessionRowState get _rowState => SessionRowState(
    pinned: widget.rowState.pinned,
    archived: widget.rowState.archived,
    filter: widget.view.archivedFilter,
  );

  void _openSearch() {
    if (!widget.wide) widget.onExpand?.call();
    setState(() => _searchExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _closeSearch() {
    _query.clear();
    setState(() => _searchExpanded = false);
  }

  // ---- ordering -----------------------------------------------------------

  Map<String, SessionListEntry> get _byId => {
    for (final e in widget.snapshot.items) e.sessionId: e,
  };

  String? get _currentBlank {
    final id = widget.currentId;
    if (id == null) return null;
    final e = _byId[id];
    return e != null && e.summary.blank ? id : null;
  }

  List<String> _orderOf(
    Iterable<String> members,
    String accountKey,
    Map<String, SessionListEntry> byId,
  ) {
    final base = widget.view.orderBy == SessionOrderBy.updated
        ? orderByRecency(members, byId)
        : reconcileManualOrder(
            members,
            widget.view.sessionOrderByAccount[accountKey],
            byId,
            _rowState,
          );
    final blank = _currentBlank;
    return pinCurrentBlank(
      base,
      blank != null && members.contains(blank) ? blank : null,
    );
  }

  List<TreeWorkspace> _orderedWorkspaces(Map<String, SessionListEntry> byId) =>
      [
        for (final w in widget.workspaces)
          TreeWorkspace(
            workspaceId: w.workspaceId,
            title: w.title,
            path: w.path,
            createdAt: w.createdAt,
            sessionIds: _orderOf(w.sessionIds, w.workspaceId, byId),
          ),
      ];

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final wide = widget.wide;
    final children = <Widget>[
      _header(context),
      Expanded(
        child: Stack(
          children: [
            if (wide) Positioned.fill(child: _body(context)),
            if (wide)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 24,
                child: IgnorePointer(
                  child: DshDecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          theme
                              .color('--dsw-specific-sidebar-fill')
                              .withAlpha(0),
                          theme.color('--dsw-specific-sidebar-fill'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _header(BuildContext context) {
    final theme = context.dsh;
    final wide = widget.wide;
    final flat = widget.view.groupBy == SessionGroupBy.flat;
    if (!wide) {
      // The rail: the add control, then search, each a 36px circle with a 12px
      // rhythm below (dsh `.rail .sectionHeader` and `.rail .search`).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.addControl != null) ...[
            _addControl(36, 18, '--dsw-alias-label-primary'),
            const SizedBox(height: 12),
          ],
          _IconControl(
            key: const ValueKey('browser-search'),
            icon: DshShellIcons.searchRegular,
            size: 18,
            box: 36,
            label: _t('search.sessions.aria'),
            tooltip: _t('search'),
            keys: widget.searchKeys,
            ink: theme.labelPrimary,
            onPressed: _openSearch,
          ),
        ],
      );
    }
    final label = DshChromeText(
      flat ? _t('section.sessions') : _t('section.workspaces'),
      key: const ValueKey('browser-title'),
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: theme
          .textStyle('--dsw-font-s-14')
          .copyWith(
            color: theme.color('--dsw-alias-label-tertiary'),
            height: 20 / 14,
          ),
    );
    final search = _SearchField(
      expanded: _searchExpanded,
      controller: _query,
      focus: _focus,
      placeholder: _t('search.placeholder'),
      label: _t('search.sessions.aria'),
      tooltip: _t('search'),
      keys: widget.searchKeys,
      clearLabel: _t('search.clear'),
      onOpen: _openSearch,
      onClear: _closeSearch,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: _searchExpanded
              ? search
              : Row(
                  children: [
                    Flexible(child: label),
                    const Spacer(),
                    search,
                    const SizedBox(width: 4),
                    _viewOptions(context),
                    if (widget.addControl != null) ...[
                      const SizedBox(width: 4),
                      _addControl(28, 16, '--dsw-alias-label-secondary'),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _addControl(double box, double icon, String ink) => DshTooltip(
    key: const ValueKey('browser-add'),
    label: _t('workspace.add'),
    shortcutKeys: widget.addKeys,
    side: DshTooltipSide.bottom,
    delay: const Duration(milliseconds: 500),
    child: widget.addControl!(box, icon, ink),
  );

  Widget _viewOptions(BuildContext context) {
    final theme = context.dsh;
    final v = widget.view;
    final entries = <DshMenuEntry>[
      DshMenuLabel('group-by', _t('groupBy.label')),
      DshMenuItem(
        'workspace',
        _t('groupBy.workspace'),
        icon: DshShellIcons.folderClose,
      ),
      DshMenuItem(
        'workspace-tree',
        _t('groupBy.workspaceTree'),
        icon: DshShellIcons.workspaceTree,
      ),
      DshMenuItem('flat', _t('groupBy.flat'), icon: DshShellIcons.flatList),
      const DshMenuSeparator('order-by-separator'),
      DshMenuLabel('order-by', _t('orderBy.label')),
      DshMenuItem(
        'manual',
        _t('orderBy.manual'),
        icon: DshShellIcons.chevronsUpDown,
      ),
      DshMenuItem('updated', _t('orderBy.updated'), icon: DshShellIcons.clock),
      const DshMenuSeparator('archived-filter-separator'),
      DshMenuLabel('filter-by', _t('filterBy.label')),
      DshMenuItem(
        'hide-archived',
        _t('viewOptions.hideArchived'),
        icon: DshShellIcons.archiveOff,
      ),
      DshMenuItem(
        'show-archived',
        _t('viewOptions.showArchived'),
        icon: DshIcons.chatLines,
      ),
      DshMenuItem(
        'only-archived',
        _t('viewOptions.onlyArchived'),
        icon: DshShellIcons.archiveCheck,
      ),
    ];
    return DshMenu(
      align: DshMenuAlign.end,
      dense: true,
      minWidth: 200,
      entries: entries,
      selectedIds: [
        switch (v.groupBy) {
          SessionGroupBy.workspace => 'workspace',
          SessionGroupBy.workspaceTree => 'workspace-tree',
          SessionGroupBy.flat => 'flat',
        },
        v.orderBy.name,
        switch (v.archivedFilter) {
          ArchivedFilter.hide => 'hide-archived',
          ArchivedFilter.show => 'show-archived',
          ArchivedFilter.only => 'only-archived',
        },
      ],
      onSelect: (id) {
        switch (id) {
          case 'workspace':
            v.setGroupBy(SessionGroupBy.workspace);
          case 'workspace-tree':
            v.setGroupBy(SessionGroupBy.workspaceTree);
          case 'flat':
            v.setGroupBy(SessionGroupBy.flat);
          case 'manual':
            v.setOrderBy(SessionOrderBy.manual, _activeOrders());
          case 'updated':
            v.setOrderBy(SessionOrderBy.updated, const {});
          case 'hide-archived':
            v.setArchivedFilter(ArchivedFilter.hide);
          case 'show-archived':
            v.setArchivedFilter(ArchivedFilter.show);
          case 'only-archived':
            v.setArchivedFilter(ArchivedFilter.only);
        }
      },
      builder: (context, menu) => _IconControl(
        key: const ValueKey('browser-view-options'),
        icon: DshShellIcons.slidersTwo,
        size: 16,
        box: 28,
        label: _t('viewOptions.label'),
        tooltip: _t('viewOptions.label'),
        ink: theme.color('--dsw-alias-label-secondary'),
        onPressed: menu.toggle,
      ),
    );
  }

  Map<String, List<String>> _activeOrders() {
    final byId = _byId;
    final accounted = {for (final w in widget.workspaces) ...w.sessionIds};
    final current = widget.currentId;
    final stray = [
      for (final e in widget.snapshot.items)
        if (!accounted.contains(e.sessionId) &&
            (!e.summary.blank || e.sessionId == current))
          e.sessionId,
    ];
    return {
      for (final w in _orderedWorkspaces(byId)) w.workspaceId: w.sessionIds,
      ungroupedKey: _orderOf(stray, ungroupedKey, byId),
      flatOrderKey: _orderOf(
        sessionMemberIds(widget.snapshot.items, current),
        flatOrderKey,
        byId,
      ),
    };
  }

  Widget _body(BuildContext context) {
    final q = _normalized;
    if (q.isNotEmpty) return _results(context, q);
    return widget.view.groupBy == SessionGroupBy.flat
        ? _flat(context)
        : _tree(context);
  }

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  // ---- search results -----------------------------------------------------

  Widget _results(BuildContext context, String q) {
    final theme = context.dsh;
    final set = deriveSearchResults(
      items: widget.snapshot.items,
      workspaces: widget.workspaces,
      query: q,
      rowState: _rowState,
      statuses: widget.statuses,
      content: _remoteItems,
      contentHasMore: _remoteMore,
      limit: widget.resultLimit,
      current: widget.currentId,
    );
    final note = TextStyle(color: theme.color('--dsw-alias-label-tertiary'))
        .merge(theme.textStyle('--dsw-font-xxs-12').copyWith(height: 18 / 12));
    return ListView(
      key: const ValueKey('browser-results'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final r in set.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _SearchRow(
              result: r,
              selected: r.id == widget.currentId,
              untitled: _t('session.untitled'),
              ungrouped: _t('group.ungrouped'),
              onTap: () {
                _closeSearch();
                widget.onOpen(r.id);
              },
            ),
          ),
        if (_remote == _RemoteStatus.loading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: DshChromeText(_t('search.pending'), style: note),
          )
        else if (set.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: DshChromeText(
              _t('search.noMatches'),
              key: const ValueKey('browser-no-matches'),
              style: note,
            ),
          )
        else if (set.hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: DshChromeText(_t('search.hasMore'), style: note),
          ),
      ],
    );
  }

  // ---- flat list ----------------------------------------------------------

  Widget _flat(BuildContext context) {
    final byId = _byId;
    final current = widget.currentId;
    final order = _orderOf(
      sessionMemberIds(widget.snapshot.items, current),
      flatOrderKey,
      byId,
    );
    final rows = deriveFlat(
      items: widget.snapshot.items,
      sessionIds: order,
      rowState: _rowState,
      statuses: widget.statuses,
      current: current,
    );
    return ListView(
      key: const ValueKey('browser-list'),
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (rows.isEmpty) _empty(context),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _sessionRow(r, 0),
          ),
      ],
    );
  }

  // ---- tree ---------------------------------------------------------------

  Widget _tree(BuildContext context) {
    final byId = _byId;
    final current = widget.currentId;
    final workspaces = _orderedWorkspaces(byId);
    final nest = widget.view.groupBy == SessionGroupBy.workspaceTree;
    final keysByPath = {for (final w in workspaces) w.path: w.workspaceId};
    final paths = keysByPath.keys.toList();
    final parents = <String, String?>{
      if (nest)
        for (final w in workspaces)
          w.workspaceId: () {
            final p = owningParentFolder(w.path, paths);
            return p == null ? null : keysByPath[p];
          }(),
    };
    final currentGroup = current == null
        ? null
        : owningGroupKey(workspaces, current);
    // The group holding the open Session opens once, unless the user chose.
    if (currentGroup != null &&
        !widget.view.groupExpansion.containsKey(currentGroup)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.view.setGroupExpanded(currentGroup, true);
      });
    }
    final ancestorKeys = {for (final p in parents.values) ?p};
    final expanded = {
      for (final k in [...workspaces.map((w) => w.workspaceId), ungroupedKey])
        if (widget.view.groupExpansion[k] ?? ancestorKeys.contains(k)) k,
    };
    final accounted = {for (final w in workspaces) ...w.sessionIds};
    final stray = [
      for (final e in widget.snapshot.items)
        if (!accounted.contains(e.sessionId)) e.sessionId,
    ];
    final groups = deriveGroups(
      items: widget.snapshot.items,
      workspaces: workspaces,
      rowState: _rowState,
      statuses: widget.statuses,
      expandedGroups: expanded,
      current: current,
      ungroupedOrder: _orderOf(stray, ungroupedKey, byId),
    );
    final ancestors = <String>{};
    for (
      var k = currentGroup == null ? null : parents[currentGroup];
      k != null;
      k = parents[k]
    ) {
      ancestors.add(k);
    }
    final rendered = {for (final g in groups) g.key};
    final children = <String?, List<GroupNode>>{};
    for (final g in groups) {
      var parent = parents[g.key];
      while (parent != null && !rendered.contains(parent)) {
        parent = parents[parent];
      }
      (children[parent] ??= []).add(g);
    }
    Widget group(GroupNode g, int depth) {
      final nested = g.expanded
          ? [
              for (final c in children[g.key] ?? const <GroupNode>[])
                group(c, depth + 1),
            ]
          : const <Widget>[];
      final baseline = requiredWatermark(g.sessions, current, null);
      final floor = baseline > sessionWatermarkBase
          ? baseline
          : sessionWatermarkBase;
      final watermark = _watermarks[g.key] ?? floor;
      final shown = watermarkRows(
        g.sessions,
        watermark < floor ? floor : watermark,
      );
      final collapsed = watermarkRows(g.sessions, floor);
      final expandedAll = shown.hidden == 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProjectRow(
              key: ValueKey('workspace-row-${g.key}'),
              group: g,
              label: g.workspaceId == null ? _t('group.ungrouped') : g.label,
              active:
                  ancestors.contains(g.key) ||
                  (g.expanded && g.containsCurrent),
              indent: depth * 12.0,
              newLabel: _t('actions.newSession'),
              newAria: _t('actions.newSession.aria', {
                'name': g.workspaceId == null ? _t('group.ungrouped') : g.label,
              }),
              newKeys: widget.newKeys,
              onNew: g.workspaceId == null || widget.onStartInWorkspace == null
                  ? null
                  : () {
                      widget.view.setGroupExpanded(g.key, true);
                      widget.onStartInWorkspace!(g.workspaceId!);
                    },
              onToggle: () {
                if (g.expanded) _watermarks.remove(g.key);
                widget.view.setGroupExpanded(g.key, !g.expanded);
              },
            ),
            ...nested.map(
              (w) => Padding(padding: const EdgeInsets.only(top: 2), child: w),
            ),
            for (final s in shown.rows)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _sessionRow(s, depth * 12.0),
              ),
            if (collapsed.hidden > 0)
              _OverflowButton(
                key: ValueKey('overflow-${g.key}'),
                indent: depth * 12.0,
                text: expandedAll
                    ? _t('sessions.collapse')
                    : _t('sessions.expand', {'n': shown.hidden}),
                onTap: () => setState(() {
                  if (expandedAll) {
                    _watermarks.remove(g.key);
                  } else {
                    _watermarks[g.key] = shown.hidden <= sessionWatermarkBase
                        ? double.infinity
                        : watermark + sessionWatermarkBase;
                  }
                }),
              ),
          ],
        ),
      );
    }

    return ListView(
      key: const ValueKey('browser-list'),
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (groups.isEmpty) _empty(context),
        for (final g in children[null] ?? const <GroupNode>[]) group(g, 0),
      ],
    );
  }

  Widget _sessionRow(SessionNode node, double indent) => _SessionRow(
    key: ValueKey('session-row-${node.id}'),
    node: node,
    indent: indent,
    selected: node.id == widget.currentId,
    now: _now,
    i18n: widget.i18n,
    onTap: () => widget.onOpen(node.id),
  );

  Widget _empty(BuildContext context) {
    final theme = context.dsh;
    final archivedOnly = _rowState.filter == ArchivedFilter.only;
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final style = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(color: tertiary, height: 20 / 13);
    if (widget.snapshot.phase == ListPhase.pending) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 80, 12, 0),
      child: Column(
        key: const ValueKey('browser-empty'),
        children: [
          DshIcon(
            archivedOnly ? DshShellIcons.archive : DshIcons.chatLines,
            size: 24,
            color: theme.color('--dsw-alias-label-caption'),
          ),
          const SizedBox(height: 12),
          DshChromeText(
            archivedOnly ? _t('empty.noneArchived') : _t('empty.none'),
            style: style,
          ),
          if (archivedOnly) ...[
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.view.setArchivedFilter(ArchivedFilter.hide),
              child: DshChromeText(
                _t('empty.viewOthers'),
                style: style.copyWith(color: theme.color('--dsw-alias-link')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- header controls --------------------------------------------------------

class _IconControl extends StatefulWidget {
  const _IconControl({
    super.key,
    required this.icon,
    required this.size,
    required this.box,
    required this.label,
    required this.tooltip,
    required this.ink,
    required this.onPressed,
    this.keys,
  });

  final DshIconData icon;
  final double size;
  final double box;
  final String label;
  final String tooltip;
  final List<String>? keys;
  final Color ink;
  final VoidCallback onPressed;

  @override
  State<_IconControl> createState() => _IconControlState();
}

class _IconControlState extends State<_IconControl> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshTooltip(
      label: widget.tooltip,
      shortcutKeys: widget.keys,
      side: DshTooltipSide.bottom,
      delay: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: widget.label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: DshContainer(
              width: widget.box,
              height: widget.box,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hover ? theme.interactiveBgHover : null,
                borderRadius: BorderRadius.circular(
                  widget.box > 28 ? theme.radiusMd : theme.radiusSm,
                ),
              ),
              child: DshIcon(widget.icon, size: widget.size, color: widget.ink),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.expanded,
    required this.controller,
    required this.focus,
    required this.placeholder,
    required this.label,
    required this.tooltip,
    required this.keys,
    required this.clearLabel,
    required this.onOpen,
    required this.onClear,
  });

  final bool expanded;
  final TextEditingController controller;
  final FocusNode focus;
  final String placeholder;
  final String label;
  final String tooltip;
  final List<String>? keys;
  final String clearLabel;
  final VoidCallback onOpen;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    if (!expanded) {
      return _IconControl(
        key: const ValueKey('browser-search'),
        icon: DshShellIcons.searchRegular,
        size: 14,
        box: 28,
        label: label,
        tooltip: tooltip,
        keys: keys,
        ink: theme.color('--dsw-alias-label-secondary'),
        onPressed: onOpen,
      );
    }
    final hairline = dshHairlineOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => OverflowBox(
        minWidth: constraints.maxWidth + 4,
        maxWidth: constraints.maxWidth + 4,
        child: _openField(context, theme, hairline),
      ),
    );
  }

  Widget _openField(BuildContext context, DshThemeData theme, double hairline) {
    return DshContainer(
      key: const ValueKey('browser-search-open'),
      height: 30,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: Border.all(
          color: theme.color('--dsw-alias-border-l4'),
          width: hairline,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Center(
              child: DshIcon(
                DshShellIcons.searchRegular,
                size: 11,
                color: theme.color('--dsw-alias-label-caption'),
              ),
            ),
          ),
          Expanded(
            child: EditableText(
              key: const ValueKey('browser-search-input'),
              controller: controller,
              focusNode: focus,
              maxLines: 1,
              inputFormatters: const [],
              style: theme
                  .textStyle('--dsw-font-xs-13')
                  .copyWith(color: theme.labelPrimary, height: 18 / 13),
              cursorColor: theme.labelPrimary,
              backgroundCursorColor: theme.color('--dsw-alias-border-l4'),
              onSubmitted: (_) {},
            ),
          ),
          GestureDetector(
            key: const ValueKey('browser-search-clear'),
            behavior: HitTestBehavior.opaque,
            onTap: onClear,
            child: Semantics(
              button: true,
              label: clearLabel,
              child: SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: DshIcon(
                    DshShellIcons.closeFill,
                    size: 14,
                    color: theme.color('--dsw-alias-label-secondary'),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ---- rows --------------------------------------------------------------------

class _ProjectRow extends StatefulWidget {
  const _ProjectRow({
    super.key,
    required this.group,
    required this.label,
    required this.active,
    required this.indent,
    required this.newLabel,
    required this.newAria,
    required this.newKeys,
    required this.onNew,
    required this.onToggle,
  });

  final GroupNode group;
  final String label;
  final bool active;
  final double indent;
  final String newLabel;
  final String newAria;
  final List<String>? newKeys;
  final VoidCallback? onNew;
  final VoidCallback onToggle;

  @override
  State<_ProjectRow> createState() => _ProjectRowState();
}

class _ProjectRowState extends State<_ProjectRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final g = widget.group;
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final folder = DshIcon(
      g.expanded ? DshShellIcons.folderOpen : DshShellIcons.folderClose,
      size: 16,
      color: widget.active
          ? theme.color('--dsw-alias-state-business-primary')
          : tertiary,
    );
    final arrow = AnimatedRotation(
      turns: g.expanded ? 0.25 : 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      child: DshIcon(
        DshShellIcons.triangleRightFill,
        size: 16,
        color: theme.color('--dsw-alias-label-caption'),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        expanded: g.expanded,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: DshContainer(
            height: 34,
            padding: EdgeInsets.only(left: 8 + widget.indent, right: 8),
            decoration: BoxDecoration(
              color: _hover ? theme.interactiveBgHover : null,
              borderRadius: BorderRadius.circular(theme.radiusMd),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 20,
                  child: Center(child: _hover ? arrow : folder),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: DshChromeText(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .copyWith(color: theme.labelPrimary, height: 20 / 14),
                  ),
                ),
                if (_hover && widget.onNew != null)
                  DshTooltip(
                    label: widget.newLabel,
                    shortcutKeys: widget.newKeys,
                    side: DshTooltipSide.bottom,
                    delay: const Duration(milliseconds: 500),
                    child: Semantics(
                      button: true,
                      label: widget.newAria,
                      child: GestureDetector(
                        key: const ValueKey('workspace-row-new'),
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onNew,
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: DshIcon(
                            DshShellIcons.newChatRegular,
                            size: 16,
                            color: tertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String relativeLabel(DshI18n i18n, num updatedAt, DateTime now) {
  String t(String key, [Map<String, Object?> p = const {}]) =>
      browserText(i18n, key, p);
  final diff = (now.millisecondsSinceEpoch - updatedAt.toInt()).clamp(
    0,
    1 << 62,
  );
  const minute = 60000;
  const hour = 3600000;
  const day = 86400000;
  if (diff < minute) return t('time.now');
  if (diff < hour) return t('time.minutes', {'n': diff ~/ minute});
  if (diff < day) return t('time.hours', {'n': diff ~/ hour});
  if (diff < 30 * day) return t('time.days', {'n': diff ~/ day});
  if (diff < 365 * day) return t('time.months', {'n': diff ~/ (30 * day)});
  return t('time.years', {'n': diff ~/ (365 * day)});
}

DshStateDotState? _dotOf(SessionNode n) {
  if (n.pending != null) return DshStateDotState.warning;
  if (n.running || n.runningSubagents > 0) return DshStateDotState.ongoing;
  if (n.completed) return DshStateDotState.done;
  return null;
}

class _SessionRow extends StatefulWidget {
  const _SessionRow({
    super.key,
    required this.node,
    required this.indent,
    required this.selected,
    required this.now,
    required this.i18n,
    required this.onTap,
  });

  final SessionNode node;
  final double indent;
  final bool selected;
  final DateTime now;
  final DshI18n i18n;
  final VoidCallback onTap;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final n = widget.node;
    String t(String key, [Map<String, Object?> p = const {}]) =>
        browserText(widget.i18n, key, p);
    final title = n.blank
        ? t('session.new')
        : (n.title.isEmpty ? t('session.untitled') : n.title);
    final dot = n.archived || n.blank ? null : _dotOf(n);
    final ink = n.archived
        ? theme.color('--dsw-alias-label-caption')
        : theme.labelPrimary;
    final time = n.pending == null
        ? relativeLabel(widget.i18n, n.updatedAt, widget.now)
        : switch (n.pending!) {
            PendingInteraction.approval => t('status.compact.approval'),
            PendingInteraction.planReview => t('status.compact.planReview'),
            PendingInteraction.question => t('status.compact.answer'),
          };
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: title,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: DshContainer(
            height: 32,
            padding: EdgeInsets.only(left: 8 + widget.indent, right: 8),
            decoration: BoxDecoration(
              color: widget.selected || _hover
                  ? theme.interactiveBgHover
                  : null,
              borderRadius: BorderRadius.circular(theme.radiusMd),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 20,
                  child: dot == null ? null : Center(child: DshStateDot(dot)),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: DshChromeText(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .copyWith(color: ink, height: 20 / 14),
                  ),
                ),
                if (!n.blank) ...[
                  const SizedBox(width: 6),
                  DshChromeText(
                    time,
                    maxLines: 1,
                    style: theme
                        .fixedTextStyle(size: 10, line: 16)
                        .copyWith(
                          color: theme.color('--dsw-alias-label-tertiary'),
                        ),
                  ),
                  if (n.pinned && !n.archived) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 16,
                      height: 20,
                      child: Center(
                        child: DshIcon(
                          DshShellIcons.pinFill,
                          size: 14,
                          color: theme.color('--dsw-alias-label-caption'),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverflowButton extends StatelessWidget {
  const _OverflowButton({
    super.key,
    required this.indent,
    required this.text,
    required this.onTap,
  });

  final double indent;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 28 + indent),
                child: DshChromeText(
                  text,
                  style: theme
                      .textStyle('--dsw-font-xxs-12')
                      .copyWith(
                        color: theme.color('--dsw-alias-label-tertiary'),
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchRow extends StatefulWidget {
  const _SearchRow({
    required this.result,
    required this.selected,
    required this.untitled,
    required this.ungrouped,
    required this.onTap,
  });

  final SearchResultNode result;
  final bool selected;
  final String untitled;
  final String ungrouped;
  final VoidCallback onTap;

  @override
  State<_SearchRow> createState() => _SearchRowState();
}

class _SearchRowState extends State<_SearchRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final r = widget.result;
    final dot = r.archived
        ? null
        : r.pending != null
        ? DshStateDotState.warning
        : r.running
        ? DshStateDotState.ongoing
        : r.completed
        ? DshStateDotState.done
        : null;
    final ink = r.archived
        ? theme.color('--dsw-alias-label-caption')
        : theme.labelPrimary;
    final meta = theme.textStyle('--dsw-font-xxs-12').copyWith(height: 17 / 12);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: DshContainer(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: widget.selected || _hover ? theme.interactiveBgHover : null,
            borderRadius: BorderRadius.circular(theme.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 20,
                    child: dot == null ? null : Center(child: DshStateDot(dot)),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: DshChromeText(
                      r.title.isEmpty ? widget.untitled : r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme
                          .textStyle('--dsw-font-s-14')
                          .copyWith(color: ink, height: 20 / 14),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Row(
                  children: [
                    Flexible(
                      flex: r.snippet == null ? 1 : 2,
                      child: DshChromeText(
                        r.workspace.isEmpty ? widget.ungrouped : r.workspace,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta.copyWith(
                          color: r.archived
                              ? theme.color('--dsw-alias-label-caption')
                              : theme.color('--dsw-alias-label-tertiary'),
                        ),
                      ),
                    ),
                    if (r.snippet != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        flex: 3,
                        child: DshChromeText(
                          r.snippet!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: meta.copyWith(
                            color: r.archived
                                ? theme.color('--dsw-alias-label-caption')
                                : theme.color('--dsw-alias-label-secondary'),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
