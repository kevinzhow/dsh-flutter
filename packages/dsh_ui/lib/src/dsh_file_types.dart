import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

import 'dsh_file_types.g.dart';
import 'theme_access.dart';

export 'dsh_file_types.g.dart' hide dshFileGlyphs, dshFolderGlyph;

/// One mark path of a glyph: filled, or stroked when [strokeWidth] is set.
class DshGlyphShape {
  const DshGlyphShape(this.path, {this.strokeWidth, this.evenOdd = false});
  final String path;
  final double? strokeWidth;
  final bool evenOdd;
}

/// A category mark on the page glyph. [markScale] scales it about (14, 16);
/// [muted] draws the grey `other` page (no mark, grey fold).
class DshFileGlyph {
  const DshFileGlyph({
    required this.markScale,
    required this.muted,
    required this.shapes,
  });
  final double? markScale;
  final bool muted;
  final List<DshGlyphShape> shapes;
}

class DshFolderGlyph {
  const DshFolderGlyph(
    this.body,
    this.mark,
    this.markStroke,
    this.markY,
    this.markScale,
  );
  final String body;
  final String mark;
  final double markStroke;
  final double markY;
  final double markScale;
}

/// The glyph kind of a path (dsh `classifyFileType`): `code` for every code or
/// configuration file (dsh's per-language artwork is not ported), then the
/// document categories, `other` last.
String dshClassifyFileType(String path) {
  final slash = [
    path.lastIndexOf('/'),
    path.lastIndexOf(r'\'),
  ].reduce((a, b) => a > b ? a : b);
  final name = path.substring(slash + 1).toLowerCase();
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1);
  if (_isCode(name, ext)) return 'code';
  return dshFileTypeByName[name] ?? dshFileTypeByExtension[ext] ?? 'other';
}

bool _isCode(String name, String ext) {
  if (dshCodeFileNames.contains(name)) return true;
  for (final p in dshCodeFileNamePrefixes) {
    if (name.startsWith(p)) return true;
  }
  for (final s in dshCodeFileNameSuffixes) {
    if (name.endsWith(s)) return true;
  }
  return dshCodeFileExtensions.contains(ext);
}

/// The extension of a file name without its dot, as written (dsh
/// `fileExtension`).
String dshFileExtension(String path) {
  final slash = [
    path.lastIndexOf('/'),
    path.lastIndexOf(r'\'),
  ].reduce((a, b) => a > b ? a : b);
  final name = path.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1);
}

/// dsh `fileSizeText`: whole units, one decimal below ten of the unit.
String dshFileSizeText(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  String unit(double v, String suffix) =>
      '${v < 10 ? v.toStringAsFixed(1) : v.round()}$suffix';
  final kb = bytes / 1024;
  if (kb < 1024) return unit(kb, 'KB');
  final mb = kb / 1024;
  if (mb < 1024) return unit(mb, 'MB');
  return unit(mb / 1024, 'GB');
}

/// The colour a glyph kind is drawn in (FileTypeIcon.module.css).
Color _kindColor(DshThemeContextRead theme, String kind) => switch (kind) {
  'code' || 'html' || 'markdown' => theme('--dsw-static-deepseek-500'),
  'excel' => theme('--dsw-static-green-500'),
  'folder' => theme('--dsw-static-amber-400'),
  'image' || 'video' => const Color(dshFileTypeViolet),
  'pdf' => theme('--dsw-static-red-600'),
  'ppt' => theme('--dsw-static-amber-500'),
  'word' => theme('--dsw-static-deepseek-450'),
  _ => theme('--dsw-static-neutral-bluish-300'),
};

typedef DshThemeContextRead = Color Function(String token);

/// dsh's `FileTypeIcon`: a page with a folded corner and a category mark, or a
/// folder. Give a [path] to classify or an explicit [kind].
class DshFileTypeIcon extends StatelessWidget {
  const DshFileTypeIcon({super.key, this.path, this.kind, this.size = 28})
    : assert(path != null || kind != null);

  final String? path;
  final String? kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final resolved = kind ?? dshClassifyFileType(path!);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _FileGlyphPainter(
          kind: resolved,
          color: _kindColor(theme.color, resolved),
          mark: theme.color('--dsw-static-neutral-00'),
          mutedFold: theme.color('--dsw-static-neutral-400'),
        ),
      ),
    );
  }
}

class _FileGlyphPainter extends CustomPainter {
  _FileGlyphPainter({
    required this.kind,
    required this.color,
    required this.mark,
    required this.mutedFold,
  });

  final String kind;
  final Color color;
  final Color mark;
  final Color mutedFold;

  static final Map<String, Path> _paths = {};
  static Path _path(String data, bool evenOdd) => _paths.putIfAbsent(
    '$evenOdd$data',
    () =>
        parseSvgPathData(data)
          ..fillType = evenOdd ? PathFillType.evenOdd : PathFillType.nonZero,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28);
    if (kind == 'folder') {
      canvas.drawPath(
        _path(dshFolderGlyph.body, false),
        Paint()..color = color,
      );
      canvas.save();
      canvas.translate(14, dshFolderGlyph.markY);
      canvas.scale(dshFolderGlyph.markScale);
      canvas.translate(-14, -dshFolderGlyph.markY);
      canvas.drawPath(
        _path(dshFolderGlyph.mark, false),
        Paint()
          ..color = mark
          ..style = PaintingStyle.stroke
          ..strokeWidth = dshFolderGlyph.markStroke,
      );
      canvas.restore();
      canvas.restore();
      return;
    }
    final glyph = dshFileGlyphs[kind] ?? dshFileGlyphs['other']!;
    canvas.drawPath(_path(dshFileBodyPath, false), Paint()..color = color);
    canvas.drawPath(
      _path(dshFileFoldPath, false),
      Paint()..color = glyph.muted ? mutedFold : mark.withValues(alpha: 0.7),
    );
    if (glyph.shapes.isNotEmpty) {
      canvas.save();
      final scale = glyph.markScale;
      if (scale != null) {
        canvas.translate(14, 16);
        canvas.scale(scale);
        canvas.translate(-14, -16);
      }
      for (final shape in glyph.shapes) {
        final paint = Paint()..color = mark;
        if (shape.strokeWidth != null) {
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = shape.strokeWidth!;
        }
        canvas.drawPath(_path(shape.path, shape.evenOdd), paint);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FileGlyphPainter old) =>
      old.kind != kind ||
      old.color != color ||
      old.mark != mark ||
      old.mutedFold != mutedFold;
}
