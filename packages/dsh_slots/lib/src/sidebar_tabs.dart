/// What a sidebar tab type is (dsh `ctx.sidebarRightTabs.register`): the static
/// declaration other features make so the sidebar can open, list and close
/// their tabs without importing them. Pure Dart; the bodies, titles and guide
/// cards are the slot occupants under the same `kind`.
class SidebarTabType {
  const SidebarTabType({
    required this.kind,
    this.multiple = false,
    this.guideOrder,
    this.onClose,
  });

  /// The tab kind (`files`, `text`, `terminal`).
  final String kind;

  /// Independent instances may be open at once (terminals); an ordinary page
  /// type opens once.
  final bool multiple;

  /// Where the type's card stands on the guide page; null lists no card.
  final int? guideOrder;

  /// Called when a tab of this kind is closed, before it goes (dsh
  /// `registerCloseHandler`): the owner takes over any cleanup. It must not
  /// throw for an ordinary close.
  final void Function(String sessionId, String tabId, String contentId)?
  onClose;
}

/// The registry of [SidebarTabType]s (dsh's `ctx.sidebarRightTabs`).
class SidebarTabTypes {
  final Map<String, SidebarTabType> _types = {};

  /// Declare a tab type. A kind is declared once.
  void Function() register(SidebarTabType type) {
    if (_types.containsKey(type.kind)) {
      throw StateError('sidebar tab type "${type.kind}" is already registered');
    }
    _types[type.kind] = type;
    return () {
      if (identical(_types[type.kind], type)) _types.remove(type.kind);
    };
  }

  SidebarTabType? typeOf(String kind) => _types[kind];

  /// The types with a guide card, in card order.
  List<SidebarTabType> get guideTypes =>
      [
        for (final t in _types.values)
          if (t.guideOrder != null) t,
      ]..sort((a, b) {
        final byOrder = a.guideOrder!.compareTo(b.guideOrder!);
        return byOrder != 0 ? byOrder : a.kind.compareTo(b.kind);
      });
}
