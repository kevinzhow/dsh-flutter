import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dsh_pixel_snap.dart';
import 'dsh_snapped_box.dart';
import 'theme_access.dart';

class DshSegmentedTab {
  const DshSegmentedTab(this.value, this.label);
  final String value, label;
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
  }) : assert(items.length > 0);
  final List<DshSegmentedTab> items;
  final String value, label;
  final ValueChanged<String> onChanged;
  final double minWidth;
  @override
  State<DshSegmentedTabs> createState() => _DshSegmentedTabsState();
}

class _DshSegmentedTabsState extends State<DshSegmentedTabs> {
  final nodes = <FocusNode>[];
  int? focusIndex, hoverIndex;
  int get selected => math.max(
    0,
    widget.items.indexWhere((item) => item.value == widget.value),
  );
  @override
  void initState() {
    super.initState();
    _nodes();
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
    for (final node in nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void select(int index) {
    widget.onChanged(widget.items[index].value);
    nodes[index].requestFocus();
  }

  KeyEventResult key(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final focused = nodes.indexWhere((node) => node.hasFocus),
        current = focused < 0 ? selected : focused;
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
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.label,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(widget.minWidth + 8, constraints.maxWidth);
          return SizedBox(
            width: width,
            height: 42,
            child: DshContainer(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.color('--dsw-alias-bg-module-platform'),
                borderRadius: BorderRadius.circular(theme.radiusLg),
              ),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (_, event) => key(event),
                child: Stack(
                  children: [
                    Positioned(
                      left: (width - 8) / widget.items.length * selected,
                      top: 0,
                      bottom: 0,
                      width: (width - 8) / widget.items.length,
                      child: IgnorePointer(
                        child: DshContainer(
                          decoration: BoxDecoration(
                            color: theme.color('--dsw-alias-bg-layer-3'),
                            border: Border.all(
                              color: theme.borderL3,
                              width: dshHairlineOf(context),
                            ),
                            borderRadius: BorderRadius.circular(theme.radiusMd),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: i == selected,
                              label: widget.items[i].label,
                              excludeSemantics: true,
                              onTap: () => select(i),
                              child: FocusableActionDetector(
                                focusNode: nodes[i],
                                mouseCursor: SystemMouseCursors.click,
                                onShowFocusHighlight: (on) {
                                  if (mounted) {
                                    setState(
                                      () => focusIndex = on
                                          ? i
                                          : (focusIndex == i
                                                ? null
                                                : focusIndex),
                                    );
                                  }
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
                                    onTap: () => select(i),
                                    child: Center(
                                      child: Text(
                                        widget.items[i].label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme
                                            .textStyle('--dsw-font-s-14')
                                            .copyWith(
                                              height: 20 / 14,
                                              fontWeight: i == selected
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color:
                                                  i == selected ||
                                                      i == hoverIndex
                                                  ? theme.labelPrimary
                                                  : theme.labelSecondary,
                                              decoration: focusIndex == i
                                                  ? TextDecoration.underline
                                                  : TextDecoration.none,
                                              decorationThickness: 1,
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
