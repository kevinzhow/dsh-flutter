import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter/painting.dart' show Alignment;

/// The pixel size of an encoded image read from its header (PNG, JPEG, GIF
/// and WebP, the types dsh accepts), or null when [bytes] is none of them.
///
/// Decoding an image at its display size keeps a gallery of large photos
/// light, but the size to decode at depends on the picture's own aspect ratio
/// (see [dshDecodeTarget]), which only the header gives without decoding.
({int width, int height})? dshImageSize(Uint8List bytes) {
  int u16be(int i) => (bytes[i] << 8) | bytes[i + 1];
  int u32be(int i) => (u16be(i) << 16) | u16be(i + 2);
  int u16le(int i) => bytes[i] | (bytes[i + 1] << 8);
  int u24le(int i) => bytes[i] | (bytes[i + 1] << 8) | (bytes[i + 2] << 16);
  bool tag(int i, String text) {
    if (i + text.length > bytes.length) return false;
    for (var k = 0; k < text.length; k++) {
      if (bytes[i + k] != text.codeUnitAt(k)) return false;
    }
    return true;
  }

  final n = bytes.length;
  // PNG: signature, then the IHDR chunk with the size at 16..24.
  if (n >= 24 && bytes[0] == 0x89 && tag(1, 'PNG') && tag(12, 'IHDR')) {
    return (width: u32be(16), height: u32be(20));
  }
  // GIF: logical screen size at 6..10 (little endian).
  if (n >= 10 && (tag(0, 'GIF87a') || tag(0, 'GIF89a'))) {
    return (width: u16le(6), height: u16le(8));
  }
  // JPEG: the first start-of-frame marker holds the size.
  if (n >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var i = 2;
    while (i + 9 < n) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = bytes[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 1) {
        i += 2;
        continue;
      }
      final isFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isFrame) return (width: u16be(i + 7), height: u16be(i + 5));
      i += 2 + u16be(i + 2);
    }
    return null;
  }
  // WebP: RIFF container with a lossy (VP8), lossless (VP8L) or extended chunk.
  if (n >= 30 && tag(0, 'RIFF') && tag(8, 'WEBP')) {
    if (tag(12, 'VP8X')) {
      return (width: u24le(24) + 1, height: u24le(27) + 1);
    }
    if (tag(12, 'VP8L') && bytes[20] == 0x2F) {
      final bits =
          bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
      return (width: (bits & 0x3FFF) + 1, height: ((bits >> 14) & 0x3FFF) + 1);
    }
    if (tag(12, 'VP8 ')) {
      return (width: u16le(26) & 0x3FFF, height: u16le(28) & 0x3FFF);
    }
  }
  return null;
}

/// How an image of [source] pixels is fitted into a [box] of device pixels.
enum DshImageFit { cover, contain }

/// The `cacheWidth` / `cacheHeight` that decode an image of [source] pixels
/// just large enough to fill [box] (device pixels) under [fit], keeping the
/// aspect ratio: exactly one of the two is set, or both are null when the
/// source is no larger than needed (decoding never upscales).
({int? width, int? height}) dshDecodeTarget(
  ({int width, int height})? source,
  Size box,
  DshImageFit fit,
) {
  final bw = math.max(1, box.width.ceil());
  final bh = math.max(1, box.height.ceil());
  if (source == null || source.width <= 0 || source.height <= 0) {
    // Unknown size: fit the width, the safe choice for portrait and square.
    return (width: bw, height: null);
  }
  final sx = bw / source.width;
  final sy = bh / source.height;
  final scale = fit == DshImageFit.cover ? math.max(sx, sy) : math.min(sx, sy);
  if (scale >= 1) return (width: null, height: null);
  final byWidth = fit == DshImageFit.cover ? sx >= sy : sx <= sy;
  return byWidth ? (width: bw, height: null) : (width: null, height: bh);
}

/// The alignment that places an image of [source] pixels in [box] (logical
/// pixels) where Chromium paints it: `object-fit` computes the picture's
/// rectangle in CSS pixels and snaps its position to a whole CSS pixel (half
/// up), so a 93 by 62 picture in a 62 box starts at -15, not at -15.5, which
/// is one device pixel at 2x. [base] is the CSS `object-position`.
Alignment dshSnappedAlignment({
  required Size box,
  required ({int width, int height})? source,
  required DshImageFit fit,
  Alignment base = Alignment.center,
}) {
  if (source == null || source.width <= 0 || source.height <= 0) return base;
  final sx = box.width / source.width;
  final sy = box.height / source.height;
  final scale = fit == DshImageFit.cover ? math.max(sx, sy) : math.min(sx, sy);
  double axis(double boxExtent, double imageExtent, double a) {
    final free = boxExtent - imageExtent * scale;
    if (free.abs() < 1e-9) return a;
    final position = (free * (a + 1) / 2 + 0.5).floorToDouble();
    return 2 * position / free - 1;
  }

  return Alignment(
    axis(box.width, source.width.toDouble(), base.x),
    axis(box.height, source.height.toDouble(), base.y),
  );
}
