import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/foundation.dart';

/// One open tab of a session's sidebar.
class SidebarTab {
  const SidebarTab({
    required this.id,
    required this.kind,
    required this.contentId,
    this.line,
    this.revision = 0,
  });

  final String id;

  /// `files` or `text` (a file preview).
  final String kind;

  /// The content address; `dsh-resource://file/session/<id>/<path>` for a file.
  final String contentId;
  final int? line;
  final int revision;

  SidebarTab navigated(int? line, int revision) => SidebarTab(
    id: id,
    kind: kind,
    contentId: contentId,
    line: line,
    revision: revision,
  );
}

/// The tab kind of the workspace file tree, and of a file preview.
const String filesTabKind = 'files';
const String textTabKind = 'text';

/// The sidebar of one session (dsh's per-session docking state, reduced to a
/// tab list: the tree plus the previews the person opened).
class SidebarState extends ChangeNotifier implements SidebarTabActions {
  SidebarState(this.sessionId);

  final String sessionId;

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

  SidebarTab get active => tabs.firstWhere((t) => t.id == activeId);

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

  void select(String id) {
    if (activeId == id || !tabs.any((t) => t.id == id)) return;
    activeId = id;
    notifyListeners();
  }

  /// Close a tab (the file tree stays).
  void close(String id) {
    final index = tabs.indexWhere((t) => t.id == id);
    if (index <= 0) return;
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
