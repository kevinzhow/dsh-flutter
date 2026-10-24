import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dsh_attachment.dart' show DshSpinner;
import 'dsh_icon.dart';
import 'dsh_icons.g.dart';
import 'dsh_text_baseline.dart';
import 'dsh_text_scale.dart';
import 'theme_access.dart';

/// One image of the lightbox: its bytes, or a loader (a durable image that is
/// not in memory yet) and a failure line for when the load fails.
class DshLightboxImage {
  const DshLightboxImage({required this.label, this.bytes, this.load});

  final String label;
  final Uint8List? bytes;
  final Future<Uint8List> Function()? load;
}

/// Strings of the lightbox.
class DshLightboxLabels {
  const DshLightboxLabels({
    required this.dialog,
    required this.close,
    required this.loadFailed,
    required this.position,
  });

  /// Accessible name of the dialog ("Original image preview").
  final String dialog;
  final String close;
  final String loadFailed;

  /// "2 / 5".
  final String Function(int index, int total) position;
}

/// Open dsh's original-image preview (`ImageLightbox`) over the app: the mask,
/// the image fitted to the screen, a close control; on a phone pinch to zoom,
/// double tap to toggle, drag to pan, and swipe between the images of a
/// message. Closes on a tap on the mask, the close control, Escape or back.
Future<void> showDshLightbox(
  BuildContext context, {
  required List<DshLightboxImage> images,
  required DshLightboxLabels labels,
  int initialIndex = 0,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, _, _) => DshLightbox(
        images: images,
        labels: labels,
        initialIndex: initialIndex,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The lightbox page; use [showDshLightbox] to open it.
class DshLightbox extends StatefulWidget {
  const DshLightbox({
    super.key,
    required this.images,
    required this.labels,
    this.initialIndex = 0,
  });

  final List<DshLightboxImage> images;
  final DshLightboxLabels labels;
  final int initialIndex;

  @override
  State<DshLightbox> createState() => _DshLightboxState();
}

class _DshLightboxState extends State<DshLightbox> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final total = widget.images.length;
    final top = MediaQuery.paddingOf(context).top;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: widget.labels.dialog,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
        child: Focus(
          autofocus: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                key: const ValueKey('lightbox-mask'),
                behavior: HitTestBehavior.opaque,
                onTap: _zoomed ? null : _close,
                child: ColoredBox(color: theme.color('--dsw-alias-bg-mask-1')),
              ),
              PageView.builder(
                controller: _pages,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: total,
                onPageChanged: (i) => setState(() {
                  _index = i;
                  _zoomed = false;
                }),
                itemBuilder: (context, i) => _LightboxPage(
                  key: ValueKey('lightbox-page-$i'),
                  image: widget.images[i],
                  labels: widget.labels,
                  onZoomed: (zoomed) {
                    if (i == _index && zoomed != _zoomed) {
                      setState(() => _zoomed = zoomed);
                    }
                  },
                  onBackdropTap: _close,
                ),
              ),
              Positioned(
                top: top + 20,
                right: 20,
                child: Semantics(
                  button: true,
                  label: widget.labels.close,
                  child: GestureDetector(
                    key: const ValueKey('lightbox-close'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.color('--dsw-specific-input-major'),
                            border: Border.all(
                              color: theme.color(
                                '--dsw-alias-border-l2-darkmode-thin',
                              ),
                              width: dshHairline,
                            ),
                          ),
                          child: Center(
                            child: DshIcon(
                              DshIcons.close,
                              size: 16,
                              color: theme.labelPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (total > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.paddingOf(context).bottom + 20,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        key: const ValueKey('lightbox-position'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: theme.color('--dsw-specific-input-major'),
                        ),
                        child: DshChromeText(
                          widget.labels.position(_index + 1, total),
                          style: theme
                              .textStyle('--dsw-font-xxs-12')
                              .sized(12, line: 18)
                              .copyWith(color: theme.labelPrimary),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LightboxPage extends StatefulWidget {
  const _LightboxPage({
    super.key,
    required this.image,
    required this.labels,
    required this.onZoomed,
    required this.onBackdropTap,
  });

  final DshLightboxImage image;
  final DshLightboxLabels labels;
  final ValueChanged<bool> onZoomed;
  final VoidCallback onBackdropTap;

  @override
  State<_LightboxPage> createState() => _LightboxPageState();
}

class _LightboxPageState extends State<_LightboxPage> {
  final TransformationController _controller = TransformationController();
  Uint8List? _bytes;
  bool _failed = false;
  Offset _doubleTapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _bytes = widget.image.bytes;
    _controller.addListener(
      () => widget.onZoomed(_controller.value.getMaxScaleOnAxis() > 1.01),
    );
    if (_bytes == null) _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final bytes = await widget.image.load!();
      if (mounted) setState(() => _bytes = bytes);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_controller.value.getMaxScaleOnAxis() > 1.01) {
      _controller.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    final p = _doubleTapAt;
    _controller.value = Matrix4.identity()
      ..translateByDouble(-p.dx * (scale - 1), -p.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final bytes = _bytes;
    if (bytes == null) {
      return Center(
        child: _failed
            ? GestureDetector(
                key: const ValueKey('lightbox-retry'),
                onTap: _load,
                child: DshChromeText(
                  widget.labels.loadFailed,
                  style: theme
                      .textStyle('--dsw-font-s-14')
                      .copyWith(color: theme.labelPrimary),
                ),
              )
            : DshSpinner(size: 28, color: theme.labelPrimary),
      );
    }
    final pad = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, pad.top + 56, 16, pad.bottom + 56),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
        onDoubleTap: _toggleZoom,
        onTap: widget.onBackdropTap,
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 1,
          maxScale: 6,
          clipBehavior: Clip.none,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(theme.radiusLg),
              child: Image.memory(
                bytes,
                key: const ValueKey('lightbox-image'),
                fit: BoxFit.contain,
                semanticLabel: widget.image.label,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => DshChromeText(
                  widget.labels.loadFailed,
                  style: theme
                      .textStyle('--dsw-font-s-14')
                      .copyWith(color: theme.labelPrimary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
