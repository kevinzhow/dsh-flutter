/// The three-column shell frame (dsh `ui-layout` `AppFrame.tsx`): sidebar,
/// centre and right column, the drag handles, the column solve, the collapse
/// rules, and the seats the other desktop features occupy (`sidebar`, `main`,
/// `rightbar`, `shell.bottom`, `shell.overlay`, `shell.leading`).
///
/// The right column is a track, not a box: its occupant draws its panel
/// anchored to the frame's right edge at the resolved normal width, and the
/// track only decides whether the centre makes room for it. The occupant
/// reports shown/track/fullscreen through `ctx.layout`; fullscreen keeps the
/// reported track but hides the outer resize handle.
library;

import 'dart:async';

import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'layout_feature.dart';

/// Whether the Windows caption row carries the leading controls.
bool windowsCaption(ShellChrome chrome) => chrome.windowsTitlebar;

/// The easing of dsh's column transitions (`--ds-ease-in-out`).
const Curve frameEase = Cubic(0.4, 0, 0.2, 1);

/// `--ds-transition-duration-slow`.
const Duration frameDuration = Duration(milliseconds: 300);

/// The three-column frame of one window.
class AppFrame extends StatefulWidget {
  const AppFrame({
    super.key,
    required this.layout,
    required this.slots,
    this.chrome = const ShellChrome(),
    this.conversationKey = conversationPanelKey,
    this.mainFallback,
    this.disableAnimations = false,
    this.phoneNewSession,
    this.phoneMenuLabel = '',
    this.phoneNewSessionLabel = '',
  });

  /// Starts a Session from the phone top bar; the phone pages are the top bar
  /// and the drawer (below [phoneDrawerBreakpoint]), a desktop window has no
  /// use for it.
  final VoidCallback? phoneNewSession;

  /// Accessible names of the phone top bar's two buttons.
  final String phoneMenuLabel;
  final String phoneNewSessionLabel;

  final LayoutFeature layout;
  final SlotRegistry slots;
  final ShellChrome chrome;

  /// The `main` key that hosts the Conversation.
  final String conversationKey;

  /// Shown when no `main` occupant answers the selected key.
  final WidgetBuilder? mainFallback;

  /// Reduced motion: the tracks never animate.
  final bool disableAnimations;

  @override
  State<AppFrame> createState() => _AppFrameState();
}

class _AppFrameState extends State<AppFrame> {
  LayoutStore get store => widget.layout.store;
  LayoutController get controller => widget.layout.controller;

  void Function()? _off;
  StreamSubscription<String>? _slotSub;
  bool _dragging = false;
  bool _animating = false;
  String? _lastToggle;
  double? _lastViewport;

  /// Distance the current left-edge swipe has travelled.
  double _edgeDx = 0;
  double _sidebarBase = 0;
  double _rightbarBase = 0;
  double _rightbarWidth = 0;
  Columns _cols = const Columns(sidebar: 0, center: 0, rightbar: 0);

  @override
  void initState() {
    super.initState();
    _off = store.subscribe(_changed);
    _slotSub = widget.slots.changes.listen((_) => _changed());
  }

