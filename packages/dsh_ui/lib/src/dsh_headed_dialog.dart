import 'dart:math' as math;

import 'package:flutter/material.dart'
    show Scrollbar, ScrollbarTheme, ScrollbarThemeData;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'dsh_button.dart';
import 'dsh_focus_presentation.dart';
import 'dsh_icon.dart';
import 'dsh_icons.g.dart';
import 'dsh_pixel_snap.dart';
import 'dsh_recipes.g.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// The headed content profile of the source Modal. The caller owns the frame
/// and route; this widget owns their header, optional body and footer layout.
class DshHeadedDialogContent extends StatefulWidget {
  const DshHeadedDialogContent({
    super.key,
    required this.title,
    required this.closeLabel,
    required this.onClose,
    this.description,
    this.body,
    this.footer,
    this.scrollContent = false,
    this.closeAutofocus = false,
    this.closeKey,
    this.headerKey,
    this.bodyKey,
    this.contentKey,
    this.footerKey,
  });

  final String title, closeLabel;
  final VoidCallback onClose;
  final String? description;
  final Widget? body;
  final List<Widget>? footer;

  /// Scroll the entire content block, including the header. The footer stays
  /// outside the scrolling region, as in RiskConfirmation.
  final bool scrollContent;

  /// Explicitly choose Close as the automatic focus target. Callers with a
  /// preferred body control can leave this false and autofocus that control.
  final bool closeAutofocus;
  final Key? closeKey, headerKey, bodyKey, contentKey, footerKey;

  @override
  State<DshHeadedDialogContent> createState() => _DshHeadedDialogContentState();
}

