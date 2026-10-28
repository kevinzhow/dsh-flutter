import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Mount around Navigator to keep source Toast paint and announcements above
/// routes. Painter widgets retain their original live inherited providers.
class DshToastHost extends StatefulWidget {
  const DshToastHost({super.key, required this.child});
  final Widget child;
  @override
  State<DshToastHost> createState() => _DshToastHostState();
}

class _DshToastHostState extends State<DshToastHost> {
  final _bridge = _AnnouncementBridge();

  @override
  Widget build(BuildContext context) => _ToastHostScope(
    bridge: _bridge,
    child: _AnnouncementRoot(
      bridge: _bridge,
      child: Overlay.wrap(child: widget.child),
    ),
  );
}

class _AnnouncementBridge {
  _RenderAnnouncementRoot? root;
}

class _ToastHostScope extends InheritedWidget {
  const _ToastHostScope({required this.bridge, required super.child});
  final _AnnouncementBridge bridge;
  @override
  bool updateShouldNotify(_ToastHostScope oldWidget) =>
      oldWidget.bridge != bridge;
}

class _AnnouncementRoot extends SingleChildRenderObjectWidget {
  const _AnnouncementRoot({required this.bridge, required super.child});
  final _AnnouncementBridge bridge;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnnouncementRoot(bridge);
}

/// This render boundary is logically above Navigator. Extra alert nodes are
/// assembled during the current semantics flush, after current layout/paint;
/// there is no post-frame cache or widget rebuild that can lag a painted frame.
class _RenderAnnouncementRoot extends RenderProxyBox {
  _RenderAnnouncementRoot(this.bridge) {
    bridge.root = this;
  }
  final _AnnouncementBridge bridge;
  final _anchors = <_RenderAnnouncementAnchor>{};
  final _nodes = <_RenderAnnouncementAnchor, SemanticsNode>{};

  void register(_RenderAnnouncementAnchor anchor) {
    _anchors.add(anchor);
    markNeedsSemanticsUpdate();
  }

  void unregister(_RenderAnnouncementAnchor anchor) {
    if (_anchors.remove(anchor)) markNeedsSemanticsUpdate();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..explicitChildNodes = true;
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    final alerts = <SemanticsNode>[];
    final active = <_RenderAnnouncementAnchor>{};
    for (final anchor in _anchors) {
      if (!anchor.attached || anchor.owner != owner || !anchor.hasSize) {
        continue;
      }
      final rect = Offset.zero & anchor.size;
      if (rect.isEmpty) continue;
      active.add(anchor);
      final alert = _nodes.putIfAbsent(anchor, SemanticsNode.new);
      alert
        ..rect = rect
        ..transform = anchor.getTransformTo(this)
        ..updateWith(
          config: SemanticsConfiguration()
            ..isSemanticBoundary = true
            ..role = SemanticsRole.alert
            ..label = anchor.text
            ..textDirection = anchor.direction,
        );
      alerts.add(alert);
    }
    node.updateWith(
      config: config,
      childrenInInversePaintOrder: [...alerts.reversed, ...children],
    );
    // updateWith detaches removed semantic children before releasing our
    // references. Equal labels never share an occurrence or semantic node.
    _nodes.removeWhere((anchor, _) => !active.contains(anchor));
  }

  @override
  void clearSemantics() {
    super.clearSemantics();
    _nodes.clear();
  }

  @override
  void dispose() {
    if (identical(bridge.root, this)) bridge.root = null;
    _nodes.clear();
    super.dispose();
  }
}

/// Internal canonical painter seat; intentionally not exported as public API.
/// The owner-side portal retains its real widget subtree. Only resolved text,
/// direction and this attached render anchor are exposed at the root boundary.
class DshToastAnnouncement extends StatelessWidget {
  const DshToastAnnouncement({
    super.key,
    required this.text,
    required this.child,
  });
  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) => _AnnouncementAnchor(
    bridge: context
        .dependOnInheritedWidgetOfExactType<_ToastHostScope>()
        ?.bridge,
    text: text,
    direction: Directionality.of(context),
    // Preserve the standalone local semantics path. The render anchor excludes
    // this subtree only when the canonical root owns its announcement.
    child: Semantics(container: true, role: SemanticsRole.alert, child: child),
  );
}

class _AnnouncementAnchor extends SingleChildRenderObjectWidget {
  const _AnnouncementAnchor({
    required this.bridge,
    required this.text,
    required this.direction,
    required super.child,
  });
  final _AnnouncementBridge? bridge;
  final String text;
  final TextDirection direction;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnnouncementAnchor(bridge, text, direction);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAnnouncementAnchor object,
  ) {
    object.update(bridge, text, direction);
  }
}

class _RenderAnnouncementAnchor extends RenderProxyBox {
  _RenderAnnouncementAnchor(this._bridge, this.text, this.direction);
  _AnnouncementBridge? _bridge;
  String text;
  TextDirection direction;

  void update(
    _AnnouncementBridge? bridge,
    String text,
    TextDirection direction,
  ) {
    if (_bridge != bridge) {
      if (attached) _bridge?.root?.unregister(this);
      _bridge = bridge;
      if (attached) _bridge?.root?.register(this);
      markNeedsSemanticsUpdate();
    }
    this.text = text;
    this.direction = direction;
    // The Toast rebuild also represents entry/fade transforms outside this
    // render object. Read their current values only at semantics assembly.
    _bridge?.root?.markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _bridge?.root?.register(this);
  }

  @override
  void detach() {
    _bridge?.root?.unregister(this);
    super.detach();
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_bridge?.root == null) super.visitChildrenForSemantics(visitor);
  }

  @override
  void performLayout() {
    super.performLayout();
    _bridge?.root?.markNeedsSemanticsUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _bridge?.root?.markNeedsSemanticsUpdate();
  }
}