  @override
  void didUpdateWidget(AppFrame old) {
    super.didUpdateWidget(old);
    if (old.layout != widget.layout) {
      _off?.call();
      _off = store.subscribe(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _off?.call();
    unawaited(_slotSub?.cancel());
    super.dispose();
  }

  void _measure(double width) {
    if (width > 0 && width != store.layoutInfo.viewportWidth) {
      // The ResizeObserver of dsh reports after layout; so do we.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) store.setViewportWidth(width);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome = widget.chrome;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        _measure(viewport);
        final info = store.layoutInfo;
        // The solve runs on the measured width as soon as it is known: the
        // store lags by one frame, the grid in dsh does not.
        final vw = viewport > 0 ? viewport : info.viewportWidth;
        final narrow = vw < sidebarAutoCollapse;
        final phone = vw > 0 && vw < phoneDrawerBreakpoint;
        final drawerOpen = phone && info.narrowExpanded;
        // A phone has no rail: the sidebar is a drawer over the page.
        final collapsed = phone
            ? true
            : (narrow ? !info.narrowExpanded : info.sidebar == 0);
        final sidebarPreference = collapsed
            ? 0.0
            : (info.sidebar == 0 ? sidebarDefault : info.sidebar);
        final rightbarPreference = info.rightbar ?? vw * rightbarDefaultRatio;
        final collapsedWidth = chrome.hidesCollapsedRail
            ? 0.0
            : sidebarCollapsed;
        // Opening on a narrow frame collapses the left sidebar: eligibility
        // includes that space before the occupant's first shown report.
        final normal = computeColumns(
          vw,
          !info.rightbarShown && narrow ? 0 : sidebarPreference,
          rightbarPreference,
          collapsedWidth,
        );
        final solved = computeColumns(
          vw,
          sidebarPreference,
          info.rightbarTrack ? rightbarPreference : 0,
          collapsedWidth,
        );
        final cols = phone
            ? Columns(sidebar: 0, center: vw, rightbar: 0)
            : solved;
        _cols = cols;
        _rightbarWidth = normal.rightbar;
        // Track easing is scoped to a discrete open/close toggle: it goes up
        // when the collapse state or the rightbar track flips and comes down
        // at settle. A toggle arriving together with a viewport change is the
        // responsive auto-collapse firing mid window-resize: it stays instant.
        final toggle = '$collapsed:${info.rightbarTrack}';
        final viewportChanged = _lastViewport != null && _lastViewport != vw;
        if (_lastToggle != null && _lastToggle != toggle && !viewportChanged) {
          _animating = true;
          Future<void>.delayed(const Duration(milliseconds: 600), () {
            if (mounted && _animating) setState(() => _animating = false);
          });
        }
        _lastToggle = toggle;
        _lastViewport = vw;
        final instant =
            !_animating ||
            _dragging ||
            info.rightbarInstant ||
            info.rightbarFullscreen ||
            widget.disableAnimations;
        final duration = instant ? Duration.zero : frameDuration;

        final theme = context.dsh;
        final insets = frameInsetsFor(chrome, sidebarCollapsed: collapsed);
        // macOS mounts the seat only while the column is fully hidden;
        // Windows keeps the sidebar toggle in the caption row in both states.
        final leadingMounted =
            (chrome.darwin && collapsed) || windowsCaption(chrome);
        final bottom = widget.slots.renderSingle(
          DshShellSlots.shellBottom.typed<Object?, Widget>(),
          null,
        );
        final overlays = widget.slots.renderList(
          DshShellSlots.shellOverlay.typed<Object?, Widget>(),
          null,
        );
        final drawerWidth = vw * 0.85 < phoneDrawerMaxWidth
            ? vw * 0.85
            : phoneDrawerMaxWidth;
        final sidebar = widget.slots.renderSingle(
          DshShellSlots.sidebar.typed<SidebarOwner, Widget>(),
          SidebarOwner(
            collapsed: phone ? false : collapsed,
            width: phone ? drawerWidth : cols.sidebar,
            drawer: phone,
          ),
        );
        final rightbar = widget.slots.renderSingle(
          DshShellSlots.rightbar.typed<RightbarOwner, Widget>(),
          RightbarOwner(
            width: normal.rightbar,
            viewportWidth: vw,
            canShow: normal.rightbar > 0,
          ),
        );
        final sidebarFill = theme.color('--dsw-specific-sidebar-fill');
        final windows = chrome.windowsTitlebar;
        final darwin = chrome.darwin;
        // The sidebar column: macOS keeps only a translucent tint of the fill
        // (dsh lets the window vibrancy through it); Windows paints the fill
        // behind the whole caption row.
        final sidebarColor = darwin
            ? sidebarFill.withValues(alpha: 0.4)
            : sidebarFill;
        final hairline = dshHairlineOf(context);
        final columns = Stack(
          fit: StackFit.expand,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AnimatedTrack(
                  width: cols.sidebar,
                  duration: duration,
                  child: phone
                      ? const SizedBox.shrink()
                      : ClipRect(
                          child: DshDecoratedBox(
                            decoration: BoxDecoration(
                              color: sidebarColor,
                              border: darwin || windows
                                  ? null
                                  : Border(
                                      right: BorderSide(
                                        color: theme.color(
                                          '--dsw-alias-border-l3',
                                        ),
                                        width: hairline,
                                      ),
                                    ),
                            ),
                            child: sidebar ?? const SizedBox.shrink(),
                          ),
                        ),
                ),
                Expanded(
                  child: _Centre(
                    darwinSeparator: darwin && !collapsed,
                    windowsRadius: windows,
                    separatorColor: theme.color('--dsw-alias-border-l3'),
                    background: theme.bgBase,
                    child: DshRightbarHost(
                      child: _MainPanel(host: widget, store: store),
                    ),
                  ),
                ),
                _AnimatedTrack(
                  width: cols.rightbar,
                  duration: duration,
                  child: const SizedBox.shrink(),
                ),
              ],
            ),
            // The right column's occupant anchors its panel to this layer's
            // right edge; with no track it hangs over the centre.
            if (rightbar != null) Positioned.fill(child: rightbar),
            if (phone) ...[
              if (!drawerOpen)
                // The left edge opens the drawer by a swipe.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 20,
                  child: GestureDetector(
                    key: const ValueKey('phone-edge'),
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: (_) => _edgeDx = 0,
                    onHorizontalDragUpdate: (d) {
                      // One swipe opens the drawer once.
                      final before = _edgeDx;
                      _edgeDx += d.delta.dx;
                      if (before < 24 && _edgeDx >= 24) {
                        controller.toggleSidebar();
                      }
                    },
                  ),
                ),
              Positioned.fill(
                child: _PhoneDrawer(
                  open: drawerOpen,
                  width: drawerWidth,
                  fill: sidebarFill,
                  border: theme.color('--dsw-alias-border-l3'),
                  scrim: theme.color('--dsw-alias-bg-mask-1'),
                  disableAnimations:
                      widget.disableAnimations ||
                      MediaQuery.disableAnimationsOf(context),
                  onClose: controller.closeNarrowSidebar,
                  child: sidebar ?? const SizedBox.shrink(),
                ),
              ),
            ],
            if (!collapsed)
              _Handle(
                key: const ValueKey('frame-handle-sidebar'),
                left: cols.sidebar,
                onStart: () {
                  _sidebarBase = _cols.sidebar;
                  setState(() => _dragging = true);
                },
                onDrag: (dx) => store.setSidebar(_sidebarBase + dx),
                onEnd: () => setState(() => _dragging = false),
              ),
            if (info.rightbarShown &&
                !info.rightbarFullscreen &&
                normal.rightbar > 0)
              _Handle(
                key: const ValueKey('frame-handle-rightbar'),
                left: vw - normal.rightbar,
                onStart: () {
                  _rightbarBase = _rightbarWidth;
                  setState(() => _dragging = true);
                },
                onDrag: (dx) => store.setRightbar(_rightbarBase - dx),
                onEnd: () => setState(() => _dragging = false),
              ),
          ],
        );
        Widget frame = ColoredBox(
          color: windows
              ? sidebarFill
              : (darwin ? theme.bgBase.withAlpha(0) : theme.bgBase),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (windows) _Caption(chrome: chrome, fill: sidebarFill),
              Expanded(child: columns),
              if (bottom != null)
                ColoredBox(color: theme.bgBase, child: bottom),
            ],
          ),
        );
        frame = Stack(
          fit: StackFit.expand,
          children: [
            frame,
            if (leadingMounted)
              Positioned(
                top: chrome.windowsTitlebar
                    ? (windowsTitlebarHeight - 28) / 2
                    : 11,
                left: chrome.windowsTitlebar
                    ? 12
                    : (chrome.fullscreen ? 12 : 88),
                child:
                    widget.slots.renderSingle(
                      DshShellSlots.shellLeading.typed<Object?, Widget>(),
                      null,
                    ) ??
                    const SizedBox.shrink(),
              ),
            if (overlays.isNotEmpty)
              Positioned.fill(
                child: Stack(
                  key: const ValueKey('frame-overlay'),
                  fit: StackFit.expand,
                  children: overlays,
                ),
              ),
          ],
        );
        Widget scoped = FrameInsetsScope(insets: insets, child: frame);
        if (phone) {
          scoped = PhoneChrome(
            openDrawer: controller.toggleSidebar,
            newSession: widget.phoneNewSession ?? () {},
            menuLabel: widget.phoneMenuLabel,
            newSessionLabel: widget.phoneNewSessionLabel,
            child: scoped,
          );
        }
        return PopScope(
          // The system back button closes the drawer before it leaves.
          canPop: !drawerOpen,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) controller.closeNarrowSidebar();
          },
          child: ShellScope(chrome: chrome, child: scoped),
        );
      },
    );
  }
}

