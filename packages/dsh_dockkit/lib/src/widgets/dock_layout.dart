/// The docking surface (dsh `ui-dockkit` `DockLayout`/`DockSurface`): a split
/// tree of tabbed panes. It renders a [DockController]'s layout and reports
/// settled intents (one per gesture, never a drag frame) back to it; tab
/// bodies, tab titles and every string come from the embedder.
///
/// Gestures: click or Enter/Space selects a chip, the close control and the
/// chip menu close it, a chip drags (a press and move) onto another strip to
/// reorder or move, or onto a pane body to move it in or split the pane on an
/// edge; dividers drag and commit one resize on release. Floating panels are
/// supported by the engine but this surface does not draw them.
library;

import 'dart:ui' as ui;

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../engine/constraints.dart';
import '../engine/controller.dart';
import '../engine/geometry.dart';
import '../engine/tree.dart';
import '../engine/types.dart';
import 'dock_labels.dart';

/// Renders one tab's body, flush to the pane's edges.
typedef DockTabBuilder = Widget Function(BuildContext context, TabRecord tab);

/// What a chip shows as its title; null falls back to the record's `title`.
typedef DockTitleBuilder = Widget? Function(
  BuildContext context,
  TabRecord tab,
);

/// Extra items at the end of one tab's context menu. Every item must call
/// `dismiss` when it acts.
typedef DockMenuItemsBuilder = List<Widget> Function(
  BuildContext context,
  TabRecord tab,
  VoidCallback dismiss,
);

const double _stripHeight = 38;
const double _chipHeight = 28;
const double _chipMin = 80;
const double _chipMax = 170;

/// The docking surface of one [DockController].
class DockLayout extends StatefulWidget {
  const DockLayout({
    super.key,
    required this.controller,
    required this.labels,
    required this.renderTab,
    this.renderTabTitle,
    this.renderTabMenuItems,
    this.canAddTab,
    this.canCloseTab,
    this.onCloseTab,
    this.keepMounted,
    this.chrome,
    this.minPaneFraction = 0.2,
    this.hideSplitWhenBlocked = false,
    this.horizontalDrops = true,
    this.stripInlineStart = 10,
    this.onFocusBody,
  });

  final DockController controller;
  final DockLabels labels;
  final DockTabBuilder renderTab;
  final DockTitleBuilder? renderTabTitle;
  final DockMenuItemsBuilder? renderTabMenuItems;

  /// Per pane: whether the strip draws the add control (default: every pane).
  final bool Function(PaneId paneId)? canAddTab;

  /// Per tab: whether the chip's close control and the menu's close item exist.
  final bool Function(TabId tabId)? canCloseTab;

  /// Takes over closing a tab (cleanup first); defaults to closing it in the
  /// controller.
  final void Function(TabId tabId)? onCloseTab;

  /// Whether a visited tab's body stays mounted while another tab is in front.
  final bool Function(TabRecord tab)? keepMounted;

  /// Surface-wide controls at the far end of the top-right pane's strip.
  final Widget? chrome;

  /// Smallest pane share a divider drag may leave.
  final double minPaneFraction;

  /// Hide a blocked split control instead of drawing it disabled.
  final bool hideSplitWhenBlocked;

  /// Offer two half-pane hints for an edge drop (the right sidebar's rule).
  final bool horizontalDrops;

  /// Inset of the first chip from the strip's edge.
  final double stripInlineStart;

  /// Called when a pane body is pressed.
  final VoidCallback? onFocusBody;

  @override
  State<DockLayout> createState() => _DockLayoutState();
}

class _DockLayoutState extends State<DockLayout> {
  final Map<String, GlobalKey> _bodyKeys = {};
  DropTarget? _drop;
  TabId? _dragging;
  final Map<String, Size> _paneSizes = {};
  void Function()? _off;

  DockController get controller => widget.controller;
  LayoutState get layout => controller.snapshot.state;

  @override
  void initState() {
    super.initState();
    _off = controller.subscribe(_changed);
  }

