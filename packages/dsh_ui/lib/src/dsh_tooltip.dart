import 'dart:async';

import 'package:flutter/widgets.dart';

import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// Where the bubble sits relative to its anchor (dsh `Tooltip` `side`).
enum DshTooltipSide { right, bottom, top }

/// A hover and focus tooltip (dsh `ui-primitives` `Tooltip`): a dark bubble
/// (`--dsw-alias-tooltip-bg`) with 13px text, 3px by 7px padding and the small
/// radius, placed [gap] px from the anchor and flipped to the other side when it
/// does not fit. [label] may be empty when only [shortcutKeys] are shown.
class DshTooltip extends StatefulWidget {
  const DshTooltip({
    super.key,
    required this.label,
    this.shortcutKeys,
    this.side = DshTooltipSide.right,
    this.delay = Duration.zero,
    this.gap = 8,
    this.disabled = false,
    required this.child,
  });

  final String label;

  /// Effective key labels rendered as tooltip keycaps after the text.
  final List<String>? shortcutKeys;
  final DshTooltipSide side;
  final Duration delay;
  final double gap;
  final bool disabled;
  final Widget child;

  @override
  State<DshTooltip> createState() => _DshTooltipState();
}

class _DshTooltipState extends State<DshTooltip> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  Timer? _timer;
  bool _hover = false;

  void _enter() {
    _hover = true;
    _timer?.cancel();
    if (widget.disabled) return;
    if (widget.delay == Duration.zero) {
      _show();
    } else {
      _timer = Timer(widget.delay, _show);
    }
  }

  void _show() {
    if (!mounted || !_hover || widget.disabled) return;
    if (!_portal.isShowing) _portal.show();
  }

  void _exit() {
    _hover = false;
    _timer?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  @override
  void didUpdateWidget(DshTooltip old) {
    super.didUpdateWidget(old);
    if (widget.disabled && _portal.isShowing) _portal.hide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.label.isEmpty && (widget.shortcutKeys?.isEmpty ?? true)) {
      return widget.child;
    }
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => _Bubble(
        link: _link,
        label: widget.label,
        keys: widget.shortcutKeys,
        side: widget.side,
        gap: widget.gap,
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: (_) => _enter(),
          onExit: (_) => _exit(),
          child: Listener(onPointerDown: (_) => _exit(), child: widget.child),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.link,
    required this.label,
    required this.keys,
    required this.side,
    required this.gap,
  });

  final LayerLink link;
  final String label;
  final List<String>? keys;
  final DshTooltipSide side;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final screen = MediaQuery.sizeOf(context);
    final text = theme
        .textStyle('--dsw-font-xs-13')
        .copyWith(
          color: theme.color('--dsw-static-neutral-bluish-00'),
          height: 20 / 13,
        );
    final bubble = DshContainer(
      constraints: BoxConstraints(maxWidth: screen.width / 2),
      padding: EdgeInsets.fromLTRB(
        7,
        3,
        keys != null && keys!.isNotEmpty ? 5 : 7,
        3,
      ),
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-tooltip-bg'),
        borderRadius: BorderRadius.circular(theme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty)
            Flexible(child: DshChromeText(label, style: text)),
          if (label.isNotEmpty && keys != null && keys!.isNotEmpty)
            const SizedBox(width: 8),
          if (keys != null && keys!.isNotEmpty)
            DshShortcutKeys(keys: keys!, tooltip: true),
        ],
      ),
    );
    final (targetAnchor, followerAnchor, offset) = switch (side) {
      DshTooltipSide.right => (
        Alignment.centerRight,
        Alignment.centerLeft,
        Offset(gap, 0),
      ),
      DshTooltipSide.bottom => (
        Alignment.bottomCenter,
        Alignment.topCenter,
        Offset(0, gap),
      ),
      DshTooltipSide.top => (
        Alignment.topCenter,
        Alignment.bottomCenter,
        Offset(0, -gap),
      ),
    };
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          targetAnchor: targetAnchor,
          followerAnchor: followerAnchor,
          offset: offset,
          child: bubble,
        ),
      ),
    );
  }
}

/// One command's keycaps (dsh `ShortcutKeys`): the key labels in a row, `+`
/// separators drawn as plain text. [tooltip] draws the boxed variant used inside
/// a tooltip bubble; otherwise the keys are unboxed tertiary text.
class DshShortcutKeys extends StatelessWidget {
  const DshShortcutKeys({
    super.key,
    required this.keys,
    this.tooltip = false,
    this.color,
  });

  final List<String> keys;
  final bool tooltip;

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
            ? theme.color('--dsw-static-neutral-bluish-00')
            : theme.color('--dsw-alias-label-tertiary'));
    final style = theme
        .textStyle(tooltip ? '--dsw-font-xxxs-11' : '--dsw-font-xxs-12')
        .copyWith(
          color: ink,
          height: (tooltip ? 14 : 16) / (tooltip ? 11 : 12),
        );
    Widget key(String k) => DshChromeText(k, style: style, maxLines: 1);
    Widget cap(Widget child, {double minWidth = 16}) => DshContainer(
      constraints: BoxConstraints(
        minWidth: minWidth,
        minHeight: 16,
        maxHeight: 16,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-tooltip-key-bg'),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
    final gap = SizedBox(width: tooltip ? 2 : 3);
    if (joined) {
      return DshContainer(
        constraints: const BoxConstraints(minHeight: 16, maxHeight: 16),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.color('--dsw-alias-tooltip-key-bg'),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [for (final k in keys) key(k)],
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