/// One grid track: its width follows the solve, easing only while a discrete
/// toggle is in flight.
class _AnimatedTrack extends StatelessWidget {
  const _AnimatedTrack({
    required this.width,
    required this.duration,
    required this.child,
  });

  final double width;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: width),
      duration: duration,
      curve: frameEase,
      builder: (context, w, child) => SizedBox(width: w, child: child),
      child: child,
    );
  }
}

/// The centre column: the conversation or a global panel, with the separators
/// dsh draws per platform.
class _Centre extends StatelessWidget {
  const _Centre({
    required this.darwinSeparator,
    required this.windowsRadius,
    required this.separatorColor,
    required this.background,
    required this.child,
  });

  final bool darwinSeparator;
  final bool windowsRadius;
  final Color separatorColor;
  final Color background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hairline = dshHairlineOf(context);
    return DshDecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: darwinSeparator
            ? Border(
                left: BorderSide(color: separatorColor, width: hairline),
              )
            : null,
        borderRadius: windowsRadius
            ? const BorderRadius.only(
                topLeft: Radius.circular(windowsContentRadius),
              )
            : null,
      ),
      child: ClipRRect(
        borderRadius: windowsRadius
            ? const BorderRadius.only(
                topLeft: Radius.circular(windowsContentRadius),
              )
            : BorderRadius.zero,
        child: child,
      ),
    );
  }
}

