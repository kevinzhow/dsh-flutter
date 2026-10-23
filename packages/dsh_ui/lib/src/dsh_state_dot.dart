import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'theme_access.dart';

/// The compact status language of rows and cards (dsh `StateDot`).
enum DshStateDotState { done, warning, ongoing, error, idle }

/// A status mark: solid states keep a 10px layout slot and paint one 6px core;
/// `ongoing` is a 14px spinner (a quiet ring behind a breathing arc). With
/// animations disabled the spinner is static, like `prefers-reduced-motion`.
class DshStateDot extends StatefulWidget {
  const DshStateDot(this.state, {super.key, this.size});

  final DshStateDotState state;
  final double? size;

  @override
  State<DshStateDot> createState() => _DshStateDotState();
}

class _DshStateDotState extends State<DshStateDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  bool get _spins => widget.state == DshStateDotState.ongoing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(DshStateDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final animate = _spins && !MediaQuery.disableAnimationsOf(context);
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

  Color _color(BuildContext context) {
    final theme = context.dsh;
    return switch (widget.state) {
      DshStateDotState.done => theme.color('--dsw-alias-state-success-primary'),
      DshStateDotState.warning => theme.color('--dsw-alias-state-warn-primary'),
      DshStateDotState.error => theme.color('--dsw-alias-state-error-primary'),
      DshStateDotState.idle => theme.color('--dsw-alias-state-idle-primary'),
      DshStateDotState.ongoing => theme.color('--dsw-alias-label-tertiary'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final edge = widget.size ?? (_spins ? 14.0 : 10.0);
    final color = _color(context);
    if (!_spins) {
      return SizedBox(
        width: edge,
        height: edge,
        child: Padding(
          padding: EdgeInsets.all(edge * 0.2),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return CustomPaint(
        size: Size.square(edge),
        painter: _SpinnerPainter(color, 0, reduced: true),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(edge),
        painter: _SpinnerPainter(color, controller.value),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.color, this.t, {this.reduced = false});

  final Color color;
  final double t;
  final bool reduced;

  static const _r = 9.5;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale);
    const center = Offset(12, 12);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: color.a * 0.25);
    canvas.drawCircle(center, _r, track);
    // Dash length breathes 12 -> 24 -> 12 with the offset following (-6 at the
    // peak); the whole glyph rotates once per period.
    final breathe = reduced ? 0.0 : 1 - (2 * t - 1).abs();
    final dash = reduced ? 18.0 : 12 + 12 * breathe;
    final offset = reduced ? -3.0 : -6 * breathe;
    final rotation = reduced ? 0.0 : t * 2 * math.pi;
    final start = rotation + (-offset) / _r;
    final sweep = dash / _r;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: _r),
      start,
      math.min(sweep, 2 * math.pi - 0.01),
      false,
      arc,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.t != t || old.color != color || old.reduced != reduced;
}
