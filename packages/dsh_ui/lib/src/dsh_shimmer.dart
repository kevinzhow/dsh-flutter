import 'package:flutter/widgets.dart';

import 'theme_access.dart';

/// One left-to-right highlight over a row's text (dsh `TextShimmer`): while
/// [active] a band in `--dsw-alias-label-shimmer` sweeps across [child] every
/// 1.5s. Static when animations are disabled, like `prefers-reduced-motion`.
class DshShimmer extends StatefulWidget {
  const DshShimmer({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<DshShimmer> createState() => _DshShimmerState();
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);
  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx * bounds.width, 0, 0);
}

class _DshShimmerState extends State<DshShimmer>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(DshShimmer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final animate = widget.active && !MediaQuery.disableAnimationsOf(context);
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

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    final shimmer = context.dsh.color('--dsw-alias-label-shimmer');
    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        // The sweep covers the first two thirds of the period.
        final phase = (controller.value / (2 / 3)).clamp(0.0, 1.0);
        final dx = -1 + 2 * phase;
        return Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: const [
                      Color(0x00000000),
                      Color(0xFF000000),
                      Color(0xFF000000),
                      Color(0x00000000),
                    ],
                    stops: const [0, 0.4, 0.6, 1],
                    transform: _SlideGradient(dx),
                  ).createShader(bounds),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(shimmer, BlendMode.srcIn),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
