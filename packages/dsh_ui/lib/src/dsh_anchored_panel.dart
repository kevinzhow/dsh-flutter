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
  });

  final Widget Function(BuildContext context, DshPanelController controller)
  builder;
  final Widget Function(BuildContext context, DshPanelController controller)
  panelBuilder;
  final DshPanelSide side;
  final DshPanelAlign align;
  final double gap;
  final DshPanelController? controller;

  @override
  State<DshAnchoredPanel> createState() => _DshAnchoredPanelState();
}

class _DshAnchoredPanelState extends State<DshAnchoredPanel> {
  final LayerLink _link = LayerLink();
  late DshPanelController _controller;
  OverlayEntry? _entry;

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
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _toggle() => _entry == null ? _show() : _close();

  void _close() {
    if (_entry == null) return;
    _entry!.remove();
    _entry = null;
    _controller._set(false);
  }

  void _show() {
    final overlay = Overlay.of(context, rootOverlay: true);
    final end = widget.align == DshPanelAlign.end;
    final top = widget.side == DshPanelSide.top;
    _entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _close(),
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment(end ? 1 : -1, top ? -1 : 1),
            followerAnchor: Alignment(end ? 1 : -1, top ? 1 : -1),
            offset: Offset(0, top ? -widget.gap : widget.gap),
            child: widget.panelBuilder(context, _controller),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
    _controller._set(true);
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    link: _link,
    child: widget.builder(context, _controller),
  );
}
