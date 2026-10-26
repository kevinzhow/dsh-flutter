import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('joined left edge retains only its two outer curves', () {
    const rect = Rect.fromLTWH(0, 0, 100, 32);
    const shape = DshCornerBorder(
      radius: 12,
      corners: BorderRadius.only(
        topLeft: Radius.circular(12),
        bottomLeft: Radius.circular(12),
      ),
    );
    final path = shape.getOuterPath(rect);
    expect(path.contains(const Offset(.5, .5)), isFalse);
    expect(path.contains(const Offset(.5, 31.5)), isFalse);
    expect(path.contains(const Offset(99.5, .5)), isTrue);
    expect(path.contains(const Offset(99.5, 31.5)), isTrue);
    expect(path.getBounds(), rect);
  });
  test('CSS scales overlapping radii together and zero axes are square', () {
    const rect = Rect.fromLTWH(0, 0, 100, 20);
    final large = dshSuperellipseCornersPath(
      rect,
      BorderRadius.circular(40),
      1,
    );
    final scaled = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)));
    for (var y = 0.5; y < 20; y++) {
      for (var x = .5; x < 100; x++) {
        expect(large.contains(Offset(x, y)), scaled.contains(Offset(x, y)));
      }
    }
    final zeroAxis = dshSuperellipseCornersPath(
      rect,
      const BorderRadius.only(topRight: Radius.elliptical(12, 0)),
      1.5,
    );
    expect(zeroAxis.contains(const Offset(99.5, .5)), isTrue);
  });
  test('independent corners retain border inset and scale without sharing a cached shape', () {
    const rect = Rect.fromLTWH(0, 0, 100, 32);
    const corners = BorderRadius.only(
      topLeft: Radius.circular(12),
      bottomLeft: Radius.circular(12),
    );
    const joined = DshCornerBorder(
      radius: 12,
      corners: corners,
      side: BorderSide(width: 1),
    );
    expect(joined.getInnerPath(rect).getBounds(), rect.deflate(1));
    expect(joined.getInnerPath(rect).contains(const Offset(99.5, .5)), isFalse);
    final scaled = joined.scale(.5) as DshCornerBorder;
    expect(scaled.corners!.topLeft, const Radius.circular(6));
    expect(scaled.corners!.topRight, Radius.zero);
    expect(scaled.side.width, .5);
    expect(joined.copyWith(corners: BorderRadius.zero), isNot(joined));
  });
}