  @override
  void didUpdateWidget(DockLayout old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _off?.call();
      _off = widget.controller.subscribe(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _off?.call();
    super.dispose();
  }

  GlobalKey _keyFor(TabId id) => _bodyKeys.putIfAbsent(id, GlobalKey.new);

  void _setDrop(DropTarget? target) {
    if (_drop == target) return;
    setState(() => _drop = target);
  }

  void _closeTab(TabId id) {
    final take = widget.onCloseTab;
    if (take != null) {
      take(id);
    } else {
      controller.closeTab(id);
    }
  }

  void _endDrag() {
    if (_drop == null && _dragging == null) return;
    setState(() {
      _drop = null;
      _dragging = null;
    });
  }

  /// Why a pane's split control cannot act, or null.
  _SplitBlock? _splitBlock(PaneId paneId) {
    if (!controller.snapshot.canSplit) return _SplitBlock.budget;
    final size = _paneSizes[paneId];
    if (size == null) return null;
    // The strip's fixed part: paddings, the add control, the split control and
    // the embedder's chrome (taken as its 28px controls).
    final chrome = widget.chrome != null && paneId == topRightPaneId(layout)
        ? 36.0 + 28 * 2 + 8
        : 0.0;
    final add = (widget.canAddTab?.call(paneId) ?? true) ? 32.0 : 0.0;
    final fixed = widget.stripInlineStart + 6 + add + 32 + chrome;
    final fit = halvesFit(
      PaneMeasure(
        pane: DockRect(0, 0, size.width, size.height),
        strip: DockRect(0, 0, size.width, _stripHeight),
        chipsWidth: 0,
        fillWidth: size.width - fixed,
      ),
    );
    return fit.row ? null : _SplitBlock.width;
  }

  @override
  Widget build(BuildContext context) {
    final state = layout;
    final root = getNode(state, state.rootId);
    return _node(context, state, root);
  }

  Widget _node(BuildContext context, LayoutState state, LayoutNode node) =>
      switch (node) {
        PaneNode() => _PaneView(
          key: ValueKey(node.paneId),
          state: state,
          pane: node,
          host: this,
        ),
        SplitNode() => _SplitView(
          key: ValueKey(node.splitId),
          split: node,
          host: this,
          children: [
            for (final id in node.children)
              _node(context, state, getNode(state, id)),
          ],
        ),
      };
}

enum _SplitBlock { budget, width }

// ---------------------------------------------------------------------------
// Splits and dividers

class _SplitView extends StatefulWidget {
  const _SplitView({
    super.key,
    required this.split,
    required this.host,
    required this.children,
  });

  final SplitNode split;
  final _DockLayoutState host;
  final List<Widget> children;

  @override
  State<_SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<_SplitView> {
  List<double>? _preview;
  int? _active;
  double _extent = 1;

  List<double> get _sizes => _preview ?? widget.split.sizes;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final row = widget.split.axis == SplitAxis.row;
    return LayoutBuilder(
      builder: (context, constraints) {
        _extent = row ? constraints.maxWidth : constraints.maxHeight;
        final sizes = _sizes;
        final children = <Widget>[];
        final seams = <Widget>[];
        var offset = 0.0;
        for (var i = 0; i < widget.children.length; i++) {
          final extent = _extent * sizes[i];
          children.add(
            SizedBox(
              width: row ? extent : constraints.maxWidth,
              height: row ? constraints.maxHeight : extent,
              child: widget.children[i],
            ),
          );
          offset += extent;
          if (i < widget.children.length - 1) {
            final at = offset;
            final index = i;
            seams.add(
              Positioned(
                left: row ? at - 4 : 0,
                top: row ? 0 : at - 4,
                width: row ? 8 : constraints.maxWidth,
                height: row ? constraints.maxHeight : 8,
                child: MouseRegion(
                  cursor: row
                      ? SystemMouseCursors.resizeColumn
                      : SystemMouseCursors.resizeRow,
                  child: GestureDetector(
                    key: ValueKey('dock-divider-${widget.split.splitId}-$i'),
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: row ? (_) => _start(index) : null,
                    onHorizontalDragUpdate: row
                        ? (d) => _drag(index, d.delta.dx)
                        : null,
                    onHorizontalDragEnd: row ? (_) => _commit() : null,
                    onVerticalDragStart: row ? null : (_) => _start(index),
                    onVerticalDragUpdate: row
                        ? null
                        : (d) => _drag(index, d.delta.dy),
                    onVerticalDragEnd: row ? null : (_) => _commit(),
                    child: _Seam(
                      row: row,
                      active: _active == i,
                      color: theme.color('--dsw-alias-border-l4'),
                      grip: theme.color('--dsw-alias-label-caption'),
                    ),
                  ),
                ),
              ),
            );
          }
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            row ? Row(children: children) : Column(children: children),
            ...seams,
          ],
        );
      },
    );
  }

