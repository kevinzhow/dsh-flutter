/// Root-owned frame measurement, panel preferences and presentation reports
/// (dsh `ui-layout` `stores.ts`). The store is a plain snapshot holder with
/// synchronous listeners; actions replace the snapshot only when something
/// changed, and keep the untouched half (`panelInfo` or `layoutInfo`) at its
/// old identity so consumers can compare by reference.
library;

import 'dart:math' as math;

import 'columns.dart';

/// Identity shared by a sidebar panel entry and its main-slot occupant; the
/// reserved `conversation` key hosts the Conversation.
typedef MainPanelId = String;

/// The main key of the Conversation.
const String conversationPanelKey = 'conversation';

/// Root-scoped navigation state exposed to panel-aware components.
class PanelInfo {
  const PanelInfo({this.activePanelId});

  /// Selected global panel; null displays the current Conversation.
  final MainPanelId? activePanelId;

  @override
  bool operator ==(Object other) =>
      other is PanelInfo && other.activePanelId == activePanelId;

  @override
  int get hashCode => activePanelId.hashCode;
}

/// Frame measurements, width preferences and the right column's reports.
class LayoutInfo {
  const LayoutInfo({
    required this.sidebar,
    required this.viewportWidth,
    this.narrowExpanded = false,
    this.rightbar,
    this.rightbarShown = false,
    this.rightbarTrack = false,
    this.rightbarFullscreen = false,
    this.rightbarInstant = false,
  });

  /// Sidebar width preference in px; 0 is closed.
  final double sidebar;

  /// Last positive frame measurement; the window width bootstraps the first render.
  final double viewportWidth;

  /// A manual expansion below [sidebarAutoCollapse].
  final bool narrowExpanded;

  /// Saved right panel width in px, or null before its first opening. Resizing
  /// the frame and closing the panel preserve this preference.
  final double? rightbar;

  /// Whether the right panel is drawn at all, in either presentation. Derived
  /// chrome reported by its occupant; nothing else writes it.
  final bool rightbarShown;

  /// Whether the normal panel width reserves a grid track, including beneath
  /// fullscreen. Always false while hidden.
  final bool rightbarTrack;

  /// Reported fullscreen presentation; hides the outer resize handle.
  final bool rightbarFullscreen;

  /// Suppress transitions for a fullscreen exit until another geometry action.
  final bool rightbarInstant;

  LayoutInfo copyWith({
    double? sidebar,
    double? viewportWidth,
    bool? narrowExpanded,
    double? rightbar,
    bool? rightbarShown,
    bool? rightbarTrack,
    bool? rightbarFullscreen,
    bool? rightbarInstant,
  }) => LayoutInfo(
    sidebar: sidebar ?? this.sidebar,
    viewportWidth: viewportWidth ?? this.viewportWidth,
    narrowExpanded: narrowExpanded ?? this.narrowExpanded,
    rightbar: rightbar ?? this.rightbar,
    rightbarShown: rightbarShown ?? this.rightbarShown,
    rightbarTrack: rightbarTrack ?? this.rightbarTrack,
    rightbarFullscreen: rightbarFullscreen ?? this.rightbarFullscreen,
    rightbarInstant: rightbarInstant ?? this.rightbarInstant,
  );

  @override
  bool operator ==(Object other) =>
      other is LayoutInfo &&
      other.sidebar == sidebar &&
      other.viewportWidth == viewportWidth &&
      other.narrowExpanded == narrowExpanded &&
      other.rightbar == rightbar &&
      other.rightbarShown == rightbarShown &&
      other.rightbarTrack == rightbarTrack &&
      other.rightbarFullscreen == rightbarFullscreen &&
      other.rightbarInstant == rightbarInstant;

  @override
  int get hashCode => Object.hash(
    sidebar,
    viewportWidth,
    narrowExpanded,
    rightbar,
    rightbarShown,
    rightbarTrack,
    rightbarFullscreen,
    rightbarInstant,
  );

  @override
  String toString() =>
      'LayoutInfo(sidebar: $sidebar, viewportWidth: $viewportWidth, narrowExpanded: $narrowExpanded, '
      'rightbar: $rightbar, shown: $rightbarShown, track: $rightbarTrack, '
      'fullscreen: $rightbarFullscreen, instant: $rightbarInstant)';
}

/// One consistent reading of the store.
class LayoutSnapshot {
  const LayoutSnapshot({required this.panelInfo, required this.layoutInfo});

  final PanelInfo panelInfo;
  final LayoutInfo layoutInfo;
}

/// The layout store. For the sidebar the preference IS the width, so closing it
/// forgets its drag width: reopening restores the contract default. The right
/// panel initializes at 45% of the frame on first opening and keeps that px
/// preference across resizes and close. Drag writes clamp to the current
/// frame's range. Narrow sidebar toggles change only the expansion override;
/// opening the right panel clears that override.
class LayoutStore {
  LayoutStore({required double viewportWidth})
    : _snapshot = LayoutSnapshot(
        panelInfo: const PanelInfo(),
        layoutInfo: LayoutInfo(
          sidebar: sidebarDefault,
          viewportWidth: viewportWidth,
        ),
      );

