/// The cross-plugin panel-action face behind dsh's `ctx.layout`
/// (`ui-layout` `service.ts`): main-panel selection, navigation supersession,
/// the sidebar toggle and the right column reports. Writes stay inside the
/// store's declared action set.
library;

import 'layout_store.dart';

/// An abort signal for an asynchronous UI navigation (dsh hands out an
/// `AbortSignal`).
class NavigationSignal {
  bool _aborted = false;

  /// Whether a later navigation, a valid panel selection or disposal superseded this one.
  bool get aborted => _aborted;
}

/// `ctx.layout`.
class LayoutController {
  LayoutController(this._store, this._hasMainPanel);

  final LayoutStore _store;
  final bool Function(MainPanelId id) _hasMainPanel;
  NavigationSignal _navigation = NavigationSignal();

  /// Selected central panel and its change notifications.
  LayoutStore get store => _store;

  PanelInfo get panelInfo => _store.panelInfo;

  /// Select a global central panel without changing the current Session, or
  /// `null` for the Conversation. Throws [StateError] when the main key is not
  /// registered; the current selection and any pending navigation are kept.
  void selectPanel(MainPanelId? panelId) {
    if (panelId != null && !_hasMainPanel(panelId)) {
      throw StateError(
        'layout.selectPanel: main panel "$panelId" is not registered',
      );
    }
    _navigation._aborted = true;
    _store.selectPanel(panelId);
  }

  /// Start an asynchronous navigation, superseding any earlier pending one.
  NavigationSignal beginNavigation() {
    _navigation._aborted = true;
    _navigation = NavigationSignal();
    return _navigation;
  }

  /// Invalidate pending navigations when the layout owner is unloaded.
  void dispose() => _navigation._aborted = true;

  /// Toggle the sidebar panel (closed and contract default width).
  void toggleSidebar() => _store.toggleSidebar();

  /// Close the narrow sidebar again (the phone drawer, the expanded rail).
  void closeNarrowSidebar() => _store.closeNarrow();

  /// Report the right panel's presentation: [track] whether the normal panel
  /// width reserves a grid track, including beneath a fullscreen overlay;
  /// [fullscreen] whether the panel covers the frame and hides its outer
  /// resize handle.
  void openRightbar(bool track, bool fullscreen) =>
      _store.openRightbar(track, fullscreen);

  /// Report the right panel as hidden: no track, no handle.
  void closeRightbar() => _store.closeRightbar();
}
