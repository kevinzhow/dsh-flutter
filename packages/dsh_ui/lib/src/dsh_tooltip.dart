import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_menu_follower.dart';
import 'dsh_recipes.g.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// Where the bubble sits relative to its anchor.
enum DshTooltipSide { right, bottom, top }

/// Horizontal alignment of top and bottom bubbles.
enum DshTooltipAlign { center, end }

/// A source-styled tooltip for a hoverable or keyboard-focused anchor.
class DshTooltip extends StatefulWidget {
  const DshTooltip({
    super.key,
    required this.label,
    this.shortcutKeys,
    this.side = DshTooltipSide.right,
    this.align = DshTooltipAlign.center,
    this.delay = Duration.zero,
    this.focusDelay = Duration.zero,
    this.gap = DshTooltipRecipe.defaultGap,
    this.maxWidth,
    this.disabled = false,
    this.openOnClick = false,
    required this.child,
  });

  final String label;
  final List<String>? shortcutKeys;
  final DshTooltipSide side;
  final DshTooltipAlign align;
  final Duration delay, focusDelay;
  final double gap;
  final double? maxWidth;
  final bool disabled, openOnClick;
  final Widget child;

  @override
  State<DshTooltip> createState() => _DshTooltipState();
}

class _TooltipScope extends InheritedWidget {
  const _TooltipScope({required this.suppress, required super.child});
  final ValueChanged<bool> suppress;
  static ValueChanged<bool>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TooltipScope>()?.suppress;
  @override
  bool updateShouldNotify(_TooltipScope old) => suppress != old.suppress;
}

// The source tooltip follows the last pointer-down or key-down, including
// mouse clicks. Flutter's focus highlight mode also treats a mouse as
// traditional, so it cannot distinguish a mouse-driven refocus from Tab.
class _TooltipInputModality {
  static int _users = 0;
  static bool pointer = false;

  static void acquire() {
    if (_users++ != 0) return;
    pointer = false;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  static void release() {
    if (--_users != 0) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  static void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) pointer = true;
  }

  static bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) pointer = false;
    return false;
  }
}

