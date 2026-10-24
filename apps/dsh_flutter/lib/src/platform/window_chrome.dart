/// The desktop window around the shell (dsh `apps/desktop` `createWindow` and
/// `windows-layout.ts`): its size, the title bar per platform and the caption
/// buttons Windows needs once the title bar is hidden.
///
/// - **macOS** (dsh: `hiddenInset`, traffic lights at (16, 18), vibrancy): the
///   title bar is hidden and the traffic lights stay; the frame clears them. The
///   lights keep the position the toolkit gives them (not (16, 18)) and there is
///   no vibrancy: the sidebar draws a translucent tint of its fill over the
///   window background instead.
/// - **Windows** (dsh: hidden title bar with a 40px native caption overlay): the
///   title bar is hidden, the frame draws a 40px caption row and these buttons.
///   Windows draws the real ones in dsh; these are Flutter drawings of the same
///   three buttons (46x40).
/// - **Linux**: dsh keeps the native window frame, so does Whalee.
///
/// macOS and Windows builds are not available where this was written: the
/// window options and the caption buttons compile on every platform but have
/// only run on Linux (where they do nothing).
library;

import 'dart:io' show Platform;

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../app_identity.dart';

/// Window width and height dsh opens with, and the floor it allows.
const Size initialWindowSize = Size(1280, 820);
const Size minimumWindowSize = Size(520, 600);

/// The window size of this run: [initialWindowSize], or `WHALEE_WINDOW_SIZE`
/// (`1280x720`) when set. The override exists for the parity captures, which
/// need exact content sizes (and narrower windows than the usual floor); a
/// malformed value is ignored.
Size windowSizeFromEnvironment() {
  final raw = Platform.environment['WHALEE_WINDOW_SIZE'];
  final match = raw == null ? null : RegExp(r'^(\d+)x(\d+)$').firstMatch(raw);
  if (match == null) return initialWindowSize;
  return Size(double.parse(match[1]!), double.parse(match[2]!));
}

/// Whether this process is a desktop app with a window of its own.
bool get hasDesktopWindow =>
    !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

/// The window of the running desktop app.
class WindowChrome with WindowListener {
  WindowChrome._(this._platform)
    : _notifier = ValueNotifier(ShellChrome(platform: _platform));

  final ShellPlatform _platform;
  final ValueNotifier<ShellChrome> _notifier;
  bool _maximized = false;
  bool _fullscreen = false;

  /// The chrome the frame draws, following fullscreen.
  ValueListenable<ShellChrome> get chrome => _notifier;

  /// Configure and show the window; null where there is no desktop window.
  static Future<WindowChrome?> init() async {
    if (!hasDesktopWindow) return null;
    final platform = Platform.isMacOS
        ? ShellPlatform.darwin
        : Platform.isWindows
        ? ShellPlatform.windows
        : ShellPlatform.other;
    await windowManager.ensureInitialized();
    final self = WindowChrome._(platform);
    windowManager.addListener(self);
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: windowSizeFromEnvironment(),
        // A capture run asks for phone widths, below the usual floor.
        minimumSize: Platform.environment.containsKey('WHALEE_WINDOW_SIZE')
            ? const Size(200, 200)
            : minimumWindowSize,
        center: true,
        title: appDisplayName,
        titleBarStyle: platform == ShellPlatform.other
            ? TitleBarStyle.normal
            : TitleBarStyle.hidden,
        windowButtonVisibility: platform == ShellPlatform.darwin,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    self._publish();
    return self;
  }

  void _publish() {
    _notifier.value = ShellChrome(
      platform: _platform,
      fullscreen: _fullscreen,
      captionControls: _platform == ShellPlatform.windows
          ? WindowsCaptionButtons(maximized: _maximized)
          : null,
      dragArea: _platform == ShellPlatform.other
          ? null
          : (child) => DragToMoveArea(child: child),
    );
  }

  /// The window title (`document.title` in dsh).
  void setTitle(String title) => windowManager.setTitle(title);

  @override
  void onWindowEnterFullScreen() {
    _fullscreen = true;
    _publish();
  }

  @override
  void onWindowLeaveFullScreen() {
    _fullscreen = false;
    _publish();
  }

  @override
  void onWindowMaximize() {
    _maximized = true;
    _publish();
  }

  @override
  void onWindowUnmaximize() {
    _maximized = false;
    _publish();
  }
}

/// Windows' caption buttons: minimise, maximise or restore, close; 46 by 40.
class WindowsCaptionButtons extends StatelessWidget {
  const WindowsCaptionButtons({super.key, required this.maximized});

  final bool maximized;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          key: const ValueKey('caption-minimize'),
          glyph: _Glyph.minimize,
          onPressed: windowManager.minimize,
        ),
        _CaptionButton(
          key: const ValueKey('caption-maximize'),
          glyph: maximized ? _Glyph.restore : _Glyph.maximize,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _CaptionButton(
          key: const ValueKey('caption-close'),
          glyph: _Glyph.close,
          danger: true,
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

enum _Glyph { minimize, maximize, restore, close }

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    super.key,
    required this.glyph,
    required this.onPressed,
    this.danger = false,
  });

  final _Glyph glyph;
  final VoidCallback onPressed;
  final bool danger;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final danger = widget.danger && _hover;
    final ink = danger
        ? theme.color('--dsw-static-neutral-bluish-00')
        : theme.labelPrimary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: SizedBox(
          width: 46,
          height: 40,
          child: DshDecoratedBox(
            decoration: BoxDecoration(
              color: danger
                  ? theme.color('--dsw-alias-state-error-primary')
                  : _hover
                  ? theme.interactiveBgHover
                  : null,
            ),
            child: CustomPaint(painter: _GlyphPainter(widget.glyph, ink)),
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final c = Offset(size.width / 2, size.height / 2);
    switch (glyph) {
      case _Glyph.minimize:
        canvas.drawLine(
          Offset(c.dx - 5, c.dy + 0.5),
          Offset(c.dx + 5, c.dy + 0.5),
          paint,
        );
      case _Glyph.maximize:
        canvas.drawRect(Rect.fromCenter(center: c, width: 9, height: 9), paint);
      case _Glyph.restore:
        canvas.drawRect(Rect.fromLTWH(c.dx - 5, c.dy - 2, 8, 8), paint);
        final back = Path()
          ..moveTo(c.dx - 2, c.dy - 2)
          ..lineTo(c.dx - 2, c.dy - 5)
          ..lineTo(c.dx + 6, c.dy - 5)
          ..lineTo(c.dx + 6, c.dy + 3)
          ..lineTo(c.dx + 3, c.dy + 3);
        canvas.drawPath(back, paint);
      case _Glyph.close:
        canvas.drawLine(
          Offset(c.dx - 5, c.dy - 5),
          Offset(c.dx + 5, c.dy + 5),
          paint,
        );
        canvas.drawLine(
          Offset(c.dx + 5, c.dy - 5),
          Offset(c.dx - 5, c.dy + 5),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
