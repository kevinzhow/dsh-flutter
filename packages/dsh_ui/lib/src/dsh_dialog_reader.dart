import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart'
    show Scrollbar, ScrollbarTheme, ScrollbarThemeData;
import 'package:flutter/widgets.dart';

import 'dsh_button.dart';
import 'dsh_icon.dart';
import 'dsh_pixel_snap.dart';
import 'dsh_presentation.dart';
import 'dsh_recipes.g.dart';
import 'dsh_segmented_tabs.dart';
import 'dsh_icons.g.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

class DshReaderTab {
  const DshReaderTab(
    this.value,
    this.label, {
    required this.child,
    this.tabKey,
    this.panelKey,
  });
  final String value, label;
  final Widget child;
  final Key? tabKey, panelKey;
}

/// Source preset-reader profile over the canonical Modal layer. Features
/// provide content and names; this profile owns geometry and panel lifetime.
Future<T?> showDshReaderDialog<T>(
  BuildContext context, {
  required String title,
  required String intro,
  required String closeLabel,
  required String tabsLabel,
  required String identifier,
  required List<DshReaderTab> tabs,
  required String initialValue,
  bool initialHighlight = false,
  FocusNode? restoreFocus,
  Key? readerKey,
  Key? tabsKey,
  Key? closeKey,
}) => showDshDialog<T>(
  context,
  width: DshGuideReaderRecipe.width,
  height: DshGuideReaderRecipe.height,
  label: title,
  restoreFocus: restoreFocus,
  builder: (context) => DshDialogReader(
    key: readerKey,
    title: title,
    intro: intro,
    closeLabel: closeLabel,
    tabsLabel: tabsLabel,
    identifier: identifier,
    tabs: tabs,
    initialValue: initialValue,
    initialHighlight: initialHighlight,
    tabsKey: tabsKey,
    closeKey: closeKey,
    onClose: () => Navigator.of(context).pop(),
  ),
);

class DshDialogReader extends StatefulWidget {
  const DshDialogReader({
    super.key,
    required this.title,
    required this.intro,
    required this.closeLabel,
    required this.tabsLabel,
    required this.identifier,
    required this.tabs,
    required this.initialValue,
    required this.onClose,
    this.initialHighlight = false,
    this.tabsKey,
    this.closeKey,
  }) : assert(tabs.length > 0);
  final String title, intro, closeLabel, tabsLabel, identifier, initialValue;
  final List<DshReaderTab> tabs;
  final bool initialHighlight;
  final VoidCallback onClose;
  final Key? tabsKey, closeKey;
  @override
  State<DshDialogReader> createState() => _DshDialogReaderState();
}

