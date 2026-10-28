import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'dsh_icon.dart';
import 'dsh_icon_data.dart';
import 'dsh_corners.dart';
import 'dsh_icons.g.dart';
import 'dsh_recipes.g.dart';
import 'dsh_shadow_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

Duration _milliseconds(double value) => Duration(
  microseconds: (value * Duration.microsecondsPerMillisecond).round(),
);

/// Source defaults retain fractional milliseconds when the recipe changes.
final Duration dshToastHold = _milliseconds(DshToastRecipe.holdMs);
final Duration dshToastFade = _milliseconds(DshToastRecipe.fadeMs);

enum DshToastTone { success }

/// Root portal layer. Mount around the Navigator in the app builder so these
/// announcements escape feature transforms and remain above lightbox routes in
/// either show order. Other overlay-family priorities are not changed here.
class DshToastHost extends StatelessWidget {
  const DshToastHost({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Overlay.wrap(child: child);
}

/// A source Toast occurrence: no icon by default; success owns the published
/// circled-check glyph and overrides an optional icon. Actions/anchors remain
/// unsupported pending source/native acceptance. Completion is timer-owned.
class DshToast extends StatefulWidget {
  const DshToast({
    super.key,
    required this.text,
    this.icon,
    this.tone,
    this.hold,
    required this.onDone,
  });
  final String text;
  final Widget? icon;
  final DshToastTone? tone;
  final Duration? hold;
  final VoidCallback onDone;
  @override
  State<DshToast> createState() => _DshToastState();
}

class _DshToastState extends State<DshToast> {
  final _identity = UniqueKey();
  final _portal = OverlayPortalController();
  late final _hold = ValueNotifier(widget.hold ?? dshToastHold);
  _ToastSpec get _spec => _ToastSpec(
    text: widget.text,
    icon: widget.icon,
    tone: widget.tone,
    holdSource: _hold,
    onDone: () {
      if (mounted) widget.onDone();
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _portal.show();
    });
  }

  @override
  void didUpdateWidget(DshToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cancel/reschedule the source effect's timer during this update, even
    // before the logical owner's overlay child gets its next build.
    _hold.value = widget.hold ?? dshToastHold;
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the actual logical owner/provider ancestry. Production's outer
    // Overlay above Navigator also preserves priority over later inner routes.
    return OverlayPortal(
      overlayLocation: OverlayChildLocation.rootOverlay,
      controller: _portal,
      overlayChildBuilder: (_) => _ToastPaint(key: _identity, spec: _spec),
      child: const SizedBox.shrink(),
    );
  }
}

class _ToastSpec {
  const _ToastSpec({
    required this.text,
    required this.icon,
    required this.tone,
    required this.holdSource,
    required this.onDone,
  });
  final String text;
  final Widget? icon;
  final DshToastTone? tone;
  final ValueNotifier<Duration> holdSource;
  Duration get hold => holdSource.value;
  final VoidCallback onDone;
}

Curve _cssCurve(String value) => switch (value) {
  'linear' => Curves.linear,
  'ease' => Curves.ease,
  'ease-in' => Curves.easeIn,
  'ease-out' => Curves.easeOut,
  'ease-in-out' => Curves.easeInOut,
  _ => throw StateError('Unsupported generated Toast curve: $value'),
};

class _ToastPaint extends StatefulWidget {
  const _ToastPaint({super.key, required this.spec});
  final _ToastSpec spec;
  @override
  State<_ToastPaint> createState() => _ToastPaintState();
}

class _ToastPaintState extends State<_ToastPaint> {
  // Source body-portal animations continue when another route covers the owner.
  // This occurrence-owned ticker therefore does not inherit route TickerMode.
  late final Ticker _ticker = Ticker((_) {
    setState(() => _elapsed = _timelineElapsed);
    if (_elapsed >= _paintEnd) _ticker.stop();
  });
  Duration _elapsed = Duration.zero;
  late final Duration _origin;
  Duration get _timelineElapsed =>
      SchedulerBinding.instance.currentFrameTimeStamp - _origin;
  Timer? _deadline;
  Duration get _enter => _milliseconds(DshToastRecipe.enterMs);
  Duration get _paintEnd => widget.spec.hold + dshToastFade > _enter
      ? widget.spec.hold + dshToastFade
      : _enter;

  void _scheduleDeadline() {
    _deadline?.cancel();
    _deadline = Timer(widget.spec.hold + dshToastFade, () {
      if (mounted) widget.spec.onDone();
    });
  }

  @override
  void initState() {
    super.initState();
    _origin = SchedulerBinding.instance.currentFrameTimeStamp;
    widget.spec.holdSource.addListener(_holdChanged);
    _scheduleDeadline();
    _ticker.start();
  }

