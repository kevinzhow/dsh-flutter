import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

// The pulse follows raft-flutter's `RaftSkeleton`
// (`packages/raft_ui/lib/src/indicators.dart`): Tailwind's `pulse`, opacity
// 1 -> .5 -> 1 over 2s on cubic-bezier(.4, 0, .6, 1), full opacity under
// reduced motion. The shapes mirror dsh's own stream (user bubble, answer
// lines, tool row); the fills are dsh tokens.

/// One placeholder stripe or block of a loading stream.
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({super.key, this.width, this.height = 12, this.radius});

  /// Null stretches to the available width.
  final double? width;
  final double height;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshDecoratedBox(
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-interactive-bg-hover-solid'),
        borderRadius: BorderRadius.circular(radius ?? height / 2),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}

/// Pulses its children together (one ticker for the whole placeholder).
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});
  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  static const _curve = Cubic(.4, 0, .6, 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: _pulse,
      child: widget.child,
      builder: (context, child) {
        final v = _pulse.value;
        final half = v < .5 ? v * 2 : (1 - v) * 2;
        return Opacity(opacity: 1 - .5 * _curve.transform(half), child: child);
      },
    ),
  );
}

/// What a session shows while its history opens, or above the oldest row
/// while an older page is read: the shape of a few exchanges.
class StreamSkeleton extends StatelessWidget {
  const StreamSkeleton({super.key, this.exchanges = 3});

  /// How many (user, answer, tool) groups to draw.
  final int exchanges;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    Widget lines(List<double> fractions) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < fractions.length; i++) ...[
          if (i > 0) const SizedBox(height: DshSpace.sm),
          FractionallySizedBox(
            widthFactor: fractions[i],
            child: const SkeletonBar(height: 12),
          ),
        ],
      ],
    );
    const shapes = [
      [.92, .78, .5],
      [.85, .64],
      [.95, .88, .7, .35],
    ];
    return SkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < exchanges; i++) ...[
            if (i > 0) const SizedBox(height: DshSpace.xl),
            // The user's bubble: right aligned, on the bubble colour.
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FractionallySizedBox(
                widthFactor: i.isEven ? .6 : .42,
                child: DshDecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.color('--dsw-specific-bubble'),
                    borderRadius: BorderRadius.circular(theme.radiusXl),
                  ),
                  child: const SizedBox(height: 44),
                ),
              ),
            ),
            const SizedBox(height: DshSpace.lg),
            lines(shapes[i % shapes.length]),
            const SizedBox(height: DshSpace.md),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: SkeletonBar(width: 168, height: 28, radius: 8),
            ),
          ],
        ],
      ),
    );
  }
}
