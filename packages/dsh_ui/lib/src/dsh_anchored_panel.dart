import 'package:flutter/widgets.dart';

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
/// closes on a press outside it and when [DshPanelController.close] is called.
/// Positions come from the anchor's [LayerLink]; a card wider than the room
/// keeps its own size and is not clamped here.
class DshAnchoredPanel extends StatefulWidget {
  const DshAnchoredPanel({
    super.key,
    required this.builder,
    required this.panelBuilder,
    this.side = DshPanelSide.bottom,
    this.align = DshPanelAlign.start,
    this.gap = 4,
    this.controller,
    this.panelWidth,
    this.viewportMargin = 12,
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

  @override
  State<DshAnchoredPanel> createState() => _DshAnchoredPanelState();
}

class _DshAnchoredPanelState extends State<DshAnchoredPanel> {
  final LayerLink _link = LayerLink();
  late DshPanelController _controller;
  OverlayEntry? _entry;
  LocalHistoryEntry? _history;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DshPanelController();
    _controller._toggle = _toggle;
    _controller._close = _close;
  }

  @override
  void dispose() {
    _controller._toggle = null;
    _controller._close = null;
    _entry?.remove();
    _entry = null;
    final history = _history;
    _history = null;
    history?.remove();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _toggle() => _entry == null ? _show() : _close();

  void _close() {
    if (_entry == null) return;
    _entry!.remove();
    _entry = null;
    _controller._set(false);
    final history = _history;
    _history = null;
    history?.remove();
  }

  void _show() {
    final overlay = Overlay.of(context, rootOverlay: true);
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
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                final box = this.context.findRenderObject()! as RenderBox;
                final anchor = box.localToGlobal(Offset.zero) & box.size;
                // The trigger owns its toggle. Closing on its pointer-down
                // would make its subsequent tap reopen the same panel.
                if (!anchor.contains(event.position)) _close();
              },
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment(end ? 1 : -1, top ? -1 : 1),
            followerAnchor: Alignment(end ? 1 : -1, top ? 1 : -1),
            offset: Offset(shiftX, top ? -widget.gap : widget.gap),
            child: width == null
                ? widget.panelBuilder(context, _controller)
                : SizedBox(
                    width: width,
                    child: widget.panelBuilder(context, _controller),
                  ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
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
      child: CompositedTransformTarget(
        link: _link,
        child: widget.builder(context, _controller),
      ),
    ),
  );
}
