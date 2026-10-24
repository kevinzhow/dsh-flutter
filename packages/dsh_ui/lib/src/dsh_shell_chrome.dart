import 'package:flutter/widgets.dart';

/// The platform whose window chrome the frame draws (dsh `data-platform` and
/// `data-windows-titlebar`). Linux keeps the native window frame in dsh's
/// desktop app too, so it is [other]: the frame draws no chrome of its own.
enum ShellPlatform { darwin, windows, other }

/// Height of the Windows caption row dsh reserves above all columns.
const double windowsTitlebarHeight = 40;

/// The step below the window's top strip on macOS (traffic lights, sidebar
/// toggle, `shell.leading` controls): entry pages pad their top by it.
const double darwinTopClearance = 48;

/// The inline band the macOS window chrome occupies at the frame's left edge
/// while the `shell.leading` seat is mounted: traffic lights to x 68, controls
/// at x 88 (28 + 8 + 28), then 8px of air.
const double darwinLeadingClearance = 160;

/// The same band in native fullscreen, where the traffic lights are hidden.
const double darwinLeadingClearanceFullscreen = 84;

/// Radius of the content area's top-left corner under the Windows caption.
const double windowsContentRadius = 16;

/// What the frame needs to know about the window it sits in. The app supplies
/// it (it owns the window); the frame stays free of any window plugin.
class ShellChrome {
  const ShellChrome({
    this.platform = ShellPlatform.other,
    this.fullscreen = false,
    this.captionControls,
    this.dragArea,
  });

  final ShellPlatform platform;

  /// Native fullscreen: the traffic lights and caption controls are gone.
  final bool fullscreen;

  /// The caption buttons (minimise, maximise, close) a Windows window draws at
  /// the right end of the caption row.
  final Widget? captionControls;

  /// Wraps a chrome row so that pressing and dragging it moves the window;
  /// null where the window cannot be dragged from the content.
  final Widget Function(Widget child)? dragArea;

  /// macOS: the hiddenInset window with its sidebar tint and traffic lights.
  bool get darwin => platform == ShellPlatform.darwin;

  /// Windows: the hidden title bar with its 40px caption row.
  bool get windowsTitlebar => platform == ShellPlatform.windows;

  /// Whether a closed sidebar hides its column instead of keeping the rail.
  bool get hidesCollapsedRail => darwin || windowsTitlebar;

  /// The height reserved above all columns.
  double get titlebarHeight => windowsTitlebar ? windowsTitlebarHeight : 0;

  /// Wraps [child] in the window drag area when there is one.
  Widget drag(Widget child) => dragArea?.call(child) ?? child;

  @override
  bool operator ==(Object other) =>
      other is ShellChrome &&
      other.platform == platform &&
      other.fullscreen == fullscreen &&
      other.captionControls == captionControls &&
      other.dragArea == dragArea;

  @override
  int get hashCode =>
      Object.hash(platform, fullscreen, captionControls, dragArea);
}

/// Provides the [ShellChrome] to everything under the frame.
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.chrome, required super.child});

  final ShellChrome chrome;

  /// The enclosing chrome; plain (no window chrome) outside a frame.
  static ShellChrome of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>()?.chrome ??
      const ShellChrome();

  @override
  bool updateShouldNotify(ShellScope oldWidget) => chrome != oldWidget.chrome;
}

/// The insets the frame publishes (dsh `--dsh-frame-*` custom properties).
class FrameInsets {
  const FrameInsets({
    this.topClearance = 0,
    this.leadingClearance = 0,
    this.overlayTop = 0,
    this.chromeTop = 0,
  });

  /// `--dsh-frame-top-clearance`: the step below the window's top strip (48 on
  /// macOS, the caption height on Windows, 0 elsewhere).
  final double topClearance;

  /// `--dsh-frame-leading-clearance`: the inline band the window chrome
  /// occupies while `shell.leading` is mounted; a main panel whose content
  /// reaches the top-left corner pads by it.
  final double leadingClearance;

  /// `--dsh-frame-overlay-top`: the inset dialogs and menus keep from the top.
  final double overlayTop;

  /// `--dsh-frame-chrome-top`: the caption a modal mask leaves uncovered.
  final double chromeTop;

  @override
  bool operator ==(Object other) =>
      other is FrameInsets &&
      other.topClearance == topClearance &&
      other.leadingClearance == leadingClearance &&
      other.overlayTop == overlayTop &&
      other.chromeTop == chromeTop;

  @override
  int get hashCode =>
      Object.hash(topClearance, leadingClearance, overlayTop, chromeTop);
}

/// Provides the [FrameInsets] to everything under the frame.
class FrameInsetsScope extends InheritedWidget {
  const FrameInsetsScope({
    super.key,
    required this.insets,
    required super.child,
  });

  final FrameInsets insets;

  /// The enclosing insets; zero outside a frame.
  static FrameInsets of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FrameInsetsScope>()?.insets ??
      const FrameInsets();

  @override
  bool updateShouldNotify(FrameInsetsScope oldWidget) =>
      insets != oldWidget.insets;
}

/// The insets dsh publishes for [chrome] with the sidebar collapsed or not.
FrameInsets frameInsetsFor(
  ShellChrome chrome, {
  required bool sidebarCollapsed,
}) {
  final top = chrome.darwin
      ? darwinTopClearance
      : chrome.windowsTitlebar
      ? windowsTitlebarHeight
      : 0.0;
  final overlay = chrome.darwin || chrome.windowsTitlebar
      ? (chrome.fullscreen ? 20.0 : top + 20)
      : 0.0;
  return FrameInsets(
    topClearance: top,
    leadingClearance: chrome.darwin && sidebarCollapsed
        ? (chrome.fullscreen
              ? darwinLeadingClearanceFullscreen
              : darwinLeadingClearance)
        : 0,
    overlayTop: overlay,
    chromeTop: chrome.windowsTitlebar && !chrome.fullscreen
        ? windowsTitlebarHeight
        : 0,
  );
}
