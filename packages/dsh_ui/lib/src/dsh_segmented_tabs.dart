import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dsh_control_focus_modality.dart';
import 'dsh_pixel_snap.dart';
import 'dsh_recipes.g.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

class DshSegmentedTab {
  const DshSegmentedTab(
    this.value,
    this.label, {
    this.key,
    this.id,
    this.panelId,
  });
  final String value, label;
  final Key? key;
  final String? id, panelId;
}

/// Controlled equal-width tabs from ui-primitives/SegmentedTabs. Only the
/// selected tab is a tab stop; arrows and Home/End move selection and focus.
class DshSegmentedTabs extends StatefulWidget {
  const DshSegmentedTabs({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    required this.label,
    this.minWidth = 240,
    this.expand = false,
    this.autofocus = false,
  }) : assert(items.length > 0);
  final List<DshSegmentedTab> items;
  final String value, label;
  final ValueChanged<String> onChanged;
  final double minWidth;

  /// Fill the caller's available width, as the preset guide's tab row does.
  final bool expand;

  /// Initially focus the selected tab, as the preset guide does on opening.
  final bool autofocus;
  @override
  State<DshSegmentedTabs> createState() => _DshSegmentedTabsState();
}

class _DshSegmentedTabsState extends State<DshSegmentedTabs> {
  final modality = DshControlFocusModality.instance;
  final nodes = <FocusNode>[];
  int? focusIndex, hoverIndex;
  int? _pointerTarget;
  int get selected => math.max(
    0,
    widget.items.indexWhere((item) => item.value == widget.value),
  );
  @override
  void initState() {
    super.initState();
    modality.acquire(_refresh);
    _nodes();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(DshSegmentedTabs old) {
    super.didUpdateWidget(old);
    _nodes();
  }

  void _nodes() {
    while (nodes.length > widget.items.length) {
      nodes.removeLast().dispose();
    }
    while (nodes.length < widget.items.length) {
      nodes.add(FocusNode());
    }
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].skipTraversal = i != selected;
    }
  }

  @override
  void dispose() {
    modality.release(_refresh);
    for (final node in nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _focus(int index) {
    _pointerTarget = null;
    focusIndex = index;
    nodes[index].requestFocus();
    _refresh();
  }

  void select(int index, {bool pointer = false}) {
    // Native :focus-visible preserves an existing keyboard underline when
    // clicking the same focused tab, but a newly pointer-focused tab has none.
    if (pointer) {
      focusIndex = nodes[index].hasFocus && focusIndex == index ? index : null;
      _pointerTarget = index;
    } else {
      focusIndex = index;
      _pointerTarget = null;
    }
    widget.onChanged(widget.items[index].value);
    nodes[index].requestFocus();
    _refresh();
  }

  KeyEventResult key(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final focused = nodes.indexWhere((node) => node.hasFocus),
        current = focused < 0 ? selected : focused;
    if (focused >= 0) {
      _pointerTarget = null;
      setState(() => focusIndex = focused);
    }
    final next = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft =>
        (current + nodes.length - 1) % nodes.length,
      LogicalKeyboardKey.arrowRight => (current + 1) % nodes.length,
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => nodes.length - 1,
      _ => null,
    };
    if (next == null) return KeyEventResult.ignored;
    select(next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: DshSegmentedTabRecipe.transitionMs.round());
    final labelDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(
            milliseconds: DshSegmentedTabRecipe.labelTransitionMs.round(),
          );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: SemanticsRole.tabBar,
      label: widget.label,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final intrinsicMinimum =
              widget.minWidth + 2 * DshSegmentedTabRecipe.padding;
          final width = widget.expand && constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : math.min(intrinsicMinimum, constraints.maxWidth);
          return SizedBox(
            width: width,
            height:
                DshSegmentedTabRecipe.height +
                2 * DshSegmentedTabRecipe.padding,
            child: DshContainer(
              padding: const EdgeInsets.all(DshSegmentedTabRecipe.padding),
              decoration: BoxDecoration(
                color: theme.color(DshSegmentedTabRecipe.backgroundToken),
                borderRadius: BorderRadius.circular(
                  theme.number(DshSegmentedTabRecipe.radiusToken),
                ),
              ),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                includeSemantics: false,
                onKeyEvent: (_, event) => key(event),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width:
                          (width - 2 * DshSegmentedTabRecipe.padding) /
                          widget.items.length,
                      child: AnimatedSlide(
                        offset: Offset(selected.toDouble(), 0),
                        duration: duration,
                        curve: Curves.ease,
                        child: IgnorePointer(
                          child: DshContainer(
                            decoration: BoxDecoration(
                              color: theme.color(
                                DshSegmentedTabRecipe.indicatorBackgroundToken,
                              ),
                              border: Border.all(
                                color: theme.color(
                                  DshSegmentedTabRecipe.outlineToken,
                                ),
                                width: dshBorderWidthOf(
                                  context,
                                  DshSegmentedTabRecipe.outlineWidth,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(
                                theme.number(
                                  DshSegmentedTabRecipe.indicatorRadiusToken,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          Expanded(
                            child: Semantics(
                              key: widget.items[i].key,
                              container: true,
                              role: SemanticsRole.tab,
                              identifier: widget.items[i].id,
                              controlsNodes: widget.items[i].panelId == null
                                  ? null
                                  : {widget.items[i].panelId!},
                              selected: i == selected,
                              focused: nodes[i].hasFocus,
                              focusable: true,
                              label: widget.items[i].label,
                              excludeSemantics: true,
                              onTap: () => select(i),
                              onFocus: () => _focus(i),
                              child: FocusableActionDetector(
                                focusNode: nodes[i],
                                autofocus: widget.autofocus && i == selected,
                                mouseCursor: SystemMouseCursors.click,
                                onFocusChange: (focused) {
                                  if (focused && _pointerTarget == i) {
                                    _pointerTarget = null;
                                  } else if (focused &&
                                      !modality.pointerOwnsFocus &&
                                      FocusManager.instance.highlightMode ==
                                          FocusHighlightMode.traditional) {
                                    focusIndex = i;
                                  } else if (!focused && focusIndex == i) {
                                    focusIndex = null;
                                  }
                                  _refresh();
                                },
                                shortcuts: const {
                                  SingleActivator(LogicalKeyboardKey.enter):
                                      ActivateIntent(),
                                  SingleActivator(LogicalKeyboardKey.space):
                                      ActivateIntent(),
                                },
                                actions: {
                                  ActivateIntent:
                                      CallbackAction<ActivateIntent>(
                                        onInvoke: (_) {
                                          select(i);
                                          return null;
                                        },
                                      ),
                                },
                                child: MouseRegion(
                                  onEnter: (_) =>
                                      setState(() => hoverIndex = i),
                                  onExit: (_) =>
                                      setState(() => hoverIndex = null),
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => select(i, pointer: true),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal:
                                            DshSegmentedTabRecipe.labelPadding,
                                      ),
                                      child: Center(
                                        child: TweenAnimationBuilder<Color?>(
                                          tween: ColorTween(
                                            end: theme.color(
                                              i == selected || i == hoverIndex
                                                  ? DshSegmentedTabRecipe
                                                        .activeLabelToken
                                                  : DshSegmentedTabRecipe
                                                        .labelToken,
                                            ),
                                          ),
                                          duration: labelDuration,
                                          curve: Curves.ease,
                                          builder: (context, color, _) => _TabLabel(
                                            widget.items[i].label,
                                            underline: focusIndex == i,
                                            style: theme
                                                .textStyle('--dsw-font-s-14')
                                                .copyWith(
                                                  height:
                                                      DshSegmentedTabRecipe
                                                          .lineHeight /
                                                      DshSegmentedTabRecipe
                                                          .fontSize,
                                                  fontWeight: i == selected
                                                      ? FontWeight
                                                            .values[DshSegmentedTabRecipe
                                                                    .selectedWeight ~/
                                                                100 -
                                                            1]
                                                      : FontWeight.w400,
                                                  color: color,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// TextStyle has no CSS text-underline-offset counterpart. Paint the source
// underline relative to the same laid-out text's alphabetic baseline.
class _TabLabel extends StatelessWidget {
  const _TabLabel(this.label, {required this.style, required this.underline});
  final String label;
  final TextStyle style;
  final bool underline;

  @override
  Widget build(BuildContext context) => DshChromeBaseline(
    style: style,
    child: CustomPaint(
      foregroundPainter: underline
          ? _TabUnderline(
              label,
              style,
              Directionality.of(context),
              MediaQuery.textScalerOf(context),
              dshSnapDensity(dshDevicePixelRatioOf(context)),
            )
          : null,
      child: Text(
        label,
        style: style,
        strutStyle: dshStrut(style),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

class _TabUnderline extends CustomPainter {
  const _TabUnderline(
    this.label,
    this.style,
    this.direction,
    this.scaler,
    this.density,
  );
  final String label;
  final TextStyle style;
  final TextDirection direction;
  final TextScaler scaler;
  final double density;

  @override
  void paint(Canvas canvas, Size size) {
    final text = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
      textScaler: scaler,
      strutStyle: dshStrut(style),
      maxLines: 1,
      ellipsis: '\u2026',
    )..layout(maxWidth: size.width);
    final y =
        text
            .computeDistanceToActualBaseline(TextBaseline.alphabetic)
            .roundToDouble() +
        (DshSegmentedTabRecipe.focusLineOffset * density).round() / density;
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        y,
        text.width,
        math.max(1, (DshSegmentedTabRecipe.focusLineWidth * density).round()) /
            density,
      ),
      Paint()..color = style.color!,
    );
    text.dispose();
  }

  @override
  bool shouldRepaint(_TabUnderline old) =>
      old.label != label ||
      old.style != style ||
      old.direction != direction ||
      old.scaler != scaler ||
      old.density != density;
}
