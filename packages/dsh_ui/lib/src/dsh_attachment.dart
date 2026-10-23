import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';

import 'dsh_file_types.dart';
import 'dsh_icon.dart';
import 'dsh_icons.g.dart';
import 'dsh_text_scale.dart';
import 'theme_access.dart';

// ---------------------------------------------------------------------------
// File card (dsh ui-attachment FileCard) and the message file card (ui-chat)
// ---------------------------------------------------------------------------

/// Strings of a pending-file card (dsh `FileCardLabels`).
class DshFileCardLabels {
  const DshFileCardLabels({
    required this.label,
    required this.remove,
    required this.uploading,
    required this.failed,
    required this.retry,
  });

  /// Announcement of the card body, e.g. "Pending files".
  final String label;
  final String remove;

  /// Status line while the upload is in flight.
  final String uploading;

  /// Status line after a failed upload.
  final String failed;
  final String retry;
}

enum DshFileCardState { uploading, ready, error }

bool get _touchPlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.fuchsia;

/// The small round remove control of a draft attachment: always there on touch
/// platforms (`pointer: coarse`), on hover or focus elsewhere.
class DshRemoveBadge extends StatelessWidget {
  const DshRemoveBadge({
    super.key,
    required this.label,
    required this.onPressed,
    required this.visible,
    this.error = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool visible;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final fill = error
        ? theme.color('--dsw-alias-state-error-primary')
        : theme.color('--dsw-alias-button-contrast-fill');
    final shown = visible || error;
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          // A 44 point target around the 18 point badge on phones.
          child: SizedBox(
            width: 18,
            height: 18,
            child: Opacity(
              opacity: shown ? 1 : 0,
              child: DecoratedBox(
                decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                child: Center(
                  child: DshIcon(
                    DshIcons.closeFill,
                    size: 12,
                    color: error
                        ? theme.color('--dsw-static-neutral-00')
                        : theme.color('--dsw-alias-label-primary-inverted'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One pending file in the composer's rail (dsh `FileCard`): type glyph (a
/// spinner while uploading), name, `EXT SIZE` or the upload status, a remove
/// badge and a progress bar. A failed card is one retry control.
class DshFileCard extends StatefulWidget {
  const DshFileCard({
    super.key,
    required this.name,
    required this.bytes,
    required this.state,
    required this.labels,
    required this.onRemove,
    required this.onRetry,
    this.progress,
    this.forceRemoveVisible,
  });

  final String name;
  final int bytes;
  final DshFileCardState state;

  /// 0..1 when the carrier reports a total; null is the indeterminate bar.
  final double? progress;
  final DshFileCardLabels labels;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  /// Overrides the platform rule (touch: visible, otherwise on hover).
  final bool? forceRemoveVisible;

  @override
  State<DshFileCard> createState() => _DshFileCardState();
}

class _DshFileCardState extends State<DshFileCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final w = widget;
    final extension = dshFileExtension(w.name).toUpperCase();
    final shortExtension = extension.length > 8
        ? extension.substring(0, 8)
        : extension;
    final meta = switch (w.state) {
      DshFileCardState.uploading => w.labels.uploading,
      DshFileCardState.error => w.labels.failed,
      DshFileCardState.ready => [
        shortExtension,
        dshFileSizeText(w.bytes),
      ].where((p) => p.isNotEmpty).join(' '),
    };
    final failed = w.state == DshFileCardState.error;
    final removeVisible = w.forceRemoveVisible ?? (_touchPlatform || _hover);
    final nameStyle = theme
        .textStyle('--dsw-font-s-14')
        .sized(14, line: 22)
        .copyWith(color: theme.labelPrimary, fontWeight: FontWeight.w500);
    final metaStyle = theme
        .textStyle('--dsw-font-xxs-12')
        .sized(12, line: 15)
        .copyWith(
          color: failed
              ? theme.color('--dsw-alias-state-error-primary')
              : theme.color('--dsw-alias-label-tertiary'),
        );
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            w.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: nameStyle,
          ),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: metaStyle,
          ),
        ],
      ),
    );
    return MouseRegion(
      onEnter: (e) {
        if (e.kind == PointerDeviceKind.mouse) setState(() => _hover = true);
      },
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        container: true,
        label: w.name,
        child: SizedBox(
          key: const ValueKey('file-card'),
          width: 240,
          height: 64,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.color('--dsw-specific-input-major'),
              borderRadius: BorderRadius.circular(theme.radiusLg),
              border: Border.all(
                color: failed
                    ? theme.color('--dsw-alias-state-error-primary')
                    : theme.color('--dsw-alias-border-l2'),
                width: dshHairline,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(
                          child: w.state == DshFileCardState.uploading
                              ? DshSpinner(size: 20, color: theme.labelPrimary)
                              : DshFileTypeIcon(path: w.name),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: failed
                            ? Semantics(
                                button: true,
                                label: w.labels.retry,
                                child: GestureDetector(
                                  key: const ValueKey('file-card-retry'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: w.onRetry,
                                  child: ExcludeSemantics(child: body),
                                ),
                              )
                            : Semantics(label: w.labels.label, child: body),
                      ),
                    ],
                  ),
                ),
                if (w.state == DshFileCardState.uploading)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 5,
                    height: 2,
                    child: DshProgressTrack(progress: w.progress),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: DshRemoveBadge(
                    key: const ValueKey('file-card-remove'),
                    label: w.labels.remove,
                    onPressed: w.onRemove,
                    visible: removeVisible,
                    error: failed,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 2 point upload bar: a determinate fill, or the sliding 35% band.
class DshProgressTrack extends StatefulWidget {
  const DshProgressTrack({super.key, this.progress});
  final double? progress;

  @override
  State<DshProgressTrack> createState() => _DshProgressTrackState();
}

class _DshProgressTrackState extends State<DshProgressTrack>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate =
        widget.progress == null && !MediaQuery.disableAnimationsOf(context);
    if (animate && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat(reverse: true);
    } else if (!animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void didUpdateWidget(DshProgressTrack old) {
    super.didUpdateWidget(old);
    didChangeDependencies();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final track = theme
        .color('--dsw-static-neutral-1000')
        .withValues(alpha: 0.08);
    final bar = theme.color('--dsw-alias-brand-primary');
    return ClipRRect(
      borderRadius: BorderRadius.circular(1),
      child: ColoredBox(
        color: track,
        child: LayoutBuilder(
          builder: (context, c) {
            final fraction = widget.progress;
            if (fraction != null) {
              return Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: ColoredBox(color: bar, child: const SizedBox.expand()),
                ),
              );
            }
            final width = c.maxWidth * 0.35;
            final t = _controller?.value ?? 0;
            // translateX(-70% .. 220%) of the band.
            final dx = (-0.7 + t * 2.9) * width;
            return Stack(
              children: [
                Positioned(
                  left: dx,
                  width: width,
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(color: bar),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The spinning ring of dsh's upload card (2 point border, one open quarter).
class DshSpinner extends StatefulWidget {
  const DshSpinner({super.key, this.size = 20, required this.color});
  final double size;
  final Color color;

  @override
  State<DshSpinner> createState() => _DshSpinnerState();
}

class _DshSpinnerState extends State<DshSpinner>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !MediaQuery.disableAnimationsOf(context);
    if (animate && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
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
    final ring = CustomPaint(
      size: Size.square(widget.size),
      painter: _RingPainter(widget.color),
    );
    final c = _controller;
    return ExcludeSemantics(
      child: c == null ? ring : RotationTransition(turns: c, child: ring),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    // `border-top-color: transparent`: three quarters drawn, the top open.
    canvas.drawArc(
      rect.deflate(stroke / 2),
      -math.pi / 4,
      math.pi * 1.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}

/// The file card of a sent message (dsh ui-chat `UserContent`): glyph, name and
/// `EXT SIZE`, 240 wide with a 64 minimum height. Not interactive, like the
/// web client's.
class DshMessageFileCard extends StatelessWidget {
  const DshMessageFileCard({
    super.key,
    required this.name,
    required this.bytes,
  });

  final String name;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final extension = dshFileExtension(name).toUpperCase();
    final meta = [
      extension.length > 8 ? extension.substring(0, 8) : extension,
      dshFileSizeText(bytes),
    ].where((p) => p.isNotEmpty).join(' ');
    return Container(
      key: const ValueKey('message-file-card'),
      width: 240,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.color('--dsw-specific-input-major'),
        borderRadius: BorderRadius.circular(theme.radiusLg),
        border: Border.all(
          color: theme.color('--dsw-alias-border-l2'),
          width: dshHairline,
        ),
      ),
      child: Semantics(
        label: name,
        child: Row(
          children: [
            DshFileTypeIcon(path: name),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .sized(14, line: 22)
                        .copyWith(
                          color: theme.labelPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .textStyle('--dsw-font-xxs-12')
                        .sized(12, line: 15)
                        .copyWith(
                          color: theme.color('--dsw-alias-label-tertiary'),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Image frames (dsh ui-attachment MessageImage)
// ---------------------------------------------------------------------------

/// How a message image is framed: a lone image at 240 on its longer edge, a
/// fixed 64 square among several, or an uncropped 48 square for a list row.
enum DshImageVariant { single, tile, thumbnail }

/// Strings of a message image.
class DshImageLabels {
  const DshImageLabels({
    required this.open,
    required this.openNamed,
    required this.loading,
    required this.loadFailed,
    required this.image,
    required this.lightbox,
    required this.closeLightbox,
  });

  /// Tooltip inviting the original.
  final String open;
  final String Function(String label) openNamed;
  final String loading;
  final String loadFailed;

  /// Fallback name of an unnamed image.
  final String image;

  /// Accessible name of the lightbox dialog.
  final String lightbox;
  final String closeLightbox;
}

/// dsh `singleFit`: the display box of a lone image: long edge 240, aspect
/// clamped to [0.25, 4], never upscaled.
({double width, double height, Alignment alignment}) dshSingleFit(
  int width,
  int height,
) {
  final natural = width / height;
  final ratio = natural.clamp(0.25, 4.0);
  final boxW = ratio >= 1 ? 240.0 : 240.0 * ratio;
  final boxH = ratio >= 1 ? 240.0 / ratio : 240.0;
  final scale = math.min(1.0, math.min(width / boxW, height / boxH));
  return (
    width: math.max(1, (boxW * scale).roundToDouble()),
    height: math.max(1, (boxH * scale).roundToDouble()),
    alignment: natural < 0.25
        ? Alignment.topCenter
        : natural > 4
        ? Alignment.centerLeft
        : Alignment.center,
  );
}

/// One image of a gallery: the frame, its loading and failure states. The
/// caller owns the loading ([bytes] null while [failed] is false is loading).
class DshImageFrame extends StatelessWidget {
  const DshImageFrame({
    super.key,
    required this.variant,
    required this.labels,
    this.bytes,
    this.failed = false,
    this.width,
    this.height,
    this.name,
    this.onOpen,
    this.onRetry,
  });

  final DshImageVariant variant;
  final DshImageLabels labels;
  final Uint8List? bytes;
  final bool failed;

  /// Intrinsic size when known (sizes a `single` image).
  final int? width;
  final int? height;
  final String? name;
  final VoidCallback? onOpen;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final label = name == null || name!.isEmpty ? labels.image : name!;
    final side = switch (variant) {
      DshImageVariant.single => null,
      DshImageVariant.tile => 64.0,
      DshImageVariant.thumbnail => 48.0,
    };
    final radius = BorderRadius.circular(
      variant == DshImageVariant.thumbnail ? theme.radiusLg : theme.radiusXl,
    );
    final border = Border.all(
      color: theme.color('--dsw-alias-border-l2-darkmode-thin'),
      width: dshHairline,
    );
    final tertiary = theme
        .textStyle('--dsw-font-xxs-12')
        .sized(12, line: 18)
        .copyWith(color: theme.color('--dsw-alias-label-tertiary'));
    if (failed) {
      final thumb = variant == DshImageVariant.thumbnail;
      return Semantics(
        button: true,
        label: labels.loadFailed,
        child: GestureDetector(
          key: const ValueKey('image-retry'),
          behavior: HitTestBehavior.opaque,
          onTap: onRetry,
          child: Container(
            width: side ?? 240,
            height: side,
            constraints: side == null
                ? const BoxConstraints(maxWidth: 240)
                : null,
            padding: thumb
                ? const EdgeInsets.all(2)
                : variant == DshImageVariant.tile
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.color('--dsw-alias-interactive-bg-hover-danger'),
              borderRadius: variant == DshImageVariant.single
                  ? BorderRadius.circular(theme.radiusMd)
                  : radius,
              border: border,
            ),
            alignment: Alignment.center,
            child: thumb
                ? DshIcon(
                    DshIcons.refresh,
                    size: 16,
                    color: theme.color('--dsw-alias-label-tertiary'),
                  )
                : Text(
                    labels.loadFailed,
                    maxLines: variant == DshImageVariant.tile ? 3 : null,
                    overflow: TextOverflow.ellipsis,
                    style: tertiary,
                  ),
          ),
        ),
      );
    }
    double? boxW = side;
    double? boxH = side;
    var alignment = Alignment.center;
    if (variant == DshImageVariant.single) {
      if (width != null && height != null && width! > 0 && height! > 0) {
        final fit = dshSingleFit(width!, height!);
        boxW = fit.width;
        boxH = fit.height;
        alignment = fit.alignment;
      } else {
        // A preview whose size is unknown yet is a square crop.
        boxW = 240;
        boxH = 240;
      }
    }
    final loaded = bytes;
    final Widget content = loaded == null
        ? Center(
            child: variant == DshImageVariant.thumbnail
                ? DshSpinner(
                    size: 16,
                    color: theme.color('--dsw-alias-label-tertiary'),
                  )
                : Text(labels.loading, style: tertiary),
          )
        : Image.memory(
            loaded,
            fit: variant == DshImageVariant.thumbnail
                ? BoxFit.contain
                : BoxFit.cover,
            alignment: alignment,
            gaplessPlayback: true,
            semanticLabel: label,
            // Decoding at the frame's size keeps a 20 image gallery light.
            cacheWidth: (boxW! * MediaQuery.devicePixelRatioOf(context)).ceil(),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
    return Semantics(
      button: true,
      label: loaded == null ? labels.loading : labels.openNamed(label),
      child: GestureDetector(
        key: const ValueKey('image-open'),
        behavior: HitTestBehavior.opaque,
        onTap: loaded == null ? null : onOpen,
        child: Container(
          width: boxW,
          height: boxH,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: variant == DshImageVariant.thumbnail
              ? const EdgeInsets.all(2)
              : EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.interactiveBgHover,
            borderRadius: radius,
            border: border,
          ),
          child: ExcludeSemantics(child: content),
        ),
      ),
    );
  }
}

/// The wrapping image group of a message (dsh `ImageGallery`): [children]
/// 10 apart, right- or left-aligned.
class DshImageGroup extends StatelessWidget {
  const DshImageGroup({
    super.key,
    required this.children,
    this.alignEnd = false,
  });

  final List<Widget> children;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
        children: children,
      ),
    );
  }
}

/// The draft thumbnail of the composer rail: a 64 square with a remove badge.
class DshDraftImage extends StatefulWidget {
  const DshDraftImage({
    super.key,
    required this.bytes,
    required this.name,
    required this.removeLabel,
    required this.openLabel,
    required this.onOpen,
    required this.onRemove,
    this.forceRemoveVisible,
  });

  final Uint8List bytes;
  final String name;
  final String removeLabel;
  final String openLabel;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final bool? forceRemoveVisible;

  @override
  State<DshDraftImage> createState() => _DshDraftImageState();
}

class _DshDraftImageState extends State<DshDraftImage> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final visible = widget.forceRemoveVisible ?? (_touchPlatform || _hover);
    return MouseRegion(
      onEnter: (e) {
        if (e.kind == PointerDeviceKind.mouse) setState(() => _hover = true);
      },
      onExit: (_) => setState(() => _hover = false),
      child: SizedBox(
        key: const ValueKey('draft-image'),
        width: 64,
        height: 64,
        child: Stack(
          children: [
            Semantics(
              button: true,
              label: widget.openLabel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpen,
                child: Container(
                  width: 64,
                  height: 64,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: theme.interactiveBgHover,
                    borderRadius: BorderRadius.circular(theme.radiusXl),
                    border: Border.all(
                      color: theme.color('--dsw-alias-border-l2-darkmode-thin'),
                      width: dshHairline,
                    ),
                  ),
                  child: ExcludeSemantics(
                    child: Image.memory(
                      widget.bytes,
                      fit: BoxFit.cover,
                      cacheWidth: (64 * MediaQuery.devicePixelRatioOf(context))
                          .ceil(),
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: DshRemoveBadge(
                key: const ValueKey('draft-image-remove'),
                label: widget.removeLabel,
                onPressed: widget.onRemove,
                visible: visible,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
