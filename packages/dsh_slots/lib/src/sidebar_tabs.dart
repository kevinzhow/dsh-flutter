/// What a sidebar tab type is (dsh `ctx.sidebarRightTabs.register`): the static
/// declaration other features make so the sidebar can open, list and close
/// their tabs without importing them. Pure Dart; the bodies, titles and guide
/// cards are the slot occupants under the same `kind`.
class SidebarTabType {
  const SidebarTabType({
    required this.kind,
    this.multiple = false,
    this.guideOrder,
    this.keepMounted = false,
    this.onClose,
    this.acceptsResource,
    this.titleForResource,
    this.restorable = false,
    this.persistParams,
  });

  /// The tab kind (`files`, `text`, `terminal`).
  final String kind;

  /// Opt-in: restoring this page must not create Host work (such as a shell).
  final bool restorable;

  /// Only explicitly declared durable bindings survive an application restart.
  /// Returning null rejects the record; transient navigation parameters stay in memory.
  final Map<String, Object?>? Function(Map<String, Object?>)? persistParams;

  /// A feature-owned address predicate; the sidebar stays independent of
  /// each resource protocol (plans, files and future preview providers).
  final bool Function(String address)? acceptsResource;
  final String Function(String address)? titleForResource;

  /// Independent instances may be open at once (terminals); an ordinary page
  /// type opens once.
  final bool multiple;

  /// Where the type's card stands on the guide page; null lists no card.
  final int? guideOrder;

  /// Whether a visited body stays mounted while another tab is in front (dsh
  /// `keepMounted`): a live terminal keeps its state.
  final bool keepMounted;

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

  SidebarTabType? typeForResource(String address) => _types.values
      .where((type) => type.acceptsResource?.call(address) ?? false)
      .firstOrNull;

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
