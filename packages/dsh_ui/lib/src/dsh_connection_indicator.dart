import 'dart:async';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import 'dsh_icon.dart';
import 'dsh_icons.g.dart';
import 'dsh_state_dot.dart';
import 'dsh_text_scale.dart';
import 'theme_access.dart';

/// What [DshConnectionIndicator] shows (dsh `ConnectionIndicatorState`).
enum DshConnectionIndicatorState {
  /// The outage is visible and the next attempt is scheduled; tapping retries
  /// now.
  disconnected,

  /// An attempt is in flight: the label followed by three advancing dots;
  /// tapping replaces the attempt.
  connecting,

  /// The connection came back (shown briefly by the owner).
  recovered,
}

/// The inline connection-recovery control of dsh's web client
/// (`ConnectionIndicator.tsx`). The outage and retry states are one button
/// whose static label already names the retry action; the recovered state is a
/// quiet confirmation. [state] null shows nothing: the widget fades out for
/// [exitDuration] before it unmounts, like the web one.
///
/// Sizes and spacing are the stylesheet's own (28px tall, 8px padding, a 14px
/// icon column and 4px gap, 12px/18px text at weight 500, 1px border), colours
/// come from the theme contract.
class DshConnectionIndicator extends StatefulWidget {
  const DshConnectionIndicator({
    super.key,
    required this.state,
    required this.disconnectedLabel,
    required this.connectingLabel,
    required this.recoveredLabel,
    required this.reconnectActionLabel,
    required this.restartActionLabel,
    required this.onReconnect,
  });

  final DshConnectionIndicatorState? state;
  final String disconnectedLabel;
  final String connectingLabel;
  final String recoveredLabel;

  /// Accessible label of the outage action.
  final String reconnectActionLabel;

  /// Accessible label of the action that replaces an attempt in flight.
  final String restartActionLabel;
  final VoidCallback onReconnect;

  /// The exit transition (the web stylesheet's `.leaving`).
  static const Duration exitDuration = Duration(milliseconds: 150);

  /// Key of the painted surface; for tests.
  static const Key surfaceKey = ValueKey<String>('dshConnectionIndicator');

  @override
  State<DshConnectionIndicator> createState() => _DshConnectionIndicatorState();
}

class _DshConnectionIndicatorState extends State<DshConnectionIndicator> {
  DshConnectionIndicatorState? _rendered;
  Timer? _exit;
  bool _hovered = false;
  bool _pressed = false;
  bool _focusVisible = false;

  @override
  void initState() {
    super.initState();
    _rendered = widget.state;
  }