/// Subscribes to the main key without rebuilding the frame for each panel id.
class _MainPanel extends StatelessWidget {
  const _MainPanel({required this.host, required this.store});

  final AppFrame host;
  final LayoutStore store;

  @override
  Widget build(BuildContext context) {
    return _PanelBuilder(
      store: store,
      builder: (context, id) {
        final key = id ?? host.conversationKey;
        final built = host.slots.renderKeyed(
          DshShellSlots.main.typed<Object?, Widget>(),
          key,
          null,
        );
        return built ??
            host.mainFallback?.call(context) ??
            const SizedBox.shrink();
      },
    );
  }
}

class _PanelBuilder extends StatefulWidget {
  const _PanelBuilder({required this.store, required this.builder});

  final LayoutStore store;
  final Widget Function(BuildContext context, String? panelId) builder;

  @override
  State<_PanelBuilder> createState() => _PanelBuilderState();
}

class _PanelBuilderState extends State<_PanelBuilder> {
  void Function()? _off;
  String? _id;

  @override
  void initState() {
    super.initState();
    _id = widget.store.panelInfo.activePanelId;
    _off = widget.store.subscribe(() {
      final next = widget.store.panelInfo.activePanelId;
      if (next != _id && mounted) setState(() => _id = next);
    });
  }

  @override
  void dispose() {
    _off?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _id);
}

/// One drag handle: an 8px hit strip centred on the column border, reporting
/// the drag distance against the drag-start origin.
class _Handle extends StatefulWidget {
  const _Handle({
    super.key,
    required this.left,
    required this.onStart,
    required this.onDrag,
    required this.onEnd,
  });

  final double left;
  final VoidCallback onStart;
  final void Function(double dx) onDrag;
  final VoidCallback onEnd;

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  double _origin = 0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.left - 4,
      top: 0,
      bottom: 0,
      width: 8,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (d) {
            _origin = d.globalPosition.dx;
            widget.onStart();
          },
          onHorizontalDragUpdate: (d) =>
              widget.onDrag(d.globalPosition.dx - _origin),
          onHorizontalDragEnd: (_) => widget.onEnd(),
          onHorizontalDragCancel: widget.onEnd,
        ),
      ),
    );
  }
}

/// The Windows caption row: the sidebar fill over the full width, the caption
/// buttons at the right end, and the drag area for the rest (the sidebar
/// toggle and New Session controls sit on it from `sidebar`).
class _Caption extends StatelessWidget {
  const _Caption({required this.chrome, required this.fill});

  final ShellChrome chrome;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final row = ColoredBox(
      color: fill,
      child: SizedBox(
        height: windowsTitlebarHeight,
        child: Row(
          children: [
            const Expanded(child: SizedBox.expand()),
            if (!chrome.fullscreen && chrome.captionControls != null)
              chrome.captionControls!,
          ],
        ),
      ),
    );
    return chrome.drag(row);
  }
}

/// The phone drawer: the sidebar slid over the page under a scrim. A tap on the
/// scrim or a swipe toward the edge closes it.
class _PhoneDrawer extends StatefulWidget {
  const _PhoneDrawer({
    required this.open,
    required this.width,
    required this.fill,
    required this.border,
    required this.scrim,
    required this.disableAnimations,
    required this.onClose,
    required this.child,
  });

  final bool open;
  final double width;
  final Color fill;
  final Color border;
  final Color scrim;
  final bool disableAnimations;
  final VoidCallback onClose;
  final Widget child;

  @override
  State<_PhoneDrawer> createState() => _PhoneDrawerState();
}

class _PhoneDrawerState extends State<_PhoneDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.open ? 1 : 0,
  );

  @override
  void didUpdateWidget(_PhoneDrawer old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    if (widget.disableAnimations) {
      _t.value = widget.open ? 1 : 0;
    } else {
      unawaited(widget.open ? _t.forward() : _t.reverse());
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final progress = frameEase.transform(_t.value);
        if (_t.value == 0 && !widget.open) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('phone-scrim'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                child: ColoredBox(
                  color: widget.scrim.withValues(
                    alpha: widget.scrim.a * progress,
                  ),
                ),
              ),
            ),
            Positioned(
              left: -widget.width * (1 - progress),
              top: 0,
              bottom: 0,
              width: widget.width,
              child: GestureDetector(
                key: const ValueKey('phone-drawer'),
                onHorizontalDragUpdate: (d) {
                  if (d.delta.dx < -6) widget.onClose();
                },
                child: DshDecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.fill,
                    border: Border(
                      right: BorderSide(color: widget.border, width: 0.5),
                    ),
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
