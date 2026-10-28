import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Mount around Navigator to keep source Toast paint and announcements above
/// routes. Painter widgets keep their original inherited providers; the root
/// holds only resolved announcement text, direction and actual painted bounds.
class DshToastHost extends StatefulWidget {
  const DshToastHost({super.key, required this.child});
  final Widget child;
  @override
  State<DshToastHost> createState() => _DshToastHostState();
}

class _Announcement {
  const _Announcement(this.text, this.direction, this.rect);
  final String text;
  final TextDirection direction;
  final Rect rect;
  bool sameAs(_Announcement? other) =>
      other != null &&
      text == other.text &&
      direction == other.direction &&
      rect == other.rect;
}

class _DshToastHostState extends State<DshToastHost> {
  final _root = GlobalKey();
  final _announcements = <Object, _Announcement>{};
  final _pending = <Object, _Announcement?>{};
  bool _scheduled = false;

  RenderBox? get rootBox {
    final object = _root.currentContext?.findRenderObject();
    return object is RenderBox && object.hasSize ? object : null;
  }

  bool update(Object identity, _Announcement? value) {
    _pending[identity] = value;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      _flush();
    } else if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _flush());
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    return value == null
        ? !_announcements.containsKey(identity)
        : value.sameAs(_announcements[identity]);
  }

  void _flush() {
    _scheduled = false;
    if (!mounted) return;
    var changed = false;
    for (final entry in _pending.entries) {
      if (entry.value case final value?) {
        if (!value.sameAs(_announcements[entry.key])) {
          _announcements[entry.key] = value;
          changed = true;
        }
      } else {
        changed = _announcements.remove(entry.key) != null || changed;
      }
    }
    _pending.clear();
    if (changed) setState(() {});
  }

  @override
  Widget build(BuildContext context) => _ToastHostScope(
    host: this,
    child: Stack(
      key: _root,
      fit: StackFit.expand,
      children: [
        Overlay.wrap(child: widget.child),
        for (final entry in _announcements.entries)
          Positioned.fromRect(
            key: ObjectKey(entry.key),
            rect: entry.value.rect,
            child: IgnorePointer(
              child: Semantics(
                container: true,
                role: SemanticsRole.alert,
                label: entry.value.text,
                textDirection: entry.value.direction,
                child: const SizedBox.expand(),
              ),
            ),
          ),
      ],
    ),
  );
}

class _ToastHostScope extends InheritedWidget {
  const _ToastHostScope({required this.host, required super.child});
  final _DshToastHostState host;
  @override
  bool updateShouldNotify(_ToastHostScope oldWidget) => oldWidget.host != host;
}

/// Internal canonical painter seat; intentionally not exported as public API.
/// A zero-size logical portal anchor inside a clipped owner can lose platform
/// traversal semantics even while its overlay paints. Under the canonical host
/// this widget supplies one root announcement at its real render rectangle.
class DshToastAnnouncement extends StatefulWidget {
  const DshToastAnnouncement({
    super.key,
    required this.text,
    required this.child,
  });
  final String text;
  final Widget child;
  @override
  State<DshToastAnnouncement> createState() => _DshToastAnnouncementState();
}

class _DshToastAnnouncementState extends State<DshToastAnnouncement> {
  final _identity = Object();
  _DshToastHostState? _host;
  bool _rootOwns = false;
  TextDirection _direction = TextDirection.ltr;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = context
        .dependOnInheritedWidgetOfExactType<_ToastHostScope>()
        ?.host;
    if (host != _host) {
      _host?.update(_identity, null);
      _rootOwns = false;
    }
    _host = host;
    _direction = Directionality.of(context);
  }

  void _report(Rect rect) {
    if (mounted && !rect.isEmpty) {
      final owned =
          _host?.update(
            _identity,
            _Announcement(widget.text, _direction, rect),
          ) ??
          false;
      if (owned != _rootOwns) setState(() => _rootOwns = owned);
    }
  }

  @override
  void dispose() {
    _host?.update(_identity, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    final semantics = Semantics(
      container: !_rootOwns,
      excludeSemantics: _rootOwns,
      role: _rootOwns ? null : SemanticsRole.alert,
      child: widget.child,
    );
    if (host == null) {
      return semantics;
    }
    return _AnnouncementBounds(host: host, onRect: _report, child: semantics);
  }
}

class _AnnouncementBounds extends SingleChildRenderObjectWidget {
  const _AnnouncementBounds({
    required this.host,
    required this.onRect,
    required super.child,
  });
  final _DshToastHostState host;
  final ValueChanged<Rect> onRect;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnnouncementBounds(host, onRect);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAnnouncementBounds object,
  ) {
    object
      ..host = host
      ..onRect = onRect
      ..markNeedsPaint();
  }
}

class _RenderAnnouncementBounds extends RenderProxyBox {
  _RenderAnnouncementBounds(this.host, this.onRect);
  _DshToastHostState host;
  ValueChanged<Rect> onRect;
  bool _scheduled = false;

  void _afterFrame() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final root = host.rootBox;
      if (!attached || !hasSize || root == null) return;
      onRect(
        MatrixUtils.transformRect(getTransformTo(root), Offset.zero & size),
      );
    });
  }

  @override
  void performLayout() {
    super.performLayout();
    _afterFrame();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _afterFrame();
  }
}