class _DshTooltipState extends State<DshTooltip> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final Object _tapGroup = Object();
  final GlobalKey _anchorKey = GlobalKey();
  Timer? _timer;
  ValueChanged<bool>? _suppressAncestor;
  bool _hover = false, _focus = false, _pinned = false, _suppressed = false;
  bool _containsFocus = false;
  bool _keyHandlerActive = false;
  int? _pressedPointer;

  @override
  void initState() {
    super.initState();
    _TooltipInputModality.acquire();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _suppressAncestor = _TooltipScope.maybeOf(context);
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _schedule(Duration delay) {
    _cancel();
    if (widget.disabled) return;
    if (delay == Duration.zero) {
      _show();
    } else {
      _timer = Timer(delay, _show);
    }
  }

  void _show() {
    if (!mounted || widget.disabled || (!_hover && !_focus && !_pinned)) return;
    if (!_portal.isShowing) _portal.show();
    _syncKeyHandler();
    _suppressAncestor?.call(true);
  }

  void _syncKeyHandler() {
    final needed =
        !widget.disabled &&
        (_containsFocus || (widget.openOnClick && _portal.isShowing));
    if (needed == _keyHandlerActive) return;
    if (needed) {
      HardwareKeyboard.instance.addHandler(_onKey);
    } else {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    _keyHandlerActive = needed;
  }

  void _withdraw() {
    if (_portal.isShowing) _portal.hide();
    _pinned = false;
    _syncKeyHandler();
    _suppressAncestor?.call(false);
  }

  void _dismiss() {
    _cancel();
    _hover = false;
    _focus = false;
    _pressedPointer = null;
    _withdraw();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (widget.openOnClick &&
        _portal.isShowing &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _dismiss();
      return true;
    }
    if (widget.openOnClick &&
        _portal.isShowing &&
        event.logicalKey == LogicalKeyboardKey.tab) {
      _dismiss();
    } else if (_containsFocus &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      _activate();
    }
    return false;
  }

  void _activate() {
    _cancel();
    _focus = false;
    if (widget.openOnClick && !widget.disabled && !_pinned) {
      setState(() => _pinned = true);
      _show();
    } else {
      _withdraw();
    }
  }

  void _setSuppressed(bool value) {
    if (_suppressed != value && mounted) setState(() => _suppressed = value);
  }

  @override
  void didUpdateWidget(DshTooltip old) {
    super.didUpdateWidget(old);
    if (widget.disabled || (!widget.openOnClick && _pinned)) {
      _cancel();
      _hover = false;
      _focus = false;
      _pressedPointer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (widget.disabled || (!widget.openOnClick && _pinned))) {
          _withdraw();
        }
      });
    }
    _syncKeyHandler();
  }

  @override
  void dispose() {
    _cancel();
    if (_keyHandlerActive) HardwareKeyboard.instance.removeHandler(_onKey);
    if (_portal.isShowing) _suppressAncestor?.call(false);
    _TooltipInputModality.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _TooltipScope(
      suppress: _setSuppressed,
      child: TapRegion(
        groupId: _tapGroup,
        onTapOutside: (_) {
          if (widget.openOnClick && _portal.isShowing) _dismiss();
        },
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => _suppressed
              ? const SizedBox.shrink()
              : _TooltipFollower(
                  link: _link,
                  side: widget.side,
                  align: widget.align,
                  gap: widget.gap,
                  maxWidth: widget.maxWidth,
                  horizontalPadding:
                      widget.label.isEmpty &&
                          (widget.shortcutKeys?.isNotEmpty ?? false)
                      ? 2 * DshTooltipRecipe.shortcutOnlyPadding
                      : DshTooltipRecipe.paddingHorizontal +
                            ((widget.shortcutKeys?.isNotEmpty ?? false)
                                ? DshTooltipRecipe.shortcutEndPadding
                                : DshTooltipRecipe.paddingHorizontal),
                  child: TapRegion(
                    groupId: _tapGroup,
                    child: IgnorePointer(
                      ignoring: !_pinned,
                      child: _Bubble(
                        label: widget.label,
                        keys: widget.shortcutKeys,
                      ),
                    ),
                  ),
                ),
          child: CompositedTransformTarget(
            link: _link,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (focused) {
                _containsFocus = focused;
                if (focused && !_TooltipInputModality.pointer) {
                  _focus = true;
                  _syncKeyHandler();
                  _schedule(widget.focusDelay);
                } else if (!focused) {
                  _focus = false;
                  if (!_hover && !_pinned) {
                    _cancel();
                    _withdraw();
                  }
                  _syncKeyHandler();
                }
              },
              child: MouseRegion(
                onEnter: (_) {
                  _hover = true;
                  _schedule(widget.delay);
                },
                onExit: (_) {
                  _hover = false;
                  _cancel();
                  if (!_pinned) _withdraw();
                },
                child: Listener(
                  key: _anchorKey,
                  onPointerDown: (event) {
                    if (!widget.disabled &&
                        event.buttons == kPrimaryButton &&
                        _pressedPointer == null) {
                      _pressedPointer = event.pointer;
                    }
                  },
                  onPointerCancel: (event) {
                    if (_pressedPointer == event.pointer) {
                      _pressedPointer = null;
                    }
                  },
                  onPointerUp: (event) {
                    if (_pressedPointer != event.pointer) return;
                    _pressedPointer = null;
                    final box = _anchorKey.currentContext?.findRenderObject();
                    if (box is RenderBox &&
                        (Offset.zero & box.size).contains(
                          event.localPosition,
                        )) {
                      _activate();
                    }
                  },
                  child: Semantics(
                    tooltip: [
                      if (widget.label.isNotEmpty) widget.label,
                      if (widget.shortcutKeys?.isNotEmpty ?? false)
                        widget.shortcutKeys!.join(' '),
                    ].join(' '),
                    child: widget.child,
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.label, required this.keys});
  final String label;
  final List<String>? keys;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final hasKeys = keys?.isNotEmpty ?? false;
    final onlyKeys = label.isEmpty && hasKeys;
    final text = theme
        .textStyle(DshTooltipRecipe.fontToken)
        .copyWith(
          color: theme.color(DshTooltipRecipe.labelToken),
          height: DshTooltipRecipe.lineHeight / DshTooltipRecipe.fontSize,
        );
    final bubble = DshContainer(
      key: const ValueKey('dsh-tooltip-bubble'),
      padding: onlyKeys
          ? const EdgeInsets.all(DshTooltipRecipe.shortcutOnlyPadding)
          : EdgeInsets.fromLTRB(
              DshTooltipRecipe.paddingHorizontal,
              DshTooltipRecipe.paddingVertical,
              hasKeys
                  ? DshTooltipRecipe.shortcutEndPadding
                  : DshTooltipRecipe.paddingHorizontal,
              DshTooltipRecipe.paddingVertical,
            ),
      decoration: theme.cornerDecoration(
        theme.number(DshTooltipRecipe.radiusToken),
        color: theme.color(DshTooltipRecipe.fillToken),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty)
            Flexible(child: DshChromeText(label, style: text)),
          if (label.isNotEmpty && hasKeys)
            const SizedBox(width: DshTooltipRecipe.gap),
          if (hasKeys) DshShortcutKeys(keys: keys!, tooltip: true),
        ],
      ),
    );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: DshTooltipRecipe.animationMs.round());
    final easing = theme.strings[DshTooltipRecipe.easingToken] ?? '';
    final numbers = RegExp(
      r'^cubic-bezier\(\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^\)]+)\s*\)$',
    ).firstMatch(easing);
    final values = numbers == null
        ? null
        : [for (var i = 1; i <= 4; i++) double.tryParse(numbers[i]!.trim())];
    final curve = values != null && values.every((v) => v != null)
        ? Cubic(values[0]!, values[1]!, values[2]!, values[3]!)
        : Curves.linear;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: curve,
      builder: (_, opacity, child) => Opacity(opacity: opacity, child: child),
      child: bubble,
    );
  }
}

