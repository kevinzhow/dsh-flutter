import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

const _eyeContour =
    'M1.5 8C2.9 5.25 5.25 3.5 8 3.5C10.75 3.5 13.1 5.25 14.5 8C13.1 10.75 10.75 12.5 8 12.5C5.25 12.5 2.9 10.75 1.5 8Z';
const _eye = DshIconData(
  viewBox: 16,
  size: 16,
  strokeWidth: 1.3,
  shapes: [
    DshIconShape(
      '${_eyeContour}M10 8C10 9.1 9.1 10 8 10C6.9 10 6 9.1 6 8C6 6.9 6.9 6 8 6C9.1 6 10 6.9 10 8Z',
      cap: DshIconCap.round,
    ),
  ],
);
const _eyeOff = DshIconData(
  viewBox: 16,
  size: 16,
  strokeWidth: 1.3,
  shapes: [
    DshIconShape('${_eyeContour}M2.5 2.5L13.5 13.5', cap: DshIconCap.round),
  ],
);

/// The retained value, rather than a global reveal flag, scopes disclosure to
/// this particular credential. Hidden mode never places raw text in semantics.
class SecretText extends StatefulWidget {
  const SecretText({
    super.key,
    required this.raw,
    required this.masked,
    required this.i18n,
    this.interactive = false,
    this.ellipsis = false,
  });
  final String raw, masked;
  final DshI18n i18n;
  final bool interactive, ellipsis;
  @override
  State<SecretText> createState() => _SecretTextState();
}

class _SecretTextState extends State<SecretText> {
  String? revealedRaw;
  bool get revealed => widget.interactive && revealedRaw == widget.raw;
  void toggle() => setState(() => revealedRaw = revealed ? null : widget.raw);
  @override
  Widget build(BuildContext context) {
    final parent = DefaultTextStyle.of(context).style;
    final parentSize =
        parent.fontSize ?? context.dsh.textStyle('--dsw-font-s-14').fontSize!;
    final size = parentSize * .875, line = parentSize * (parent.height ?? 1.2);
    final style = context.dsh
        .fixedCodeStyle(size: size, line: line)
        .copyWith(color: parent.color ?? context.dsh.labelPrimary);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final control = widget.interactive ? size : 0.0;
          final available = math.max(0.0, constraints.maxWidth - control);
          Size measure(String value) {
            final painter = TextPainter(
              text: TextSpan(text: value, style: style),
              maxLines: widget.ellipsis ? 1 : null,
              ellipsis: widget.ellipsis ? '…' : null,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: available);
            final result = painter.size;
            painter.dispose();
            return result;
          }

          final rawSize = measure(widget.raw),
              maskSize = measure(widget.masked);
          final width = math.min(
            available,
            math.max(rawSize.width, maskSize.width),
          );
          final height = math.max(rawSize.height, maskSize.height);
          final value = revealed ? widget.raw : widget.masked;
          final baselinePainter = TextPainter(
            text: TextSpan(text: widget.raw, style: style),
            maxLines: widget.ellipsis ? 1 : null,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: available);
          final baseline =
              baselinePainter.computeLineMetrics().firstOrNull?.baseline ??
              height;
          baselinePainter.dispose();
          return _SecretBaseline(
            distance: baseline,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  label: value,
                  excludeSemantics: true,
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: revealed
                        ? Text(
                            value,
                            style: style,
                            maxLines: widget.ellipsis ? 1 : null,
                            overflow: widget.ellipsis
                                ? TextOverflow.ellipsis
                                : TextOverflow.clip,
                          )
                        : CustomPaint(
                            painter: _MaskPainter(
                              value,
                              style,
                              size * .125,
                              widget.ellipsis,
                            ),
                          ),
                  ),
                ),
                if (widget.interactive)
                  Semantics(
                    container: true,
                    button: true,
                    toggled: revealed,
                    label: widget.i18n.t(
                      'secretMask',
                      revealed ? 'secret.hide' : 'secret.reveal',
                    ),
                    child: FocusableActionDetector(
                      shortcuts: const {
                        SingleActivator(LogicalKeyboardKey.enter):
                            ActivateIntent(),
                        SingleActivator(LogicalKeyboardKey.space):
                            ActivateIntent(),
                      },
                      actions: {
                        ActivateIntent: CallbackAction<ActivateIntent>(
                          onInvoke: (_) {
                            toggle();
                            return null;
                          },
                        ),
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          key: const ValueKey('secret-toggle'),
                          behavior: HitTestBehavior.opaque,
                          onTap: toggle,
                          child: Transform.translate(
                            offset: Offset(0, -size * .125),
                            child: SizedBox.square(
                              dimension: control,
                              child: DshIcon(
                                revealed ? _eyeOff : _eye,
                                size: control,
                                color: context.dsh.labelSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Paint the same centered asterisk tile as upstream's 12×20 SVG mask. The
/// underlying measured string retains one advance per mark and every newline.
class _MaskPainter extends CustomPainter {
  const _MaskPainter(this.value, this.style, this.raise, this.ellipsis);
  final String value;
  final TextStyle style;
  final double raise;
  final bool ellipsis;
  @override
  void paint(Canvas canvas, Size size) {
    // Transparent mask runs retain their advances beneath the centered tiles.
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final run in RegExp(r'\*+').allMatches(value)) {
      if (run.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, run.start)));
      }
      spans.add(
        TextSpan(
          text: run.group(0),
          style: TextStyle(color: style.color?.withValues(alpha: 0)),
        ),
      );
      cursor = run.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    final painter = TextPainter(
      text: TextSpan(style: style, children: spans),
      maxLines: ellipsis ? 1 : null,
      ellipsis: ellipsis ? '…' : null,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    painter.paint(canvas, Offset.zero);
    final paint = Paint()
      ..color = style.color!
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < value.length; index++) {
      if (value.codeUnitAt(index) != 42) continue;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 1),
        boxHeightStyle: ui.BoxHeightStyle.max,
      );
      for (final box in boxes) {
        final width = box.right - box.left, height = box.bottom - box.top;
        final scale = math.min(width / 12, height / 20);
        canvas.save();
        canvas.translate(
          box.left + (width - 12 * scale) / 2,
          box.top + (height - 20 * scale) / 2 - raise,
        );
        canvas.scale(scale);
        paint.strokeWidth = 1.5;
        canvas.drawLine(const Offset(6, 5.6), const Offset(6, 14.4), paint);
        canvas.drawLine(
          const Offset(2.19, 7.8),
          const Offset(9.81, 12.2),
          paint,
        );
        canvas.drawLine(
          const Offset(2.19, 12.2),
          const Offset(9.81, 7.8),
          paint,
        );
        canvas.restore();
      }
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(_MaskPainter old) =>
      old.value != value ||
      old.style != style ||
      old.raise != raise ||
      old.ellipsis != ellipsis;
}

/// CustomPaint has no text baseline. Both reveal modes publish the measured
/// value baseline so toggling cannot shift the surrounding paragraph.
class _SecretBaseline extends SingleChildRenderObjectWidget {
  const _SecretBaseline({required this.distance, required super.child});
  final double distance;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSecretBaseline(distance);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSecretBaseline renderObject,
  ) {
    renderObject.distance = distance;
  }
}

class _RenderSecretBaseline extends RenderProxyBox {
  _RenderSecretBaseline(this._distance);
  double _distance;
  set distance(double value) {
    if (value == _distance) return;
    _distance = value;
    markNeedsLayout();
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) => _distance;
  @override
  double computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => _distance;
}
