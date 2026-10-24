import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// The mark Whalee draws in `sidebar.brand.mark` when no occupant replaces it:
/// the product's own simple whale glyph, in the text ink. (dsh draws the
/// DeepSeek whale here; that is a brand asset Whalee does not use.)
class WhaleeMark extends StatelessWidget {
  const WhaleeMark({super.key, required this.size, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MarkPainter(color ?? context.dsh.labelPrimary),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()..color = color;
    // A rounded body, a tail fluke and a spout: 24x24 artwork.
    final body = Path()
      ..moveTo(2 * s, 14 * s)
      ..cubicTo(2 * s, 8 * s, 7 * s, 5 * s, 12 * s, 5 * s)
      ..cubicTo(17 * s, 5 * s, 20 * s, 8 * s, 21 * s, 11 * s)
      ..cubicTo(22 * s, 8.5 * s, 22 * s, 6 * s, 21 * s, 4 * s)
      ..cubicTo(23.5 * s, 5.5 * s, 24 * s, 9 * s, 23 * s, 13 * s)
      ..cubicTo(22 * s, 17 * s, 17 * s, 20 * s, 11 * s, 20 * s)
      ..cubicTo(6 * s, 20 * s, 2 * s, 18 * s, 2 * s, 14 * s)
      ..close();
    canvas.drawPath(body, paint);
    final eye = Paint()..blendMode = BlendMode.clear;
    canvas.drawCircle(Offset(8 * s, 12 * s), 1.1 * s, eye);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}