class _TooltipFollower extends StatefulWidget {
  const _TooltipFollower({
    required this.link,
    required this.side,
    required this.align,
    required this.gap,
    required this.maxWidth,
    required this.horizontalPadding,
    required this.child,
  });
  final LayerLink link;
  final DshTooltipSide side;
  final DshTooltipAlign align;
  final double gap;
  final double? maxWidth;
  final double horizontalPadding;
  final Widget child;
  @override
  State<_TooltipFollower> createState() => _TooltipFollowerState();
}

class _TooltipFollowerState extends State<_TooltipFollower>
    with WidgetsBindingObserver {
  final _root = GlobalKey(), _probe = GlobalKey();
  Rect? _anchor;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _measure(Duration _) {
    if (!mounted) return;
    final root = _root.currentContext?.findRenderObject();
    final probe = _probe.currentContext?.findRenderObject();
    final size = widget.link.leaderSize;
    final anchor =
        widget.link.leader == null ||
            size == null ||
            root is! RenderBox ||
            probe is! RenderBox
        ? null
        : MatrixUtils.transformRect(
            probe.getTransformTo(root),
            Offset.zero & size,
          );
    if (_anchor != anchor) setState(() => _anchor = anchor);
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    key: _root,
    child: Stack(
      children: [
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          child: SizedBox.shrink(key: _probe),
        ),
        if (_anchor case final Rect anchor)
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _TooltipPlacement(
                anchor: anchor,
                side: widget.side,
                align: widget.align,
                gap: widget.gap,
                maxWidth: widget.maxWidth,
                horizontalPadding: widget.horizontalPadding,
                safeInsets: dshMenuSafeInsetsOf(context),
              ),
              child: widget.child,
            ),
          ),
      ],
    ),
  );
}

class _TooltipPlacement extends SingleChildLayoutDelegate {
  const _TooltipPlacement({
    required this.anchor,
    required this.side,
    required this.align,
    required this.gap,
    required this.maxWidth,
    required this.horizontalPadding,
    required this.safeInsets,
  });
  final Rect anchor;
  final DshTooltipSide side;
  final DshTooltipAlign align;
  final double gap;
  final double? maxWidth;
  final double horizontalPadding;
  final EdgeInsets safeInsets;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = math.max(
      0.0,
      constraints.maxWidth -
          safeInsets.horizontal -
          2 * DshTooltipRecipe.viewportMargin,
    );
    // CSS max-width constrains the content box; padding is added afterward.
    final cap =
        (maxWidth ??
            constraints.maxWidth * DshTooltipRecipe.maxViewportFraction) +
        horizontalPadding;
    return BoxConstraints(maxWidth: math.min(available, cap));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final margin = DshTooltipRecipe.viewportMargin;
    final minX = safeInsets.left + margin;
    final maxX = math.max(
      minX,
      size.width - safeInsets.right - margin - childSize.width,
    );
    final rawX = side == DshTooltipSide.right
        ? anchor.right + DshTooltipRecipe.rightGap
        : align == DshTooltipAlign.end
        ? anchor.right - childSize.width
        : anchor.center.dx - childSize.width / 2;
    final x = rawX.clamp(minX, maxX);
    if (side == DshTooltipSide.right) {
      return Offset(x, anchor.center.dy - childSize.height / 2);
    }
    final fitsBelow =
        anchor.bottom + gap + childSize.height <=
        size.height - safeInsets.bottom - margin;
    final fitsAbove =
        anchor.top - gap - childSize.height >= safeInsets.top + margin;
    final above = side == DshTooltipSide.bottom
        ? !fitsBelow && fitsAbove
        : fitsAbove || !fitsBelow;
    return Offset(
      x,
      above ? anchor.top - gap - childSize.height : anchor.bottom + gap,
    );
  }

  @override
  bool shouldRelayout(_TooltipPlacement old) =>
      anchor != old.anchor ||
      side != old.side ||
      align != old.align ||
      gap != old.gap ||
      maxWidth != old.maxWidth ||
      horizontalPadding != old.horizontalPadding ||
      safeInsets != old.safeInsets;
}