  LayoutSnapshot _snapshot;
  final Set<void Function()> _listeners = {};

  LayoutSnapshot get snapshot => _snapshot;
  PanelInfo get panelInfo => _snapshot.panelInfo;
  LayoutInfo get layoutInfo => _snapshot.layoutInfo;

  /// Observe changes; returns the disposer.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _setLayout(LayoutInfo next) {
    if (next == _snapshot.layoutInfo) return;
    _snapshot = LayoutSnapshot(
      panelInfo: _snapshot.panelInfo,
      layoutInfo: next,
    );
    _notify();
  }

  void _setPanel(PanelInfo next) {
    if (next == _snapshot.panelInfo) return;
    _snapshot = LayoutSnapshot(
      panelInfo: next,
      layoutInfo: _snapshot.layoutInfo,
    );
    _notify();
  }

  void _notify() {
    for (final listener in [..._listeners]) {
      listener();
    }
  }

  /// Select a global panel; null selects the Conversation, and global panels
  /// keep the current Session intact.
  void selectPanel(MainPanelId? panelId) =>
      _setPanel(PanelInfo(activePanelId: panelId));

  /// Return to the Conversation when the selected main registration is gone.
  void retainMainPanels(Iterable<String> panelIds) {
    final active = panelInfo.activePanelId;
    if (active != null && !panelIds.contains(active)) {
      _setPanel(const PanelInfo());
    }
  }

  void setSidebar(double px) {
    final l = layoutInfo;
    _setLayout(
      _withInstant(
        l,
        false,
      ).copyWith(sidebar: clampWidth(px, sidebarMin, sidebarMax)),
    );
  }

  /// Narrow toggles flip only the override: the width preference survives
  /// untouched, so re-widening restores the pre-squeeze layout.
  void toggleSidebar() {
    final l = _withInstant(layoutInfo, false);
    if (l.viewportWidth < sidebarAutoCollapse) {
      _setLayout(l.copyWith(narrowExpanded: !l.narrowExpanded));
    } else {
      _setLayout(l.copyWith(sidebar: l.sidebar == 0 ? sidebarDefault : 0));
    }
  }

  /// Close the narrow sidebar's override (the phone drawer, the rail's
  /// expansion): picking something in it ends it.
  void closeNarrow() {
    final l = layoutInfo;
    if (l.viewportWidth < sidebarAutoCollapse && l.narrowExpanded) {
      _setLayout(_withInstant(l, false).copyWith(narrowExpanded: false));
    }
  }

  /// Crossing the breakpoint in either direction drops the override: the narrow
  /// default is auto-collapsed, the wide state is the preference.
  void setViewportWidth(double width) {
    final l = layoutInfo;
    if (l.viewportWidth == width) return;
    var next = _withInstant(l, false);
    if ((l.viewportWidth < sidebarAutoCollapse) !=
        (width < sidebarAutoCollapse)) {
      next = next.copyWith(narrowExpanded: false);
    }
    _setLayout(next.copyWith(viewportWidth: width));
  }

  void setRightbar(double px) {
    final l = _withInstant(layoutInfo, false);
    _setLayout(
      l.copyWith(
        rightbar: clampWidth(
          px,
          rightbarMin,
          math.max(rightbarMin, l.viewportWidth * rightbarMaxRatio),
        ),
      ),
    );
  }

  /// Report the right panel's presentation without changing its expanded state.
  void openRightbar(bool track, bool fullscreen) {
    final l = layoutInfo;
    var next = l;
    if (!l.rightbarShown ||
        l.rightbarTrack != track ||
        l.rightbarFullscreen != fullscreen) {
      next = _withInstant(next, l.rightbarFullscreen && !fullscreen);
    }
    if (!l.rightbarShown && l.viewportWidth < sidebarAutoCollapse) {
      next = next.copyWith(narrowExpanded: false);
    }
    next = next.copyWith(
      rightbar:
          l.rightbar ??
          math.max(
            rightbarMin,
            jsRound(l.viewportWidth * rightbarDefaultRatio).toDouble(),
          ),
      rightbarShown: true,
      rightbarTrack: track,
      rightbarFullscreen: fullscreen,
    );
    _setLayout(next);
  }

  /// Report the right panel as hidden: no track, no handle.
  void closeRightbar() {
    final l = layoutInfo;
    var next = l;
    if (l.rightbarShown) next = _withInstant(next, l.rightbarFullscreen);
    _setLayout(
      next.copyWith(
        rightbarShown: false,
        rightbarTrack: false,
        rightbarFullscreen: false,
      ),
    );
  }

  static LayoutInfo _withInstant(LayoutInfo l, bool instant) =>
      l.rightbarInstant == instant ? l : l.copyWith(rightbarInstant: instant);
}