  @override
  void didUpdateWidget(_ToastPaint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec.holdSource != widget.spec.holdSource) {
      oldWidget.spec.holdSource.removeListener(_holdChanged);
      widget.spec.holdSource.addListener(_holdChanged);
      _holdChanged();
    }
  }

  void _holdChanged() {
    _scheduleDeadline();
    // CSS changes delay on its original mount timeline; the timer restarts.
    _elapsed = _timelineElapsed;
    if (!_ticker.isActive && _elapsed < _paintEnd) _ticker.start();
  }

  @override
  void dispose() {
    widget.spec.holdSource.removeListener(_holdChanged);
    _deadline?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  double _progress(Duration elapsed, Duration duration) =>
      duration == Duration.zero
      ? 1
      : (elapsed.inMicroseconds / duration.inMicroseconds).clamp(0, 1);

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh, spec = widget.spec;
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final entry = reduced
        ? 1.0
        : _cssCurve(DshToastRecipe.enterCurve)
              .transform(_progress(_elapsed, _enter));
    final afterHold = _elapsed - spec.hold;
    final fade = afterHold.isNegative
        ? 0.0
        : _cssCurve(DshToastRecipe.fadeCurve)
              .transform(_progress(afterHold, dshToastFade));
    final hidden = !afterHold.isNegative && afterHold >= dshToastFade;
    final icon = spec.tone == DshToastTone.success
        ? const DshIcon(DshIcons.checkCircle)
        : spec.icon;
    final radius = theme.number(DshToastRecipe.radiusToken);
    return IgnorePointer(
      child: hidden
          ? const SizedBox.shrink()
          : LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = math.max(
                  0.0,
                  math.min(
                    DshToastRecipe.maxContentWidth,
                    constraints.maxWidth - DshToastRecipe.viewportInset,
                  ),
                );
                return Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: DshToastRecipe.top),
                    child: Opacity(
                      opacity: entry * (1 - fade),
                      alwaysIncludeSemantics: true,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          DshToastRecipe.enterOffsetY * (1 - entry),
                        ),
                        child: Semantics(
                          container: true,
                          role: SemanticsRole.alert,
                          child: DshShadowBox(
                            color: theme.color(DshToastRecipe.backgroundToken),
                            authoredOpaqueBackground:
                                theme.color(DshToastRecipe.backgroundToken).a ==
                                1,
                            radius: radius,
                            shape: theme.cornerBorder(radius),
                            shadows: theme.boxShadow(
                              DshToastRecipe.shadowToken,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: DshToastRecipe.horizontalPadding,
                              vertical: DshToastRecipe.verticalPadding,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: contentWidth,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (icon != null) ...[
                                    ExcludeSemantics(
                                      child: IconTheme(
                                        data: IconThemeData(
                                          color: theme.color(
                                            spec.tone == DshToastTone.success
                                                ? DshToastRecipe
                                                      .successIconLabelToken
                                                : DshToastRecipe.iconLabelToken,
                                          ),
                                        ),
                                        child: icon,
                                      ),
                                    ),
                                    SizedBox(width: DshToastRecipe.gap),
                                  ],
                                  Flexible(
                                    child: DshChromeText(
                                      spec.text,
                                      style: theme
                                          .fixedTextStyle(
                                            size: DshToastRecipe.fontSize,
                                            line: DshToastRecipe.lineHeight,
                                          )
                                          .copyWith(
                                            color: theme.color(
                                              DshToastRecipe.labelToken,
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
                  ),
                );
              },
            ),
    );
  }
}

/// Owner-local, data-only imperative adapter. An OverlayEntry cannot preserve
/// an arbitrary initiating provider subtree; use owner-mounted [DshToast] for a
/// custom context-dependent icon. Identity is allocated once per show, so an
/// overlay rebuild keeps its deadline and old completion keeps a replacement.
class DshToasts {
  OverlayEntry? _entry;
  void show(
    BuildContext context,
    String text, {
    DshIconData? icon,
    DshToastTone? tone,
    Duration? hold,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) {
      showOn(overlay, text, icon: icon, tone: tone, hold: hold);
    }
  }

  void showOn(
    OverlayState overlay,
    String text, {
    DshIconData? icon,
    DshToastTone? tone,
    Duration? hold,
  }) {
    dismiss();
    final identity = UniqueKey();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => DshToast(
        key: identity,
        text: text,
        icon: icon == null ? null : DshIcon(icon),
        tone: tone,
        hold: hold,
        onDone: () {
          if (!identical(_entry, entry)) return;
          _entry = null;
          entry.remove();
          entry.dispose();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  void dismiss() {
    final entry = _entry;
    _entry = null;
    entry?.remove();
    entry?.dispose();
  }
}
