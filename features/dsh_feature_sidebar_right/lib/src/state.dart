import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/foundation.dart';

/// One open tab of a session's sidebar.
class SidebarTab {
  const SidebarTab({
    required this.id,
    required this.kind,
    required this.contentId,
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

  /// What the opener passed (`{shellPath}` for a terminal chosen on the guide).
  final Map<String, Object?> params;
  final int? line;
  final int revision;

  SidebarTab navigated(int? line, int revision) => SidebarTab(
    id: id,
    kind: kind,
    contentId: contentId,
    params: params,
    line: line,
    revision: revision,
  );
}

/// The tab kind of the workspace file tree, of a file preview and of the guide
/// (dsh's start page).
const String filesTabKind = 'files';
const String textTabKind = 'text';
const String guideTabKind = 'guide';

/// The sidebar of one session (dsh's per-session docking state, reduced to a
/// tab list: the tree, the previews and pages the person opened).
class SidebarState extends ChangeNotifier implements SidebarTabActions {
  SidebarState(this.sessionId, {SidebarTabTypes? types})
    : _types = types ?? SidebarTabTypes();

  final String sessionId;
  final SidebarTabTypes _types;

  final List<SidebarTab> tabs = [
    const SidebarTab(
      id: 'files',
      kind: filesTabKind,
      contentId: 'sidebar://files',
    ),
  ];
  String activeId = 'files';

  /// Whether the inline column is shown (wide windows). The sheet on phones is
  /// a route and keeps no flag here.
  bool inlineOpen = false;
  int _revision = 0;
  int _pages = 0;

  SidebarTab get active => tabs.firstWhere((t) => t.id == activeId);

  /// Whether the strip offers the add control: not while a guide is open (dsh
  /// draws it only while its pane holds none).
  bool get canAddTab => !tabs.any((t) => t.kind == guideTabKind);

  /// Open [address]; a file address reuses the tab already showing it and
  /// navigates it to [line].
  @override
  void openResource(String address, {int? line}) {
    if (parseSessionFileAddress(address) == null) return;
    _revision++;
    final index = tabs.indexWhere((t) => t.contentId == address);
    if (index >= 0) {
      tabs[index] = tabs[index].navigated(line, _revision);
      activeId = tabs[index].id;
    } else {
      final tab = SidebarTab(
        id: 'text-${tabs.length}-$_revision',
        kind: textTabKind,
        contentId: address,
        line: line,
        revision: _revision,
      );
      tabs.add(tab);
      activeId = tab.id;
    }
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
    final replaceIndex = replaceTabId == null
        ? -1
        : tabs.indexWhere((t) => t.id == replaceTabId);
    if (!multiple) {
      final existing = tabs.indexWhere((t) => t.kind == kind);
      if (existing >= 0) {
        if (replaceIndex >= 0 && replaceIndex != existing) {
          tabs.removeAt(replaceIndex);
        }
        activeId = tabs.firstWhere((t) => t.kind == kind).id;
        notifyListeners();
        return;
      }
    }
    _revision++;
    final n = ++_pages;
    final tab = SidebarTab(
      id: '$kind-$n',
      kind: kind,
      contentId: 'sidebar://$kind/$n',
      params: params,
      revision: _revision,
    );
    if (replaceIndex > 0) {
      tabs[replaceIndex] = tab;
    } else {
      tabs.add(tab);
    }
    activeId = tab.id;
    notifyListeners();
  }

  void select(String id) {
    if (activeId == id || !tabs.any((t) => t.id == id)) return;
    activeId = id;
    notifyListeners();
  }

  /// Close a tab (the file tree stays). A type with a close handler takes over
  /// its cleanup first (a terminal's process ends in the background).
  void close(String id) {
    final index = tabs.indexWhere((t) => t.id == id);
    if (index <= 0) return;
    final tab = tabs[index];
    _types.typeOf(tab.kind)?.onClose?.call(sessionId, tab.id, tab.contentId);
    tabs.removeAt(index);
    if (activeId == id) {
      activeId = tabs[(index - 1).clamp(0, tabs.length - 1)].id;
    }
    notifyListeners();
  }

  void setInlineOpen(bool open) {
    if (inlineOpen == open) return;
    inlineOpen = open;
    notifyListeners();
  }
}