class _DshHeadedDialogContentState extends State<DshHeadedDialogContent> {
  final closeFocus = FocusNode(debugLabel: 'headed dialog close');
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    closeFocus.addListener(_closeFocusChanged);
    if (widget.closeAutofocus) _autofocus();
  }

  void _closeFocusChanged() {
    if (closeFocus.hasPrimaryFocus &&
        widget.scrollContent &&
        scroll.hasClients) {
      // Browser focus returns this header control to the top edge; revealing
      // only the button would leave the header's top padding scrolled away.
      scroll.jumpTo(scroll.position.minScrollExtent);
    }
  }

  @override
  void didUpdateWidget(DshHeadedDialogContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.closeAutofocus && !oldWidget.closeAutofocus) _autofocus();
  }

  void _autofocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.closeAutofocus &&
          ModalRoute.of(context)?.isCurrent != false) {
        dshFocusWithoutRing(closeFocus);
      }
    });
  }

  @override
  void dispose() {
    closeFocus.removeListener(_closeFocusChanged);
    closeFocus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final titleStyle = theme
        .fixedTextStyle(
          size: DshModalRecipe.titleFontSize,
          line: DshModalRecipe.titleLineHeight,
          weight: DshModalRecipe.titleWeight.round(),
        )
        .copyWith(color: theme.color(DshModalRecipe.titleLabelToken));
    final descriptionStyle = theme
        .fixedTextStyle(
          size: DshModalRecipe.descriptionFontSize,
          line: DshModalRecipe.descriptionLineHeight,
          weight: DshModalRecipe.descriptionWeight.round(),
        )
        .copyWith(color: theme.color(DshModalRecipe.descriptionLabelToken));
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: widget.headerKey,
          padding: const EdgeInsets.fromLTRB(
            DshModalRecipe.headerLeft,
            DshModalRecipe.headerTop,
            DshModalRecipe.headerRight,
            DshModalRecipe.headerBottom,
          ),
          child: Row(
            children: [
              Expanded(child: DshChromeText(widget.title, style: titleStyle)),
              const SizedBox(width: DshModalRecipe.headerGap),
              SizedBox(
                width: DshModalRecipe.closeSize,
                child: DshButton(
                  key: widget.closeKey,
                  focusNode: closeFocus,
                  height: DshModalRecipe.closeSize,
                  horizontalPadding:
                      (DshModalRecipe.closeSize -
                          DshModalRecipe.closeIconSize) /
                      2,
                  radius: theme.number(DshModalRecipe.closeRadiusToken),
                  semanticLabel: widget.closeLabel,
                  onPressed: widget.onClose,
                  child: DshIcon(
                    DshIcons.close,
                    size: DshModalRecipe.closeIconSize,
                    color: theme.color(DshModalRecipe.closeLabelToken),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.description case final description?
            when description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DshModalRecipe.descriptionHorizontalPadding,
            ),
            child: DshChromeText(description, style: descriptionStyle),
          ),
        if (widget.body case final body?)
          Padding(
            padding: const EdgeInsets.only(top: DshModalRecipe.bodyMarginTop),
            child: Padding(
              key: widget.bodyKey,
              padding: const EdgeInsets.symmetric(
                horizontal: DshModalRecipe.bodyHorizontalPadding,
              ),
              child: body,
            ),
          ),
      ],
    );
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: ClipRect(
        child: _HeadedLayout(
          gap: widget.footer == null ? 0 : DshModalRecipe.gap,
          content: ClipRect(
            key: widget.contentKey,
            child: widget.scrollContent
                ? _scrollingContent(context, content)
                : OverflowBox(
                    alignment: Alignment.topLeft,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    fit: OverflowBoxFit.deferToChild,
                    child: content,
                  ),
          ),
          footer: Padding(
            padding: const EdgeInsets.only(
              bottom: DshModalRecipe.paddingBottom,
            ),
            child: widget.footer == null
                ? const SizedBox.shrink()
                : Padding(
                    key: widget.footerKey,
                    padding: const EdgeInsets.symmetric(
                      horizontal: DshModalRecipe.footerHorizontalPadding,
                    ),
                    child: _HeadedFooter(
                      gap: DshModalRecipe.footerGap,
                      children: widget.footer!,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _scrollingContent(BuildContext context, Widget content) {
    final theme = context.dsh;
    final gutter = dshBorderWidthOf(context, DshScrollbarRecipe.width);
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(scrollbars: false, overscroll: false),
      child: PrimaryScrollController(
        controller: scroll,
        child: ScrollbarTheme(
          data: ScrollbarThemeData(
            thickness: WidgetStatePropertyAll(gutter),
            radius: const Radius.circular(DshScrollbarRecipe.radius),
            crossAxisMargin: DshScrollbarRecipe.thumbBorderWidth,
            mainAxisMargin: DshScrollbarRecipe.trackMargin,
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => theme.color(
                states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.dragged)
                    ? DshScrollbarRecipe.hoverToken
                    : DshScrollbarRecipe.thumbToken,
              ),
            ),
          ),
          child: Scrollbar(
            controller: scroll,
            thumbVisibility: true,
            child: _ScrollbarViewport(
              controller: scroll,
              gutter: gutter,
              child: SingleChildScrollView(
                controller: scroll,
                primary: false,
                physics: const ClampingScrollPhysics(),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keep natural action widths while they fit, then shrink toward min-content
/// widths, including explicit caller minima. Risk's one-word Cancel freezes
/// at its minimum and Confirm receives the remaining width, as in the source.
/// Arbitrary children use outer natural widths as shrink weights: if several
/// shrink together this approximates CSS, whose weights exclude box padding.
class _HeadedFooter extends MultiChildRenderObjectWidget {
  const _HeadedFooter({required this.gap, required super.children});
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeadedFooter(gap);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderHeadedFooter renderObject,
  ) {
    renderObject.gap = gap;
  }
}

class _RenderHeadedFooter extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeadedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeadedParentData> {
  _RenderHeadedFooter(this._gap);
  double _gap;

  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeadedParentData) {
      child.parentData = _HeadedParentData();
    }
  }

  List<RenderBox> get _children => [
    for (var child = firstChild; child != null; child = childAfter(child))
      child,
  ];

  double get _spacing => math.max(0, childCount - 1) * _gap;

  List<double> _widths(
    BoxConstraints constraints,
    List<RenderBox> children,
    List<Size> natural,
  ) {
    final widths = natural.map((size) => size.width).toList();
    if (!constraints.hasBoundedWidth ||
        widths.fold(0.0, (sum, width) => sum + width) + _spacing <=
            constraints.maxWidth) {
      return widths;
    }
    final minima = [
      for (var i = 0; i < children.length; i++)
        math.min(
          widths[i],
          children[i].getMinIntrinsicWidth(constraints.maxHeight),
        ),
    ];
    final flexible = {for (var i = 0; i < children.length; i++) i};
    while (flexible.isNotEmpty) {
      final deficit =
          widths.fold(0.0, (sum, width) => sum + width) +
          _spacing -
          constraints.maxWidth;
      if (deficit <= 0) break;
      final weight = flexible.fold(
        0.0,
        (sum, index) => sum + natural[index].width,
      );
      if (weight <= 0) break;
      final frozen = <int>[];
      for (final index in flexible) {
        final target = widths[index] - deficit * natural[index].width / weight;
        if (target < minima[index]) {
          widths[index] = minima[index];
          frozen.add(index);
        }
      }
      if (frozen.isEmpty) {
        for (final index in flexible) {
          widths[index] -= deficit * natural[index].width / weight;
        }
        break;
      }
      flexible.removeAll(frozen);
    }
    return widths;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _children.fold(
        0.0,
        (sum, child) => sum + child.getMinIntrinsicWidth(height),
      ) +
      _spacing;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _children.fold(
        0.0,
        (sum, child) => sum + child.getMaxIntrinsicWidth(height),
      ) +
      _spacing;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final children = _children;
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    final natural = [for (final child in children) child.getDryLayout(loose)];
    final widths = _widths(constraints, children, natural);
    var height = 0.0;
    for (var i = 0; i < children.length; i++) {
      height = math.max(
        height,
        children[i].getDryLayout(loose.tighten(width: widths[i])).height,
      );
    }
    return constraints.constrain(
      Size(widths.fold(0.0, (sum, width) => sum + width) + _spacing, height),
    );
  }

  @override
  void performLayout() {
    final children = _children;
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    for (final child in children) {
      child.layout(loose, parentUsesSize: true);
    }
    final widths = _widths(constraints, children, [
      for (final child in children) child.size,
    ]);
    var height = 0.0;
    for (var i = 0; i < children.length; i++) {
      children[i].layout(loose.tighten(width: widths[i]), parentUsesSize: true);
      height = math.max(height, children[i].size.height);
    }
    final totalWidth = widths.fold(0.0, (sum, width) => sum + width) + _spacing;
    size = constraints.constrain(Size(totalWidth, height));
    var left = size.width - totalWidth;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      (child.parentData! as _HeadedParentData).offset = Offset(
        left,
        (size.height - child.size.height) / 2,
      );
      left += widths[i] + _gap;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// CSS overflow:auto reserves its scrollbar only when the full-width content
/// overflows. Measure that width first on every layout so resizing cannot keep
/// a gutter that would itself cause unnecessary wrapping and overflow.
class _ScrollbarViewport extends SingleChildRenderObjectWidget {
  const _ScrollbarViewport({
    required this.controller,
    required this.gutter,
    required super.child,
  });
  final ScrollController controller;
  final double gutter;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollbarViewport(controller, gutter);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderScrollbarViewport renderObject,
  ) {
    renderObject.update(controller, gutter);
  }
}

class _RenderScrollbarViewport extends RenderProxyBox {
  _RenderScrollbarViewport(this._controller, this._gutter);
  ScrollController _controller;
  double _gutter;

  void update(ScrollController controller, double gutter) {
    if (identical(controller, _controller) && gutter == _gutter) return;
    _controller = controller;
    _gutter = gutter;
    markNeedsLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      child!.getDryLayout(constraints);

  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    final width = child!.size.width;
    if (_controller.hasClients &&
        _controller.position.hasContentDimensions &&
        _controller.position.maxScrollExtent > 0) {
      child!.layout(
        constraints.copyWith(
          minWidth: math.max(0, constraints.minWidth - _gutter),
          maxWidth: math.max(0, constraints.maxWidth - _gutter),
        ),
        parentUsesSize: true,
      );
    }
    size = constraints.constrain(Size(width, child!.size.height));
  }
}

/// Measure the footer first, then give the content the remaining height.
/// Unlike a Flex this also permits a viewport shorter than its fixed footer:
/// content collapses to zero and the surrounding clip handles that case.
class _HeadedLayout extends MultiChildRenderObjectWidget {
  _HeadedLayout({
    required this.gap,
    required Widget content,
    required Widget footer,
  }) : super(children: [content, footer]);

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeadedLayout(gap);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderHeadedLayout renderObject,
  ) {
    renderObject.gap = gap;
  }
}

class _HeadedParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeadedLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeadedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeadedParentData> {
  _RenderHeadedLayout(this._gap);
  double _gap;

  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeadedParentData) {
      child.parentData = _HeadedParentData();
    }
  }

  double _width(BoxConstraints constraints) => constraints.hasBoundedWidth
      ? constraints.maxWidth
      : constraints.constrainWidth(
          math.max(
            firstChild!.getMaxIntrinsicWidth(double.infinity),
            lastChild!.getMaxIntrinsicWidth(double.infinity),
          ),
        );

  double _available(BoxConstraints constraints, double footerHeight) =>
      math.max(0, constraints.maxHeight - footerHeight);

  BoxConstraints _contentConstraints(
    BoxConstraints constraints,
    double width,
    double footerHeight,
  ) => BoxConstraints(
    minWidth: width,
    maxWidth: width,
    maxHeight: math.max(0, _available(constraints, footerHeight) - _gap),
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = _width(constraints);
    final footer = lastChild!.getDryLayout(
      BoxConstraints.tightFor(width: width),
    );
    final content = firstChild!.getDryLayout(
      _contentConstraints(constraints, width, footer.height),
    );
    return constraints.constrain(
      Size(width, content.height + _gap + footer.height),
    );
  }

  @override
  void performLayout() {
    final width = _width(constraints);
    final footer = lastChild!;
    footer.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    final content = firstChild!;
    content.layout(
      _contentConstraints(constraints, width, footer.size.height),
      parentUsesSize: true,
    );
    final footerTop = content.size.height + _gap;
    (content.parentData! as _HeadedParentData).offset = Offset.zero;
    (footer.parentData! as _HeadedParentData).offset = Offset(0, footerTop);
    size = constraints.constrain(Size(width, footerTop + footer.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
