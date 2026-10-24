import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

import 'dsh_corners.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// One painted shape of a [DshArtwork]: SVG path data in a view box, stroked
/// with [strokeWidth] or filled, in its own colour.
class DshArtworkShape {
  const DshArtworkShape(
    this.path,
    this.color, {
    this.strokeWidth,
    this.evenOdd = false,
  });

  final String path;
  final Color color;

  /// Null fills the path.
  final double? strokeWidth;
  final bool evenOdd;
}

/// Fixed-colour artwork of dsh's primitives (the guide cards' glyphs), which a
/// single-colour [DshIcon] cannot draw.
class DshArtwork extends StatelessWidget {
  const DshArtwork({
    super.key,
    required this.shapes,
    required this.viewBox,
    required this.size,
  });

  final List<DshArtworkShape> shapes;
  final double viewBox;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _ArtworkPainter(shapes, viewBox),
    ),
  );
}

final Map<String, Path> _artworkPaths = {};

class _ArtworkPainter extends CustomPainter {
  _ArtworkPainter(this.shapes, this.viewBox);
  final List<DshArtworkShape> shapes;
  final double viewBox;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / viewBox);
    for (final shape in shapes) {
      final path = _artworkPaths.putIfAbsent(
        shape.path,
        () => parseSvgPathData(shape.path),
      )..fillType = shape.evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
      final paint = Paint()
        ..color = shape.color
        ..isAntiAlias = true;
      if (shape.strokeWidth == null) {
        paint.style = PaintingStyle.fill;
      } else {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = shape.strokeWidth!;
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArtworkPainter old) =>
      old.viewBox != viewBox || !identical(old.shapes, shapes);
}

/// The light-blue terminal artwork of plugin cards and the terminal's guide
/// card (dsh `PluginArtworkTerminal`).
class DshTerminalArtwork extends StatelessWidget {
  const DshTerminalArtwork({super.key, this.size = 36});
  final double size;

  static const _shapes = [
    DshArtworkShape(
      'M10 11L16.606 17.606C16.6841 17.6841 16.6841 17.8107 16.606 17.8888L10 24.4948',
      Color(0xFF679EFE),
      strokeWidth: 3.5,
    ),
    DshArtworkShape(
      'M20.1211 24.4946H26.8685',
      Color(0xFF679EFE),
      strokeWidth: 3.5,
    ),
  ];

  @override
  Widget build(BuildContext context) =>
      DshArtwork(shapes: _shapes, viewBox: 36, size: size);
}

/// The terminal tile of the missing-terminal panel (dsh `TerminalBody`): a dark
/// rounded square with the white prompt.
class DshTerminalTile extends StatelessWidget {
  const DshTerminalTile({super.key, this.size = 36});
  final double size;

  static const _shapes = [
    DshArtworkShape(
      'M6 5H22A3 3 0 0 1 25 8V21A3 3 0 0 1 22 24H6A3 3 0 0 1 3 21V8A3 3 0 0 1 6 5Z',
      Color(0xFF17191D),
    ),
    DshArtworkShape(
      'M8 10L12 14L8 18M15 18H20',
      Color(0xFFFFFFFF),
      strokeWidth: 1.7,
    ),
  ];

  @override
  Widget build(BuildContext context) =>
      DshArtwork(shapes: _shapes, viewBox: 28, size: size);
}

/// The folder artwork of the workspace files' guide card (dsh
/// `GuideArtworkFiles`).
class DshFilesArtwork extends StatelessWidget {
  const DshFilesArtwork({super.key, this.size = 36});
  final double size;

