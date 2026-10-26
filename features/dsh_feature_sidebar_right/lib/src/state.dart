import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/foundation.dart';

import 'dart:convert';

import 'persistence.dart';

/// One open tab of a session's sidebar.
class SidebarTab {
  const SidebarTab({
    required this.id,
    required this.kind,
    required this.contentId,
    this.title = '',
    this.params = const {},
    this.line,
    this.revision = 0,
  });

  final String id;

  /// `files`, `text` (a file preview), `guide` or a kind another feature
  /// registered (`terminal`).
  final String kind;

  /// The content address; `dsh-resource://file/session/<id>/<path>` for a file,
  /// `sidebar://<kind>/<n>` for a page.
  final String contentId;

  /// The text the chip shows unless the type draws its own title; captured when
  /// the tab opens.
  final String title;

  /// What the opener passed (`{shellPath}` for a terminal chosen on the guide).
  final Map<String, Object?> params;
  final int? line;
  final int revision;
}

/// The tab kind of the workspace file tree, of a file preview and of the guide
/// (dsh's start page).
const String filesTabKind = 'files';
const String textTabKind = 'text';
const String guideTabKind = 'guide';

class _Extra {
  _Extra({this.params = const {}, this.line, this.revision = 0});

  Map<String, Object?> params;
  int? line;
  int revision;
}

/// The sidebar of one session (dsh's per-session docking surface, reduced to
/// what Whalee offers): a [DockController] holding the tabs the person opened
/// in up to two panes, the expanded flag and the presentation, plus the
/// navigation facts a tab body reads (parameters, line, revision).
///
/// A session starts collapsed and empty; the expansion that would first show an
/// empty layout seeds the guide, as in dsh. A collapsed surface keeps its tabs.
class SidebarState extends ChangeNotifier implements SidebarTabBindingActions {
  SidebarState(
    this.sessionId, {
    SidebarTabTypes? types,
    String Function()? guideTitle,
    String? restored,
    void Function(String)? persist,
  }) : _types = types ?? SidebarTabTypes(),
       _guideTitle = guideTitle ?? (() => ''),
       _persist = persist {
    final saved = restoreSidebar(restored, _types);
    dock = DockController(
      DockControllerOptions(
        makePaneTab: _guide,
        maxPanes: 2,
        restored: saved?.surface,
      ),
    );
    if (saved != null) {
      for (final entry in saved.extras.entries) {
        _extras[entry.key] = _Extra(
          params: entry.value['params'] as Map<String, Object?>,
          line: entry.value['line'] as int?,
        );
      }
      for (final record in dock.snapshot.state.tabs.values) {
        final uri = Uri.tryParse(record.contentId);
        final page = uri == null
            ? null
            : int.tryParse(uri.pathSegments.lastOrNull ?? '');
        if (page != null && page > _pages) _pages = page;
      }
    }
    addListener(_save);
    _off = dock.subscribe(_dockChanged);
  }

  final String sessionId;
  final void Function(String)? _persist;

  bool _disposed = false;

  @override
  void rememberBinding(String tabId, Map<String, Object?> binding) {
    if (_disposed || !layout.tabs.containsKey(tabId)) return;
    final extra = _extras.putIfAbsent(tabId, _Extra.new);
    if (binding.entries.every((e) => extra.params[e.key] == e.value)) return;
    extra.params = Map.unmodifiable({...extra.params, ...binding});
    notifyListeners();
  }

  void _dockChanged() {
    // A dock duplicate keeps the same content binding, then owns its own
    // navigation fields even after the original tab closes.
    for (final record in layout.tabs.values) {
      if (_extras.containsKey(record.id)) continue;
      final source = layout.tabs.values
          .where(
            (t) =>
                t.id != record.id &&
                t.contentId == record.contentId &&
                _extras.containsKey(t.id),
          )
          .firstOrNull;
      if (source != null) {
        final extra = _extras[source.id]!;
        _extras[record.id] = _Extra(
          params: extra.params,
          line: extra.line,
          revision: ++_revision,
        );
      }
    }
    _extras.removeWhere((id, _) => !layout.tabs.containsKey(id));
    notifyListeners();
  }

