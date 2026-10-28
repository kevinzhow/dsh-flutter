import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import 'dsh_menu_follower.dart';
import 'dsh_recipes.g.dart';
import 'dsh_shell_chrome.dart';

/// Handle an anchor builder uses to open and close its panel.
class DshPanelController extends ChangeNotifier {
  bool _open = false;
  bool get isOpen => _open;

  void Function()? _toggle;
  VoidCallback? _close;

  void toggle() => _toggle?.call();

  void close() => _close?.call();

  void _set(bool open) {
    if (_open == open) return;
    _open = open;
    notifyListeners();
  }
}

/// Where the panel sits against its anchor.
enum DshPanelSide { bottom, top }

/// Horizontal edge the panel shares with its anchor.
enum DshPanelAlign { start, end }

/// A panel that floats over the app beside its anchor (dsh `Menu` portal and
/// the stat dialogs): [builder] draws the anchor, [panelBuilder] the card. It
/// closes on Escape, a press outside it, or [DshPanelController.close].
/// Positions come from the anchor's [LayerLink]; a card wider than the room
/// keeps its own size. Source menu viewport fitting is enabled by [menuViewport].
class DshAnchoredPanel extends StatefulWidget {
  const DshAnchoredPanel({
    super.key,
    required this.builder,
    required this.panelBuilder,
    this.side = DshPanelSide.bottom,
    this.align = DshPanelAlign.start,
    this.gap = DshMenuRecipe.anchorGap,
    this.controller,
    this.panelWidth,
    this.viewportMargin = DshMenuRecipe.portalMargin,
    this.menuViewport = false,
    this.domOffsetGeometry = false,
    this.frameOverlayTop,
    this.focusPanel = true,
    this.exclusiveGroup,
  });

  final Widget Function(BuildContext context, DshPanelController controller)
  builder;
  final Widget Function(BuildContext context, DshPanelController controller)
  panelBuilder;
  final DshPanelSide side;
  final DshPanelAlign align;
  final double gap;
  final DshPanelController? controller;

  /// A known popover width permits horizontal placement within the viewport.
  /// Omitted keeps the caller's intrinsic layout and anchor alignment.
  final double? panelWidth;
  final double viewportMargin;

  /// Use source menu portal fitting rather than unconstrained popover placement.
  final bool menuViewport;

  /// Match source portals that place with integer DOM offset dimensions and
  /// window inner dimensions. This affects placement, never the card's layout.
  final bool domOffsetGeometry;
  final double? frameOverlayTop;

  /// Static source stat dialogs retain focus on their trigger. Interactive
  /// menus keep their existing foreground focus ownership by default.
  final bool focusPanel;

  /// Sibling panels in this source family replace one another, including when
  /// a keyboard activates the sibling without a pointer-down event.
  final Object? exclusiveGroup;

  @override
  State<DshAnchoredPanel> createState() => _DshAnchoredPanelState();
}

class _DshAnchoredPanelState extends State<DshAnchoredPanel> {
  static final _activeByOverlay =
      Expando<Map<Object, _DshAnchoredPanelState>>();
  final LayerLink _link = LayerLink();
  late DshPanelController _controller;
  OverlayEntry? _entry;
  LocalHistoryEntry? _history;
  FocusNode? _previousFocus;
  final _panelFocus = FocusScopeNode(debugLabel: 'anchored panel');
  bool _refreshScheduled = false;
  bool _observingKeyboard = false;
  OverlayState? _overlay;
  Object? _openGroup;