  void _start(int index) => setState(() {
    _active = index;
    _preview = [...widget.split.sizes];
  });

  void _drag(int index, double delta) {
    if (_extent <= 0) return;
    setState(() {
      _preview = clampSizes(
        dividerSizes(_sizes, index, delta / _extent),
        widget.host.widget.minPaneFraction,
      );
    });
  }

  void _commit() {
    final sizes = _preview;
    setState(() {
      _active = null;
      _preview = null;
    });
    if (sizes != null) {
      widget.host.controller.resizeSplit(widget.split.splitId, sizes);
    }
  }
}

/// The hairline on the seam, with the 1px grip that fades in on hover or drag.
class _Seam extends StatefulWidget {
  const _Seam({
    required this.row,
    required this.active,
    required this.color,
    required this.grip,
  });

  final bool row;
  final bool active;
  final Color color;
  final Color grip;

  @override
  State<_Seam> createState() => _SeamState();
}

class _SeamState extends State<_Seam> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: CustomPaint(
        painter: _SeamPainter(
          row: widget.row,
          color: widget.color,
          grip: widget.grip,
          gripVisible: _hover || widget.active,
          hairline: dshHairlineOf(context),
        ),
      ),
    );
  }
}

class _SeamPainter extends CustomPainter {
  _SeamPainter({
    required this.row,
    required this.color,
    required this.grip,
    required this.gripVisible,
    required this.hairline,
  });

  final bool row;
  final Color color;
  final Color grip;
  final bool gripVisible;
  final double hairline;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()..color = color;
    if (row) {
      canvas.drawRect(
        Rect.fromLTWH(cx - hairline / 2, 0, hairline, size.height),
        paint,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, cy - hairline / 2, size.width, hairline),
        paint,
      );
    }
    if (gripVisible) {
      final shader = ui.Gradient.linear(
        row ? Offset(cx, 0) : Offset(0, cy),
        row ? Offset(cx, size.height) : Offset(size.width, cy),
        [grip.withAlpha(0), grip, grip.withAlpha(0)],
        const [0, 0.5, 1],
      );
      final gripPaint = Paint()..shader = shader;
      canvas.drawRect(
        row
            ? Rect.fromLTWH(cx - 0.5, 0, 1, size.height)
            : Rect.fromLTWH(0, cy - 0.5, size.width, 1),
        gripPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_SeamPainter old) =>
      old.row != row ||
      old.color != color ||
      old.gripVisible != gripVisible ||
      old.hairline != hairline;
}

// ---------------------------------------------------------------------------
// One pane

class _PaneView extends StatelessWidget {
  const _PaneView({
    super.key,
    required this.state,
    required this.pane,
    required this.host,
  });

