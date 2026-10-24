// Ported from raft-flutter `apps/raft_flutter/lib/features/timeline_scrollbar.dart`
// (thumb-drag model unchanged; colours and sizes come from dsh's scrollbar
// tokens instead of the Material `ColorScheme`).
import 'package:flutter/gestures.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// Maps a scrollbar thumb drag onto a timeline.
abstract interface class DshTimelineThumbDriver {
  /// Freezes the timeline's content model for a drag; returns the thumb's
  /// fraction of the track (0 = top), or null when it cannot be dragged.
  double? beginThumbDrag();

  /// Shows the content at [fraction] of the frozen model.
  void moveThumb(double fraction);

  void endThumbDrag();
}

/// The desktop scrollbar of a message timeline: a dsh-styled thumb (5px,
/// `--dsw-alias-scrollbar-*`) with a thumb drag mapped through [driver].
///
/// The default scrollbar maps the pointer onto the live scroll range. A
/// timeline's range is partly estimated and grows when history lands, so the
/// same pointer position kept mapping to a new offset (an older page landing
/// under a thumb held at the top jumped the content to the new top, which
/// requested the next page, and so on) and the thumb drifted from the
/// pointer. Here the thumb follows the pointer exactly against a model frozen
/// at the press; the live range applies again after release.
class DshTimelineScrollbar extends RawScrollbar {
  const DshTimelineScrollbar({
    super.key,
    required super.child,
    required ScrollController super.controller,
    required this.driver,
  }) : super(
         fadeDuration: const Duration(milliseconds: 300),
         timeToFade: const Duration(milliseconds: 600),
         pressDuration: Duration.zero,
       );

  final DshTimelineThumbDriver driver;

  @override
  RawScrollbarState<DshTimelineScrollbar> createState() =>
      _DshTimelineScrollbarState();
}

class _ThumbGrab {
  _ThumbGrab(this.start, this.fraction, this.movable, this.metrics);

  /// Pointer main-axis position and thumb fraction at the press.
  final double start, fraction;

  /// Track length the thumb can travel.
  final double movable;

  /// Scroll metrics at the press; the thumb is painted against them.
  final ScrollMetrics metrics;
  late double current = fraction;

  ScrollMetrics paint() {
    final range = metrics.maxScrollExtent - metrics.minScrollExtent;
    return FixedScrollMetrics(
      minScrollExtent: metrics.minScrollExtent,
      maxScrollExtent: metrics.maxScrollExtent,
      pixels: metrics.minScrollExtent + current * range,
      viewportDimension: metrics.viewportDimension,
      axisDirection: metrics.axisDirection,
      devicePixelRatio: metrics.devicePixelRatio,
    );
  }
}