/// One command's keycaps (dsh `ShortcutKeys`): the key labels in a row, `+`
/// separators drawn as plain text. [tooltip] draws the boxed variant used inside
/// a tooltip bubble; otherwise the keys are unboxed tertiary text.
class DshShortcutKeys extends StatelessWidget {
  const DshShortcutKeys({
    super.key,
    required this.keys,
    this.tooltip = false,
    this.menu = false,
    this.color,
  }) : assert(!tooltip || !menu);

  final List<String> keys;
  final bool tooltip;

  /// The published Menu shortcut typography and caption color.
  final bool menu;

  /// Text colour override; defaults to the tertiary label (plain) or the
  /// tooltip's own text.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final joined = tooltip && keys.contains('+');
    final ink =
        color ??
        (tooltip
            ? theme.color(DshTooltipRecipe.labelToken)
            : theme.color(
                menu
                    ? DshMenuRecipe.shortcutColorToken
                    : DshShortcutKeysRecipe.plainColorToken,
              ));
    final size = tooltip
        ? DshShortcutKeysRecipe.tooltipFontSize
        : menu
        ? DshMenuRecipe.shortcutFontSize
        : DshShortcutKeysRecipe.plainFontSize;
    final line = tooltip
        ? DshShortcutKeysRecipe.tooltipLineHeight
        : menu
        ? DshMenuRecipe.shortcutLineHeight
        : DshShortcutKeysRecipe.plainLineHeight;
    final style = theme
        .textStyle(
          tooltip
              ? DshShortcutKeysRecipe.tooltipFontToken
              : menu
              ? DshMenuRecipe.shortcutFontToken
              : DshShortcutKeysRecipe.plainFontToken,
        )
        .copyWith(color: ink, height: line / size);
    Widget key(String k) => DshChromeText(k, style: style, maxLines: 1);
    Widget cap(
      Widget child, {
      double minWidth = DshShortcutKeysRecipe.keyMinWidth,
    }) => DshContainer(
      constraints: BoxConstraints(
        minWidth: minWidth,
        minHeight: DshShortcutKeysRecipe.keyHeight,
        maxHeight: DshShortcutKeysRecipe.keyHeight,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: DshShortcutKeysRecipe.keyPadding,
      ),
      alignment: Alignment.center,
      decoration: theme.cornerDecoration(
        DshShortcutKeysRecipe.keyRadius,
        color: theme.color(DshShortcutKeysRecipe.keyFillToken),
      ),
      child: child,
    );
    final gap = SizedBox(
      width: tooltip
          ? DshShortcutKeysRecipe.tooltipGap
          : DshShortcutKeysRecipe.plainGap,
    );
    if (joined) {
      return DshContainer(
        constraints: const BoxConstraints(
          minHeight: DshShortcutKeysRecipe.keyHeight,
          maxHeight: DshShortcutKeysRecipe.keyHeight,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DshShortcutKeysRecipe.joinedPadding,
        ),
        alignment: Alignment.center,
        decoration: theme.cornerDecoration(
          DshShortcutKeysRecipe.keyRadius,
          color: theme.color(DshShortcutKeysRecipe.keyFillToken),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < keys.length; i++) ...[
              if (i > 0) gap,
              key(keys[i]),
            ],
          ],
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) gap,
          tooltip ? cap(key(keys[i])) : key(keys[i]),
        ],
      ],
    );
  }
}