  final LayoutState state;
  final PaneNode pane;
  final _DockLayoutState host;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final widgetRef = host.widget;
    return LayoutBuilder(
      builder: (context, constraints) {
        host._paneSizes[pane.paneId] = constraints.biggest;
        final active = pane.activeTabId == null
            ? null
            : state.tabs[pane.activeTabId];
        return Semantics(
          container: true,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (host.layout.activePaneId != pane.paneId) {
                host.controller.focusPane(pane.paneId);
              }
            },
            child: ClipRect(
              child: ColoredBox(
                color: theme.bgBase,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TabStrip(state: state, pane: pane, host: host),
                    Expanded(
                      child: _PaneBody(
                        pane: pane,
                        host: host,
                        children: [
                          for (final id in pane.tabs)
                            if (state.tabs[id] case final tab?)
                              if (id == pane.activeTabId ||
                                  (widgetRef.keepMounted?.call(tab) ?? false))
                                Offstage(
                                  key: ValueKey('dock-body-$id'),
                                  offstage: id != pane.activeTabId,
                                  child: KeyedSubtree(
                                    key: host._keyFor(id),
                                    child: widgetRef.renderTab(context, tab),
                                  ),
                                ),
                        ],
                        empty: active == null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PaneBody extends StatelessWidget {
  const _PaneBody({
    required this.pane,
    required this.host,
    required this.children,
    required this.empty,
  });

  final PaneNode pane;
  final _DockLayoutState host;
  final List<Widget> children;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final labels = host.widget.labels;
    return DragTarget<TabId>(
      key: ValueKey('dock-body-target-${pane.paneId}'),
      onWillAcceptWithDetails: (details) => true,
      onMove: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(details.offset);
        final size = box.size;
        var zone = zoneInRect(
          DockRect(0, 0, size.width, size.height),
          local.dx,
          local.dy,
        );
        // An edge needs room for two working halves and a free pane budget.
        final split = zoneSplit(zone);
        if (split != null) {
          final block = host._splitBlock(pane.paneId);
          if (block != null && split.axis == SplitAxis.row) {
            zone = DockZone.center;
          }
          if (!host.controller.snapshot.canSplit) zone = DockZone.center;
        }
        host._setDrop(ZoneDrop(pane.paneId, zone));
      },
      onLeave: (_) => host._setDrop(null),
      onAcceptWithDetails: (details) {
        final target = host._drop;
        host._endDrag();
        if (target is ZoneDrop && target.paneId == pane.paneId) {
          host.controller.dropTab(details.data, pane.paneId, target.zone);
        }
      },
      builder: (context, candidate, rejected) {
        final target = host._drop;
        final zone = target is ZoneDrop && target.paneId == pane.paneId
            ? target.zone
            : null;
        return Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => host.widget.onFocusBody?.call(),
              child: empty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: DshChromeText(
                          labels.emptyPane,
                          style: theme
                              .textStyle('--dsw-font-xs-13')
                              .copyWith(
                                color: theme.color(
                                  '--dsw-alias-label-tertiary',
                                ),
                              ),
                        ),
                      ),
                    )
                  : Stack(fit: StackFit.expand, children: children),
            ),
            if (zone != null)
              _DropHints(
                zone: zone,
                labels: labels,
                horizontal: host.widget.horizontalDrops,
              ),
          ],
        );
      },
    );
  }
}

class _DropHints extends StatelessWidget {
  const _DropHints({
    required this.zone,
    required this.labels,
    required this.horizontal,
  });

  final DockZone zone;
  final DockLabels labels;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final scrim = theme.bgBase.withValues(alpha: 0.72);
    Widget card(DockZone z, bool active) => Padding(
      padding: const EdgeInsets.all(8),
      child: CustomPaint(
        painter: _DashedCard(
          color: active
              ? theme.color(
                  '--dsw-alias-brand-primary-new-colorprimary-new-color',
                )
              : theme.color('--dsw-alias-border-l4'),
          radius: theme.radiusMd,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DshIcon(
                switch (z) {
                  DockZone.center => DshShellIcons.dockZoneCenter,
                  DockZone.left => DshShellIcons.dockZoneLeft,
                  DockZone.right => DshShellIcons.dockZoneRight,
                  DockZone.top => DshShellIcons.dockZoneTop,
                  DockZone.bottom => DshShellIcons.dockZoneBottom,
                },
                size: 16,
                color: active
                    ? theme.color(
                        '--dsw-alias-brand-primary-new-colorprimary-new-color',
                      )
                    : theme.color('--dsw-alias-label-tertiary'),
              ),
              const SizedBox(height: 6),
              DshChromeText(
                labels.dropZone[z] ?? '',
                style: theme
                    .textStyle('--dsw-font-xs-13')
                    .copyWith(
                      color: active
                          ? theme.labelPrimary
                          : theme.color('--dsw-alias-label-tertiary'),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
    final halves = horizontal && zone != DockZone.center;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scrim),
          if (halves)
            Row(
              children: [
                Expanded(child: card(DockZone.left, zone == DockZone.left)),
                Expanded(child: card(DockZone.right, zone == DockZone.right)),
              ],
            )
          else
            LayoutBuilder(
              builder: (context, c) => switch (zone) {
                DockZone.center => card(zone, true),
                DockZone.left => Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: c.maxWidth * 0.4,
                    child: card(zone, true),
                  ),
                ),
                DockZone.right => Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: c.maxWidth * 0.4,
                    child: card(zone, true),
                  ),
                ),
                DockZone.top => Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: c.maxHeight * 0.4,
                    child: card(zone, true),
                  ),
                ),
                DockZone.bottom => Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: c.maxHeight * 0.4,
                    child: card(zone, true),
                  ),
                ),
              },
            ),
        ],
      ),
    );
  }
}