class _DshTimelineScrollbarState
    extends RawScrollbarState<DshTimelineScrollbar> {
  // dsh's WebKit scrollbar is 5px wide with a transparent track
  // (`--dsh-scrollbar-width`, ui-theme styles/scrollbar.css); the hovered
  // thumb on a pointer platform grows so it is easy to grab.
  static const _thicknessIdle = 5.0, _thicknessHover = 8.0;
  static const _margin = 2.0, _minLength = 48.0;
  static const _radius = Radius.circular(8);
  static const _hoverDuration = Duration(milliseconds: 200);

  late final AnimationController hover = AnimationController(
    vsync: this,
    duration: _hoverDuration,
  )..addListener(updateScrollbarPainter);
  bool hovering = false;
  _ThumbGrab? grab;
  late Color _thumb, _thumbHover;

  /// dsh's 5px bar is a classic (non-overlay) scrollbar: the thumb is there
  /// whenever the list can scroll, on every desktop platform.
  @override
  bool get showScrollbar => true;

  @override
  bool get enableGestures => true;

  @override
  void didChangeDependencies() {
    final theme = context.dsh;
    _thumb = theme.color('--dsw-alias-scrollbar-bg-l1');
    _thumbHover = theme.color('--dsw-alias-scrollbar-hover-l1');
    // The hover fade is a change of state, not motion, when it is reduced.
    hover.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _hoverDuration;
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    hover.dispose();
    super.dispose();
  }

  @override
  void updateScrollbarPainter() {
    scrollbarPainter
      ..color = grab != null
          ? _thumbHover
          : Color.lerp(_thumb, _thumbHover, hover.value)!
      ..trackColor = _thumb.withValues(alpha: 0)
      ..trackBorderColor = _thumb.withValues(alpha: 0)
      ..textDirection = Directionality.of(context)
      ..thickness = grab != null || hovering ? _thicknessHover : _thicknessIdle
      ..radius = _radius
      ..crossAxisMargin = _margin
      ..mainAxisMargin = 0
      ..minLength = _minLength
      ..padding = MediaQuery.paddingOf(context)
      ..ignorePointer = !enableGestures;
  }

  double mainAxis(Offset offset, ScrollMetrics metrics) =>
      switch (metrics.axisDirection) {
        AxisDirection.down => offset.dy,
        AxisDirection.up => -offset.dy,
        AxisDirection.right => offset.dx,
        AxisDirection.left => -offset.dx,
      };

  @override
  void handleThumbPressStart(Offset localPosition) {
    // Holds the position in a drag activity (no ballistic or alignment
    // fights the thumb) and shows the bar.
    super.handleThumbPressStart(localPosition);
    final controller = widget.controller!;
    if (!controller.hasClients) return;
    final position = controller.position;
    final range = position.maxScrollExtent - position.minScrollExtent;
    final fraction = widget.driver.beginThumbDrag();
    // Track length per unit of scroll range, from the painter's own mapping.
    final perUnit = range > 0 ? scrollbarPainter.getTrackToScroll(1) : 0;
    if (fraction == null || perUnit <= 0) return;
    grab = _ThumbGrab(
      mainAxis(localPosition, position),
      fraction,
      range / perUnit,
      position.copyWith(),
    );
    setState(() {});
    scrollbarPainter.update(grab!.paint(), position.axisDirection);
  }

  @override
  // The update is mapped through the frozen model instead of the live range
  // (see the class comment); RawScrollbar's own mapping must not run.
  // ignore: must_call_super
  void handleThumbPressUpdate(Offset localPosition) {
    final g = grab;
    if (g == null) {
      super.handleThumbPressUpdate(localPosition);
      return;
    }
    final fraction =
        (g.fraction +
                (mainAxis(localPosition, g.metrics) - g.start) / g.movable)
            .clamp(0.0, 1.0);
    // At either end the driver still hears every move (reaching for more).
    if (fraction == g.current && fraction > 0 && fraction < 1) return;
    g.current = fraction;
    scrollbarPainter.update(g.paint(), g.metrics.axisDirection);
    widget.driver.moveThumb(fraction);
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    if (grab != null) {
      grab = null;
      widget.driver.endThumbDrag();
      setState(() {});
      final controller = widget.controller!;
      if (controller.hasClients) {
        final position = controller.position;
        scrollbarPainter.update(position, position.axisDirection);
      }
    }
    super.handleThumbPressEnd(localPosition, velocity);
  }

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    if (isPointerOverScrollbar(event.position, event.kind, forHover: true)) {
      setState(() => hovering = true);
      hover.forward();
    } else if (hovering) {
      setState(() => hovering = false);
      hover.reverse();
    }
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    setState(() => hovering = false);
    hover.reverse();
  }

  /// Runs after RawScrollbar's own listeners: while the thumb is held, its
  /// painter keeps the frozen metrics at the pointer's fraction.
  bool keepGrab(Notification notification) {
    final g = grab;
    if (g != null) scrollbarPainter.update(g.paint(), g.metrics.axisDirection);
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: keepGrab,
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: keepGrab,
          child: super.build(context),
        ),
      );
}