  void _save() {
    final persist = _persist;
    if (persist == null) return;
    try {
      persist(
        jsonEncode({
          'version': 1,
          'surface': dock.savedLayout.toJson(),
          'extras': {
            for (final entry in _extras.entries)
              if (layout.tabs.containsKey(entry.key))
                entry.key: {
                  'params':
                      _types
                          .typeOf(layout.tabs[entry.key]!.kind)
                          ?.persistParams
                          ?.call(entry.value.params) ??
                      <String, Object?>{},
                  if (entry.value.line != null) 'line': entry.value.line,
                },
          },
        }),
      );
    } on Object {
      /* Persistence never retires a live tab. */
    }
  }

  final SidebarTabTypes _types;
  final String Function() _guideTitle;

  /// The docking surface this sidebar renders.
  late final DockController dock;
  late final void Function() _off;

  final Map<String, _Extra> _extras = {};
  int _revision = 0;
  int _pages = 0;

  TabRecord _guide(TabId id) => TabRecord(
    id: id,
    kind: guideTabKind,
    contentId: 'sidebar://guide/0',
    title: _guideTitle(),
  );

  LayoutState get layout => dock.snapshot.state;

  /// The tabs, pane by pane in visual order.
  List<SidebarTab> get tabs => [
    for (final pane in dockPaneIds(layout))
      for (final id in getPane(layout, pane).tabs) _tab(id),
  ];

  SidebarTab _tab(String id) {
    final record = layout.tabs[id]!;
    final extra = _extras[id];
    return SidebarTab(
      id: id,
      kind: record.kind,
      contentId: record.contentId,
      title: record.title,
      params: extra?.params ?? const {},
      line: extra?.line,
      revision: extra?.revision ?? 0,
    );
  }

  /// The id of the active tab of the active pane (empty when there is none).
  String get activeId =>
      getPane(layout, activeDockPaneId(layout)).activeTabId?.value ?? '';

  /// The tab in front in the active docked pane.
  SidebarTab get active => tabs.firstWhere((t) => t.id == activeId);

  /// Whether [tabId] is the one in front in its own pane.
  bool isFront(String tabId) {
    for (final pane in dockPaneIds(layout)) {
      if (getPane(layout, pane).activeTabId?.value == tabId) return true;
    }
    return false;
  }

  /// Whether the strip offers the add control in [paneId]: not while a guide is
  /// open there (dsh draws it only while its pane holds none).
  bool canAddTab(String paneId) => !getPane(
    layout,
    paneId,
  ).tabs.any((t) => layout.tabs[t]?.kind == guideTabKind);

  /// Whether the add control is on offer anywhere (the single-pane view).
  bool get canAddAnywhere => !tabs.any((t) => t.kind == guideTabKind);

  /// Whether [tabId] has a close control: the guide standing alone draws none.
  bool canClose(String tabId) {
    final all = tabs;
    final lone = all.length == 1 && all.first.id == tabId;
    return !(lone && layout.tabs[tabId]?.kind == guideTabKind);
  }

  /// Whether the column is expanded.
  bool get expanded => layout.expanded;

  /// Whether the panel covers the viewport (the recorded presentation).
  bool get fullscreen => layout.mode == DockMode.fullscreen;

  /// Expand or collapse the column. Expanding an empty surface seeds the guide.
  void setExpanded(bool value) {
    dock.setExpanded(value);
    if (value) dock.settle();
  }

  void toggleExpanded() => setExpanded(!expanded);

  void setFullscreen(bool value) =>
      dock.setMode(value ? DockMode.fullscreen : DockMode.push);

  void toggleFullscreen() => setFullscreen(!fullscreen);

  /// Whether the inline column is shown (kept for the callers of the first
  /// version of this state).
  bool get inlineOpen => expanded;

  void setInlineOpen(bool open) => setExpanded(open);