class _DashedCard extends CustomPainter {
  _DashedCard({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 4), paint);
        distance += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCard old) =>
      old.color != color || old.radius != radius;
}

// ---------------------------------------------------------------------------
// The tab strip

class _TabStrip extends StatefulWidget {
  const _TabStrip({
    required this.state,
    required this.pane,
    required this.host,
  });

  final LayoutState state;
  final PaneNode pane;
  final _DockLayoutState host;

  @override
  State<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<_TabStrip> {
  final Map<TabId, GlobalKey> _chipKeys = {};
  final ScrollController _scroll = ScrollController();
  _TabMenuState? _menu;

  GlobalKey _chipKey(TabId id) => _chipKeys.putIfAbsent(id, GlobalKey.new);

  @override
  void didUpdateWidget(_TabStrip old) {
    super.didUpdateWidget(old);
    final active = widget.pane.activeTabId;
    if (active != null && active != old.pane.activeTabId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _chipKeys[active]?.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 150),
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<DockRect> _chipRects() {
    final rects = <DockRect>[];
    for (final id in widget.pane.tabs) {
      final box = _chipKeys[id]?.currentContext?.findRenderObject();
      if (box is RenderBox && box.attached) {
        final o = box.localToGlobal(Offset.zero);
        rects.add(DockRect(o.dx, o.dy, box.size.width, box.size.height));
      }
    }
    return rects;
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final w = host.widget;
    final pane = widget.pane;
    final state = widget.state;
    final block = host._splitBlock(pane.paneId);
    final isChromePane =
        w.chrome != null && pane.paneId == topRightPaneId(state);
    final target = host._drop;
    final caret = target is StripDrop && target.paneId == pane.paneId
        ? target.index
        : null;

    final chips = <Widget>[];
    for (var i = 0; i < pane.tabs.length; i++) {
      final id = pane.tabs[i];
      final tab = state.tabs[id]!;
      final selected = id == pane.activeTabId;
      final closable = w.canCloseTab?.call(id) ?? true;
      final quiet = !closable && pane.tabs.length == 1;
      if (i > 0 || caret == i) {
        chips.add(_Slot(caret: caret == i, hidden: _slotHidden(pane, i)));
      }
      chips.add(
        _TabChip(
          key: _chipKey(id),
          tab: tab,
          selected: selected,
          closable: closable,
          quiet: quiet,
          dragging: host._dragging == id,
          host: host,
          onTap: () {
            if (state.activePaneId == pane.paneId && pane.activeTabId == id) {
              return;
            }
            host.controller.focusTab(id);
          },
          onClose: () => host._closeTab(id),
          onMenu: (anchor) => _openMenu(context, tab, anchor),
          onDragStarted: () => host.setState(() => host._dragging = id),
          onDragEnd: host._endDrag,
        ),
      );
    }
    if (caret == pane.tabs.length) {
      chips.add(const _Slot(caret: true, hidden: false));
    }

    final strip = DragTarget<TabId>(
      key: ValueKey('dock-strip-target-${pane.paneId}'),
      onWillAcceptWithDetails: (_) => true,
      onMove: (details) {
        final index = insertionIndex(_chipRects(), details.offset.dx);
        host._setDrop(StripDrop(pane.paneId, index));
      },
      onLeave: (_) => host._setDrop(null),
      onAcceptWithDetails: (details) {
        final dropped = host._drop;
        host._endDrag();
        if (dropped is StripDrop && dropped.paneId == pane.paneId) {
          host.controller.placeTab(details.data, pane.paneId, dropped.index);
        }
      },
      builder: (context, c, r) => SizedBox(
        height: _stripHeight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(w.stripInlineStart, 10, 6, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Row(
                    key: ValueKey('dock-strip-${pane.paneId}'),
                    children: chips,
                  ),
                ),
              ),
              if (w.canAddTab?.call(pane.paneId) ?? true) ...[
                const SizedBox(width: 4),
                _IconAction(
                  key: ValueKey('dock-add-${pane.paneId}'),
                  icon: DshShellIcons.plusOutline,
                  iconSize: 14,
                  label: w.labels.addTab,
                  onPressed: () => host.controller.addTab(pane.paneId),
                ),
              ],
              const Expanded(child: SizedBox.shrink()),
              if (!(w.hideSplitWhenBlocked && block != null)) ...[
                const SizedBox(width: 4),
                DshTooltip(
                  label: switch (block) {
                    null => w.labels.splitPane,
                    _SplitBlock.budget => w.labels.splitPaneDisabled,
                    _SplitBlock.width => w.labels.splitPaneNarrow,
                  },
                  shortcutKeys: block == null ? w.labels.splitPaneKeys : null,
                  side: DshTooltipSide.bottom,
                  delay: const Duration(milliseconds: 500),
                  child: _IconAction(
                    key: ValueKey('dock-split-${pane.paneId}'),
                    icon: DshShellIcons.dockSplit,
                    iconSize: 16,
                    label: w.labels.splitPane,
                    enabled: block == null,
                    onPressed: () => host.controller.splitPane(pane.paneId),
                  ),
                ),
              ],
              if (isChromePane) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: w.chrome!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [strip, if (_menu != null) const SizedBox.shrink()],
      ),
    );
  }

  /// The two slots beside the active chip draw no hairline.
  bool _slotHidden(PaneNode pane, int index) {
    final active = pane.activeTabId;
    return active != null &&
        (pane.tabs[index] == active || pane.tabs[index - 1] == active);
  }

  void _openMenu(BuildContext context, TabRecord tab, Rect anchor) {
    final host = widget.host;
    final w = host.widget;
    final closable = w.canCloseTab?.call(tab.id) ?? true;
    final entry = _TabMenuState();
    _menu = entry;
    late OverlayEntry overlay;
    void dismiss() {
      if (_menu == entry) _menu = null;
      overlay.remove();
    }

    final extras =
        w.renderTabMenuItems?.call(context, tab, dismiss) ?? const <Widget>[];
    if (!closable && extras.isEmpty) {
      _menu = null;
      return;
    }
    overlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: dismiss,
                onSecondaryTap: dismiss,
              ),
            ),
            Positioned(
              left: anchor.left,
              top: anchor.bottom + 4,
              child: _MenuSurface(
                children: [
                  if (closable)
                    _MenuItem(
                      key: ValueKey('dock-menu-close-${tab.id}'),
                      label: w.labels.closeTab,
                      onTap: () {
                        dismiss();
                        host._closeTab(tab.id);
                      },
                    ),
                  ...extras,
                ],
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(overlay);
  }
}

class _TabMenuState {}

class _MenuSurface extends StatelessWidget {
  const _MenuSurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshContainer(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-bg-layer-2'),
        borderRadius: BorderRadius.circular(theme.radiusMd),
        border: Border.all(
          color: theme.color('--dsw-alias-border-l2'),
          width: dshHairlineOf(context),
        ),
        boxShadow: theme.boxShadow('--dsw-elevation-prominent'),
      ),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: DshContainer(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: _hover ? theme.interactiveBgHover : null,
              borderRadius: BorderRadius.circular(theme.radiusMd),
            ),
            child: DshChromeText(
              widget.label,
              style: theme
                  .textStyle('--dsw-font-xs-13')
                  .copyWith(color: theme.labelPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// The slot between two chips: a 10px box with a hairline down its centre, or
/// the drop caret when a drag targets it.
class _Slot extends StatelessWidget {
  const _Slot({required this.caret, required this.hidden});

  final bool caret;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return SizedBox(
      width: 10,
      height: _chipHeight,
      child: Center(
        child: caret
            ? ColoredBox(
                key: const ValueKey('dock-caret'),
                color: theme.color(
                  '--dsw-alias-brand-primary-new-colorprimary-new-color',
                ),
                child: const SizedBox(width: 2, height: 20),
              )
            : hidden
            ? const SizedBox.shrink()
            : ColoredBox(
                color: theme.color('--dsw-alias-border-l4'),
                child: SizedBox(width: dshHairlineOf(context), height: 14),
              ),
      ),
    );
  }
}

class _IconAction extends StatefulWidget {
  const _IconAction({
    super.key,
    required this.icon,
    required this.iconSize,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final DshIconData icon;
  final double iconSize;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  State<_IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<_IconAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // A disabled control still takes the press: it never reaches the
          // pane's click-to-focus.
          onTap: widget.enabled ? widget.onPressed : () {},
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.4,
            child: DshContainer(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hover && widget.enabled
                    ? theme.interactiveBgHover
                    : null,
                borderRadius: BorderRadius.circular(theme.radiusSm),
              ),
              child: DshIcon(
                widget.icon,
                size: widget.iconSize,
                color: _hover && widget.enabled
                    ? theme.labelPrimary
                    : theme.labelSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({
    super.key,
    required this.tab,
    required this.selected,
    required this.closable,
    required this.quiet,
    required this.dragging,
    required this.host,
    required this.onTap,
    required this.onClose,
    required this.onMenu,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  final TabRecord tab;
  final bool selected;
  final bool closable;
  final bool quiet;
  final bool dragging;
  final _DockLayoutState host;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final void Function(Rect anchor) onMenu;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hover = false;
  bool _focus = false;

  Widget _chip(BuildContext context, {required bool feedback}) {
    final theme = context.dsh;
    final w = widget.host.widget;
    final selected = widget.selected;
    final showClose =
        widget.closable && !feedback && (selected || _hover || _focus);
    final ink = selected || widget.quiet
        ? theme.labelPrimary
        : theme.labelSecondary;
    final style = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(color: ink, height: 1.4);
    final title =
        w.renderTabTitle?.call(context, widget.tab) ??
        DshChromeText(
          widget.tab.title,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
        );
    final fill = widget.quiet
        ? null
        : selected
        ? theme.color('--dsw-alias-markdown-tag')
        : _hover
        ? theme.interactiveBgHover
        : null;
    Widget titleBox = DefaultTextStyle(
      style: style,
      child: IconTheme(
        data: IconThemeData(color: ink),
        child: ClipRect(child: title),
      ),
    );
    // The title fades out under the close control.
    titleBox = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => ui.Gradient.linear(
        Offset(rect.left, 0),
        Offset(rect.right, 0),
        [theme.bgBase, theme.bgBase, theme.bgBase.withAlpha(0)],
        [
          0,
          (rect.width - (showClose ? 30 : 16)).clamp(0, rect.width) /
              rect.width,
          ((rect.width - (showClose ? 14 : 0)) / rect.width).clamp(0, 1),
        ],
      ),
      child: titleBox,
    );
    return Opacity(
      opacity: widget.dragging && !feedback ? 0.5 : 1,
      child: DshContainer(
        height: _chipHeight,
        constraints: const BoxConstraints(
          minWidth: _chipMin,
          maxWidth: _chipMax,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(theme.radiusSm),
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: titleBox,
              ),
            ),
            if (showClose)
              Positioned(
                top: 4,
                right: 4,
                child: DshTooltip(
                  label: w.labels.closeTab,
                  shortcutKeys: w.labels.closeTabKeys,
                  side: DshTooltipSide.bottom,
                  delay: const Duration(milliseconds: 500),
                  child: _CloseButton(
                    key: ValueKey('dock-close-${widget.tab.id}'),
                    label: w.labels.closeTab,
                    onPressed: widget.onClose,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chip = Focus(
      onFocusChange: (f) => setState(() => _focus = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: widget.quiet
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Semantics(
          selected: widget.selected,
          button: true,
          label: widget.tab.title,
          child: GestureDetector(
            key: ValueKey('dock-chip-${widget.tab.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onSecondaryTapDown: (details) {
              final box = context.findRenderObject() as RenderBox;
              final origin = box.localToGlobal(Offset.zero);
              widget.onMenu(origin & box.size);
            },
            child: _chip(context, feedback: false),
          ),
        ),
      ),
    );
    if (widget.quiet) return chip;
    return Draggable<TabId>(
      data: widget.tab.id,
      maxSimultaneousDrags: 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: widget.onDragStarted,
      onDragEnd: (_) => widget.onDragEnd(),
      onDraggableCanceled: (_, _) => widget.onDragEnd(),
      feedback: IgnorePointer(child: _chip(context, feedback: true)),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _chip(context, feedback: false),
      ),
      child: chip,
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: DshContainer(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? theme.interactiveBgHover : null,
              borderRadius: BorderRadius.circular(theme.radiusSm),
            ),
            child: DshIcon(
              DshIcons.closeFill,
              size: 14,
              color: _hover
                  ? theme.labelPrimary
                  : theme.color('--dsw-alias-label-tertiary'),
            ),
          ),
        ),
      ),
    );
  }
}