class _DshDialogReaderState extends State<DshDialogReader> {
  late String value = widget.initialValue;
  final controllers = <String, ScrollController>{};
  final nodes = <String, FocusNode>{};
  final highlighted = <String>{};

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    for (final node in nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _panel(DshReaderTab tab) {
    final theme = context.dsh;
    final selected = tab.value == value;
    final gutter = dshBorderWidthOf(
      context,
      DshGuideReaderRecipe.scrollbarWidth,
    );
    final controller = controllers.putIfAbsent(tab.value, ScrollController.new);
    final node = nodes.putIfAbsent(tab.value, FocusNode.new);
    final ring = highlighted.contains(tab.value);
    final color =
        theme.colors[DshGuideReaderRecipe.panelFocusToken] ??
        theme.color(DshGuideReaderRecipe.panelFocusFallbackToken);
    final focusWidth = theme.number(DshGuideReaderRecipe.panelFocusWidthToken);
    return Offstage(
      offstage: !selected,
      child: TickerMode(
        enabled: selected,
        child: ExcludeFocus(
          excluding: !selected,
          child: Semantics(
            key: tab.panelKey,
            container: true,
            explicitChildNodes: true,
            identifier: '${widget.identifier}-panel-${tab.value}',
            role: SemanticsRole.tabPanel,
            label: tab.label,
            child: PrimaryScrollController(
              controller: controller,
              child: FocusableActionDetector(
                focusNode: node,
                onShowFocusHighlight: (show) => setState(() {
                  if (show) {
                    highlighted.add(tab.value);
                  } else {
                    highlighted.remove(tab.value);
                  }
                }),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    border: ring
                        ? Border.all(color: color, width: focusWidth)
                        : null,
                  ),
                  child: ScrollbarTheme(
                    data: ScrollbarThemeData(
                      thickness: WidgetStatePropertyAll(gutter),
                      radius: Radius.circular(
                        DshGuideReaderRecipe.scrollbarRadius,
                      ),
                      crossAxisMargin:
                          DshGuideReaderRecipe.scrollbarThumbBorderWidth,
                      mainAxisMargin: DshGuideReaderRecipe.scrollbarTrackMargin,
                      thumbColor: WidgetStateProperty.resolveWith(
                        (states) => theme.color(
                          states.contains(WidgetState.hovered) ||
                                  states.contains(WidgetState.dragged)
                              ? DshGuideReaderRecipe.scrollbarHoverToken
                              : DshGuideReaderRecipe.scrollbarThumbToken,
                        ),
                      ),
                    ),
                    child: Scrollbar(
                      controller: controller,
                      thumbVisibility: true,
                      child: Padding(
                        padding: EdgeInsets.only(right: gutter),
                        child: SingleChildScrollView(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(
                            DshGuideReaderRecipe.panelLeft,
                            DshGuideReaderRecipe.panelTop,
                            DshGuideReaderRecipe.panelRight,
                            DshGuideReaderRecipe.panelBottom,
                          ),
                          child: DefaultTextStyle(
                            style: theme
                                .textStyle(DshGuideReaderRecipe.panelFontToken)
                                .copyWith(
                                  color: theme.color(
                                    DshGuideReaderRecipe.panelLabelToken,
                                  ),
                                ),
                            child: tab.child,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final titleStyle = theme
        .textStyle(DshGuideReaderRecipe.titleFontToken)
        .copyWith(
          fontWeight:
              FontWeight.values[DshGuideReaderRecipe.titleWeight ~/ 100 - 1],
          height:
              DshGuideReaderRecipe.titleLineHeight /
              DshGuideReaderRecipe.titleFontSize,
          color: theme.labelPrimary,
        );
    final introStyle = theme
        .textStyle(DshGuideReaderRecipe.introFontToken)
        .copyWith(
          height:
              DshGuideReaderRecipe.introLineHeight /
              DshGuideReaderRecipe.introFontSize,
          color: theme.color(DshGuideReaderRecipe.introLabelToken),
        );
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: CustomMultiChildLayout(
        delegate: _ReaderLayout(),
        children: [
          LayoutId(
            id: _ReaderSlot.header,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DshGuideReaderRecipe.headerLeft,
                DshGuideReaderRecipe.headerTop,
                DshGuideReaderRecipe.headerRight,
                DshGuideReaderRecipe.headerBottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DshChromeText(widget.title, style: titleStyle),
                      ),
                      const SizedBox(width: DshGuideReaderRecipe.titleGap),
                      SizedBox(
                        width: DshGuideReaderRecipe.closeSize,
                        child: DshButton(
                          key: widget.closeKey,
                          height: DshGuideReaderRecipe.closeSize,
                          horizontalPadding: DshGuideReaderRecipe.closePadding,
                          radius: theme.number(
                            DshGuideReaderRecipe.closeRadiusToken,
                          ),
                          semanticLabel: widget.closeLabel,
                          onPressed: widget.onClose,
                          child: DshIcon(
                            DshIcons.close,
                            size: DshGuideReaderRecipe.closeIconSize,
                            color: theme.color(
                              DshGuideReaderRecipe.closeLabelToken,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DshGuideReaderRecipe.introGap),
                  DshChromeText(widget.intro, style: introStyle),
                ],
              ),
            ),
          ),
          LayoutId(
            id: _ReaderSlot.tabs,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DshGuideReaderRecipe.tabsHorizontalMargin,
                DshGuideReaderRecipe.tabsTopMargin,
                DshGuideReaderRecipe.tabsHorizontalMargin,
                DshGuideReaderRecipe.tabsBottomMargin,
              ),
              child: DshSegmentedTabs(
                key: widget.tabsKey,
                items: [
                  for (final tab in widget.tabs)
                    DshSegmentedTab(
                      tab.value,
                      tab.label,
                      key: tab.tabKey,
                      id: '${widget.identifier}-tab-${tab.value}',
                      panelId: '${widget.identifier}-panel-${tab.value}',
                    ),
                ],
                value: value,
                label: widget.tabsLabel,
                expand: true,
                autofocus: true,
                autofocusHighlight: widget.initialHighlight,
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
          LayoutId(
            id: _ReaderSlot.panels,
            child: Stack(
              fit: StackFit.expand,
              children: [for (final tab in widget.tabs) _panel(tab)],
            ),
          ),
        ],
      ),
    );
  }
}

enum _ReaderSlot { header, tabs, panels }

class _ReaderLayout extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final width = BoxConstraints.tightFor(width: size.width);
    final header = layoutChild(_ReaderSlot.header, width);
    final tabs = layoutChild(_ReaderSlot.tabs, width);
    positionChild(_ReaderSlot.header, Offset.zero);
    positionChild(_ReaderSlot.tabs, Offset(0, header.height));
    final top = header.height + tabs.height;
    layoutChild(
      _ReaderSlot.panels,
      BoxConstraints.tight(Size(size.width, math.max(0, size.height - top))),
    );
    positionChild(_ReaderSlot.panels, Offset(0, top));
  }

  @override
  bool shouldRelayout(_ReaderLayout oldDelegate) => false;
}