  /// Open [address]; a file address reuses the tab already showing it and
  /// navigates it to [line].
  @override
  void openResource(
    String address, {
    int? line,
    Map<String, Object?> params = const {},
  }) {
    final file = parseSessionFileAddress(address);
    final type = file == null ? _types.typeForResource(address) : null;
    if (file == null && type == null) return;
    if (layout.tabs.isEmpty) dock.settle();
    final id = dock.openContent(
      OpenContentInput(
        contentId: address,
        title: file != null
            ? pathPartsOf(file.path).name
            : type?.titleForResource?.call(address) ?? '',
        kind: file != null ? textTabKind : type!.kind,
      ),
    );
    _revision++;
    final extra = _extras.putIfAbsent(id, _Extra.new);
    extra.params = Map.unmodifiable(params);
    extra.line = line;
    extra.revision = _revision;
    notifyListeners();
  }

  /// Open a page of [kind] (dsh `openTab`). A page type opens once and a second
  /// open focuses it; a type that declared `multiple` (terminals) opens another
  /// instance. [replaceTabId] names the guide the page takes the place of.
  @override
  void openTab(
    String kind, {
    String? replaceTabId,
    Map<String, Object?> params = const {},
  }) {
    final type = _types.typeOf(kind);
    final multiple = type?.multiple ?? false;
    if (kind != guideTabKind && type == null && kind != filesTabKind) {
      throw StateError('no sidebar tab type "$kind" is registered');
    }
    if (layout.tabs.isEmpty) dock.settle();
    final replace =
        replaceTabId != null && layout.tabs.containsKey(replaceTabId)
        ? replaceTabId
        : null;
    if (!multiple) {
      final existing = layout.tabs.values
          .where((t) => t.kind == kind)
          .firstOrNull;
      if (existing != null) {
        if (replace != null && replace != existing.id) {
          _closeRecord(replace, runHandler: false);
        }
        final extra = _extras.putIfAbsent(existing.id, _Extra.new);
        extra.params = Map.unmodifiable(params);
        extra.revision = ++_revision;
        dock.focusTab(existing.id);
        notifyListeners();
        return;
      }
    }
    _revision++;
    final n = ++_pages;
    final contentId = 'sidebar://$kind/$n';
    // The page takes the place of the guide that offered it.
    PaneId? paneId;
    int? index;
    if (replace != null) {
      final pane = findTabPane(layout, TabId(replace));
      paneId = pane.paneId;
      index = pane.tabs.indexOf(TabId(replace));
    }
    final id = dock.openContent(
      OpenContentInput(
        contentId: contentId,
        title: _titleOf(kind),
        kind: kind,
        paneId: paneId,
        index: index,
        revealIfOpened: false,
      ),
    );
    _extras[id] = _Extra(params: params, revision: _revision);
    if (replace != null) _closeRecord(replace, runHandler: false);
    notifyListeners();
  }

  String _titleOf(String kind) => kind;

  void select(String id) {
    if (!layout.tabs.containsKey(id)) return;
    dock.focusTab(TabId(id));
  }

  /// Close a tab. A type with a close handler takes over its cleanup first (a
  /// terminal's process ends in the background). The guide standing alone is
  /// not closable; another tab standing alone closes with the column.
  void close(String id) {
    final record = layout.tabs[id];
    if (record == null || !canClose(id)) return;
    final lone = tabs.length == 1;
    _closeRecord(id);
    if (lone) {
      dock.setExpanded(false);
    } else {
      dock.settle(reseed: false);
    }
  }

  void _closeRecord(String id, {bool runHandler = true}) {
    final record = layout.tabs[id];
    if (record == null) return;
    if (runHandler) {
      _types
          .typeOf(record.kind)
          ?.onClose
          ?.call(sessionId, id, record.contentId);
    }
    _extras.remove(id);
    dock.closeTab(TabId(id));
  }

  @override
  void dispose() {
    _disposed = true;
    _off();
    removeListener(_save);
    super.dispose();
  }
}