  static const _shapes = [
    DshArtworkShape(
      'M10.7603 27.922H24.6817C26.3441 27.922 27.1753 27.922 27.8102 27.5984C28.3687 27.3139 28.8228 26.8598 29.1074 26.3012C29.4309 25.6663 29.4309 24.8351 29.4309 23.1727V15.4936',
      Color(0xFFFFCD78),
      strokeWidth: 1.97886,
    ),
    DshArtworkShape(
      'M13.1597 8.07812C13.4182 8.07818 13.6727 8.14336 13.8989 8.26855L16.7554 9.84961C16.9817 9.97485 17.2369 10.041 17.4956 10.041H26.106C26.9492 10.0412 27.6323 10.7251 27.6323 11.5684V24.5371C27.6323 25.3805 26.9483 26.0645 26.105 26.0645H8.09619C7.25281 26.0645 6.56884 25.3805 6.56885 24.5371V9.60449C6.56909 8.76133 7.25297 8.07812 8.09619 8.07812H13.1597ZM9.81592 14.5508V16.5293H24.3999V14.5508H9.81592Z',
      Color(0xFFFFBC4D),
    ),
  ];

  @override
  Widget build(BuildContext context) =>
      DshArtwork(shapes: _shapes, viewBox: 36, size: size);
}

/// The guide's compass (dsh `CompassGlyph`): a ring and the needle's rhombus on
/// [color].
class DshCompassGlyph extends StatelessWidget {
  const DshCompassGlyph({super.key, this.size = 16, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => DshArtwork(
    viewBox: 16,
    size: size,
    shapes: [
      DshArtworkShape(
        'M8 14C11.3137 14 14 11.3137 14 8C14 4.68629 11.3137 2 8 2C4.68629 2 2 4.68629 2 8C2 11.3137 4.68629 14 8 14Z',
        color,
        strokeWidth: 1,
      ),
      DshArtworkShape(
        'M10.6101 5.39014L8.99014 8.99014L5.39014 10.6101L7.01014 7.01014L10.6101 5.39014Z',
        color,
      ),
    ],
  );
}

/// The terminal prompt glyph of terminal tab titles (dsh `TerminalIcon`).
class DshTerminalGlyph extends StatelessWidget {
  const DshTerminalGlyph({super.key, this.size = 16, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => DshArtwork(
    viewBox: 16,
    size: size,
    shapes: [
      DshArtworkShape('M3 4L7 8L3 12', color, strokeWidth: 1),
      DshArtworkShape('M9 12H13', color, strokeWidth: 1),
    ],
  );
}

/// One capsule of the sidebar's guide page (dsh `GuideBody.module.css`
/// `.entry`): the type's glyph, its title and description, and an optional
/// trailing control beside the title. [onTap] opens the type.
class DshGuideCard extends StatefulWidget {
  const DshGuideCard({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.titleTrailing,
    this.onTap,
    this.semanticLabel,
  });

  /// The glyph, drawn in a 26px box.
  final Widget icon;
  final String title;
  final String? description;

  /// A control placed after the title (the terminal's shell menu).
  final Widget? titleTrailing;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<DshGuideCard> createState() => _DshGuideCardState();
}

class _DshGuideCardState extends State<DshGuideCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final radius = theme.number('--dsw-radius-xl');
    final fill = _pressed
        ? theme.interactiveBgHover
        : theme.color('--dsw-alias-bg-layer-1');
    final titleStyle = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(height: 1.4, color: theme.labelPrimary);
    final descriptionStyle = theme
        .textStyle('--dsw-font-xxxs-11')
        .copyWith(
          height: 1.4,
          color: theme.color('--dsw-alias-label-tertiary'),
        );
    final description = widget.description;
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel ?? widget.title,
      excludeSemantics: widget.titleTrailing == null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, minHeight: 56),
          child: DecoratedBox(
            decoration: context.dshOutlined(
              radius,
              fill: fill,
              border: theme.borderL3,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: Center(child: widget.icon),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: DshChromeText(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle,
                              ),
                            ),
                            if (widget.titleTrailing != null) ...[
                              const SizedBox(width: 4),
                              widget.titleTrailing!,
                            ],
                          ],
                        ),
                        if (description != null) ...[
                          const SizedBox(height: 3),
                          DshChromeText(
                            description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: descriptionStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
