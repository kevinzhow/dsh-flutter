import 'package:flutter/painting.dart';

/// This style at an exact pixel size and line height, for the few places dsh's
/// stylesheets set a literal size (11px counts, 12px captions) that is not a
/// rung of the type ladder. The size is a delta from the ladder rung, so the
/// user's font-size setting still moves it.
extension DshTextSize on TextStyle {
  TextStyle sized(double size, {double? line}) {
    final scaled = apply(fontSizeDelta: size - fontSize!);
    return line == null ? scaled : scaled.copyWith(height: line / size);
  }
}

/// A colour from 0xRRGGBB, for literal ANSI colours that carry their own
/// foreground and background in terminal output.
Color dshRgb(int rgb) => Color.from(
  alpha: 1,
  red: ((rgb >> 16) & 255) / 255,
  green: ((rgb >> 8) & 255) / 255,
  blue: (rgb & 255) / 255,
);