  bool _onGlobalKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
    }
    // The source's document listener does not cancel the underlying key.
    return false;
  }

  void _forgetPanel() {
    if (_observingKeyboard) {
      HardwareKeyboard.instance.removeHandler(_onGlobalKey);
      _observingKeyboard = false;
    }
    final overlay = _overlay;
    final group = _openGroup;
    if (overlay != null && group != null) {
      final peers = _activeByOverlay[overlay];
      if (peers?[group] == this) peers?.remove(group);
    }
    _overlay = null;
    _openGroup = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshOverlay();
  }

  @override
  void didUpdateWidget(DshAnchoredPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshOverlay();
  }

  void _refreshOverlay() {
    if (_entry == null || _refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (mounted) _entry?.markNeedsBuild();
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DshPanelController();
    _controller._toggle = _toggle;
    _controller._close = _close;
  }

  @override
  void dispose() {
    _forgetPanel();
    _controller._toggle = null;
    _controller._close = null;
    _entry?.remove();
    _entry = null;
    final history = _history;
    _history = null;
    history?.remove();
    _panelFocus.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _toggle() => _entry == null ? _show() : _close();

  void _close() {
    if (_entry == null) return;
    _forgetPanel();
    _entry!.remove();
    _entry = null;
    _controller._set(false);
    final history = _history;
    _history = null;
    history?.remove();
    final previousFocus = _previousFocus;
    _previousFocus = null;
    if (previousFocus?.context != null && previousFocus!.canRequestFocus) {
      previousFocus.requestFocus();
    }
  }

  void _show() {
    final overlay = Overlay.of(context, rootOverlay: true);
    final group = widget.exclusiveGroup;
    if (group != null) {
      final peers = _activeByOverlay[overlay] ??= {};
      peers[group]?._close();
      peers[group] = this;
      _overlay = overlay;
      _openGroup = group;
    }
    _previousFocus = widget.focusPanel
        ? FocusManager.instance.primaryFocus
        : null;
    if (!widget.focusPanel) {
      HardwareKeyboard.instance.addHandler(_onGlobalKey);
      _observingKeyboard = true;
    }
    final end = widget.align == DshPanelAlign.end;
    final top = widget.side == DshPanelSide.top;
    double shiftX = 0;
    double? width;
    final requested = widget.panelWidth;
    if (requested != null) {
      final screen = MediaQuery.sizeOf(context);
      final margin = widget.viewportMargin;
      width = requested.clamp(
        0,
        (screen.width - margin * 2).clamp(0, screen.width),
      );
      final box = context.findRenderObject()! as RenderBox;
      final anchor = box.localToGlobal(Offset.zero);
      final left = end ? anchor.dx + box.size.width - width : anchor.dx;
      final clamped = left.clamp(
        margin,
        (screen.width - margin - width).clamp(margin, screen.width),
      );
      shiftX = clamped - left;
    }
    _entry = OverlayEntry(
      builder: (context) => InheritedTheme.captureAll(
        this.context,
        ShellScope(
          chrome: ShellScope.of(this.context),
          child: FrameInsetsScope(
            insets: FrameInsetsScope.of(this.context),
            child: Builder(
              builder: (context) => FocusScope(
                node: _panelFocus,
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent ||
                      event.logicalKey != LogicalKeyboardKey.escape) {
                    return KeyEventResult.ignored;
                  }
                  _close();
                  return KeyEventResult.handled;
                },
                child: Stack(
                  children: [
                    if (widget.menuViewport)
                      Positioned.fill(
                        child: DshMenuFollower(
                          link: _link,
                          alignEnd: end,
                          above: top,
                          frameOverlayTop:
                              widget.frameOverlayTop ??
                              FrameInsetsScope.of(this.context).overlayTop,
                          gap: widget.gap,
                          viewportMargin: widget.viewportMargin,
                          domOffsetGeometry: widget.domOffsetGeometry,
                          child: TapRegion(
                            groupId: this,
                            child: widget.panelBuilder(context, _controller),
                          ),
                        ),
                      )
                    else
                      CompositedTransformFollower(
                        link: _link,
                        targetAnchor: Alignment(end ? 1 : -1, top ? -1 : 1),
                        followerAnchor: Alignment(end ? 1 : -1, top ? 1 : -1),
                        offset: Offset(shiftX, top ? -widget.gap : widget.gap),
                        child: TapRegion(
                          groupId: this,
                          child: width == null
                              ? widget.panelBuilder(context, _controller)
                              : SizedBox(
                                  width: width,
                                  child: widget.panelBuilder(
                                    context,
                                    _controller,
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
    // A FocusScopeNode cannot defer a request made before it is attached.
    // Pointer-opened panels may start with only the route scope focused.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _entry != null && widget.focusPanel) {
        _panelFocus.requestFocus();
      }
    });
    _history = LocalHistoryEntry(
      onRemove: () {
        _history = null;
        _close();
      },
    );
    ModalRoute.of(context)?.addLocalHistoryEntry(_history!);
    _controller._set(true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => PopScope(
      canPop: !_controller.isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: TapRegion(
        groupId: this,
        enabled: _controller.isOpen,
        onTapOutside: (_) => _close(),
        child: CompositedTransformTarget(
          link: _link,
          child: widget.builder(context, _controller),
        ),
      ),
    ),
  );
}
