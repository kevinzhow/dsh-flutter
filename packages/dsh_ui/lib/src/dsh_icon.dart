import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

import 'dsh_icon_data.dart';

/// Draws a [DshIconData] in [color] at [size] (default: the glyph's own size).
class DshIcon extends StatelessWidget {
  const DshIcon(this.icon, {super.key, this.size, required this.color});

  final DshIconData icon;
  final double? size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final edge = size ?? icon.size.toDouble();
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(edge),
        painter: _IconPainter(icon, color),
      ),
    );
  }
}

final Map<DshIconData, List<Path>> _paths = Map.identity();

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color);

  final DshIconData icon;
  final Color color;

  List<Path> get _shapes => _paths.putIfAbsent(
    icon,
    () => [
      for (final shape in icon.shapes)
        parseSvgPathData(shape.path)
          ..fillType = shape.evenOdd
              ? PathFillType.evenOdd
              : PathFillType.nonZero,
    ],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / icon.viewBox;
    canvas.save();
    canvas.scale(scale);
    final paths = _shapes;
    for (var i = 0; i < paths.length; i++) {
      final shape = icon.shapes[i];
      final paint = Paint()
        ..color = color
        ..isAntiAlias = true;
      if (shape.fill) {
        paint.style = PaintingStyle.fill;
      } else {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = icon.strokeWidth
          ..strokeCap = switch (shape.cap) {
            DshIconCap.butt => StrokeCap.butt,
            DshIconCap.round => StrokeCap.round,
            DshIconCap.square => StrokeCap.square,
          }
          ..strokeJoin = StrokeJoin.miter;
      }
      canvas.drawPath(paths[i], paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color;
}