  @override
  void didUpdateWidget(DshConnectionIndicator old) {
    super.didUpdateWidget(old);
    final state = widget.state;
    if (state != null) {
      _exit?.cancel();
      _rendered = state;
      return;
    }
    if (_rendered == null || (_exit?.isActive ?? false)) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _rendered = null;
      return;
    }
    _exit = Timer(DshConnectionIndicator.exitDuration, () {
      if (mounted) setState(() => _rendered = null);
    });
  }

  @override
  void dispose() {
    _exit?.cancel();
    super.dispose();
  }

  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }

  /// `color-mix(in srgb, a, b p)`: premultiplied interpolation.
  static Color _mix(Color a, Color b, double p) {
    final alpha = a.a * (1 - p) + b.a * p;
    if (alpha == 0) return a.withValues(alpha: 0);
    double ch(double x, double y) => (x * a.a * (1 - p) + y * b.a * p) / alpha;
    return Color.from(
      alpha: alpha,
      red: ch(a.r, b.r),
      green: ch(a.g, b.g),
      blue: ch(a.b, b.b),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rendered = _rendered;
    if (rendered == null) return const SizedBox.shrink();
    final theme = context.dsh;
    final leaving = widget.state == null;
    final recovered = rendered == DshConnectionIndicatorState.recovered;
    final connecting = rendered == DshConnectionIndicatorState.connecting;

    final Color foreground;
    final Color fill;
    final Color border;
    if (recovered) {
      foreground = theme.color('--dsw-alias-state-success-primary');
      fill = theme.color('--dsw-alias-state-success-tertiary');
      border = foreground.withValues(alpha: foreground.a * 0.2);
    } else {
      foreground = theme.color('--dsw-alias-state-warn-label');
      final tertiary = theme.color('--dsw-alias-state-warn-tertiary');
      final primary = theme.color('--dsw-alias-state-warn-primary');
      fill = _pressed
          ? _mix(tertiary, primary, 0.10)
          : _hovered
          ? _mix(tertiary, primary, 0.06)
          : tertiary;
      border = foreground.withValues(alpha: foreground.a * 0.2);
    }
    final style = theme
        .textStyle('--dsw-font-xxs-12')
        .sized(12, line: 18)
        .copyWith(
          color: foreground,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.none,
        );
    final label = recovered
        ? widget.recoveredLabel
        : connecting
        ? widget.connectingLabel
        : widget.disconnectedLabel;
    final radius = BorderRadius.circular(theme.radiusSm);

    Widget body = Container(
      key: DshConnectionIndicator.surfaceKey,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: Center(
              child: recovered
                  ? DshIcon(DshIcons.check, size: 14, color: foreground)
                  : connecting
                  ? DshStateDot(
                      DshStateDotState.ongoing,
                      size: 14,
                      color: foreground,
                    )
                  : DshIcon(DshIcons.refresh, size: 14, color: foreground),
            ),
          ),
          const SizedBox(width: 4),
          DefaultTextStyle(
            style: style,
            child: connecting
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, softWrap: false),
                      _Dots(style: style),
                    ],
                  )
                : Text(label, softWrap: false),
          ),
        ],
      ),
    );

    if (recovered) {
      body = Semantics(
        container: true,
        liveRegion: true,
        label: label,
        child: ExcludeSemantics(child: body),
      );
    } else {
      final ring = theme.focusRingWidth;
      body = Semantics(
        container: true,
        button: true,
        label: connecting
            ? widget.restartActionLabel
            : widget.reconnectActionLabel,
        onTap: widget.onReconnect,
        child: ExcludeSemantics(
          child: MouseRegion(
            onEnter: (_) => _set(() => _hovered = true),
            onExit: (_) => _set(() => _hovered = false),
            child: FocusableActionDetector(
              mouseCursor: SystemMouseCursors.click,
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              },
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    widget.onReconnect();
                    return null;
                  },
                ),
              },
              onShowFocusHighlight: (v) => _set(() => _focusVisible = v),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => _set(() => _pressed = true),
                onTapUp: (_) => _set(() => _pressed = false),
                onTapCancel: () => _set(() => _pressed = false),
                onTap: widget.onReconnect,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    body,
                    if (_focusVisible)
                      Positioned(
                        left: -2 - ring,
                        top: -2 - ring,
                        right: -2 - ring,
                        bottom: -2 - ring,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: theme.focusRingColor,
                                width: ring,
                              ),
                              borderRadius: BorderRadius.circular(
                                theme.radiusSm + 2 + ring,
                              ),
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
      );
    }
    if (leaving) {
      body = Opacity(opacity: 0, child: body);
    }
    return body;
  }
}

/// The three attempt dots: a 1em box, the second dot appears a third of the
/// way through each 1.5s cycle and the third at two thirds (stylesheet
/// `reveal-second-dot` / `reveal-third-dot`). Static (all three) with
/// animations disabled, like `prefers-reduced-motion`.
class _Dots extends StatefulWidget {
  const _Dots({required this.style});
  final TextStyle style;

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !MediaQuery.disableAnimationsOf(context);
    if (animate && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      )..repeat();
    } else if (!animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _build(double t) {
    final color = widget.style.color!;
    Color at(bool visible) => visible ? color : color.withValues(alpha: 0);
    return SizedBox(
      width: widget.style.fontSize,
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: '.'),
            TextSpan(
              text: '.',
              style: TextStyle(color: at(t >= 0.3333)),
            ),
            TextSpan(
              text: '.',
              style: TextStyle(color: at(t >= 0.6666)),
            ),
          ],
        ),
        softWrap: false,
        overflow: TextOverflow.visible,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return _build(1);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _build(controller.value),
    );
  }
}
