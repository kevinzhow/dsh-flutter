import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// dsh `formatMessageClock` (`ui-chat` `message-chrome.ts`): `HH:mm` on the
/// same calendar day, else the `clock.md` (this year) or `clock.ymd` template
/// followed by the clock.
String formatMessageClock(num timeMs, DshI18n i18n, {DateTime? now}) {
  final d = DateTime.fromMillisecondsSinceEpoch(timeMs.toInt());
  final n = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final clock = '${two(d.hour)}:${two(d.minute)}';
  if (d.year == n.year && d.month == n.month && d.day == n.day) return clock;
  final params = <String, Object?>{'y': d.year, 'm': d.month, 'd': d.day};
  final date = d.year == n.year
      ? i18n.t('chat', 'clock.md', params: params)
      : i18n.t('chat', 'clock.ymd', params: params);
  return '$date $clock';
}

/// Whether a pointer that can hover is there: dsh's `@media (hover: hover)`
/// (`MessageIconActions.module.css`), which is about the input device, not the
/// width of the window. Desktop platforms always count; elsewhere a connected
/// mouse does (a tablet with a mouse hovers, a phone does not).
mixin HoverCapable<T extends StatefulWidget> on State<T> {
  MouseTracker get _tracker => RendererBinding.instance.mouseTracker;

  bool get hoverCapable =>
      switch (defaultTargetPlatform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => true,
        _ => false,
      } ||
      _tracker.mouseIsConnected;

  void _mouseChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tracker.addListener(_mouseChanged);
  }

  @override
  void dispose() {
    _tracker.removeListener(_mouseChanged);
    super.dispose();
  }
}

/// The icon actions row of a message (dsh `MessageIconActions`): the clock,
/// and the copy action that swaps to a check for a second. On pointer
/// platforms an earlier message reveals the row on hover or focus (dsh's
/// `@media (hover: hover)` rule); on touch platforms, like dsh's devices
/// without hover, it is always there (raft-flutter turns hover chrome off
/// for a coarse pointer the same way, `RaftMessageRow.coarsePointer`).
class MessageActions extends StatefulWidget {
  const MessageActions({
    super.key,
    required this.text,
    required this.i18n,
    this.time,
    this.clockFirst = true,
    this.revealed = true,
    this.touchTarget,
  });

  /// What the copy action writes.
  final String text;
  final num? time;
  final DshI18n i18n;

  /// Clock before the icons (user rows) or after (assistant rows).
  final bool clockFirst;

  /// Whether the row shows (see [HoverReveal]); touch platforms ignore it.
  final bool revealed;

  /// The copy control's touch area (44px) instead of dsh's 28px; by default on
  /// where nothing can hover. Off for the parity captures.
  final bool? touchTarget;

  @override
  State<MessageActions> createState() => _MessageActionsState();
}

class _MessageActionsState extends State<MessageActions>
    with DshCopyFeedback, HoverCapable {
  bool _focused = false;
  bool get _big => widget.touchTarget ?? !hoverCapable;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final secondary = theme.color('--dsw-alias-label-secondary');
    final label = widget.i18n.t('common', copied ? 'copied' : 'copy');
    final time = widget.time;
    final clock = time == null
        ? null
        : DshChromeText(
            formatMessageClock(time, widget.i18n),
            key: const ValueKey('message-clock'),
            // `.timeStart` 13px; the assistant tail's `.timeEnd` is a pixel smaller.
            style: theme
                .textStyle(
                  widget.clockFirst ? '--dsw-font-xs-13' : '--dsw-font-xxs-12',
                )
                .copyWith(color: tertiary),
          );
    final copy = Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: () => copyText(widget.text),
      child: Focus(
        onFocusChange: (v) => setState(() => _focused = v),
        child: GestureDetector(
          key: const ValueKey('message-copy'),
          behavior: HitTestBehavior.opaque,
          onTap: () => copyText(widget.text),
          // 28px visual (dsh), grown to the 44px touch target on phones.
          // The glyph stays flush with the row's edge (the clock side is the
          // inner one); the extra touch area grows inward.
          child: SizedBox.square(
            dimension: _big ? DshSpace.touch : 28,
            child: Align(
              alignment: !_big
                  ? Alignment.center
                  : widget.clockFirst
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: DshIcon(
                copied ? DshIcons.check : DshIcons.copy,
                // `.action svg` 15px; 17px on the assistant tail.
                size: widget.clockFirst ? 15 : 17,
                color: copied ? secondary : tertiary,
              ),
            ),
          ),
        ),
      ),
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // `.actions { gap: 8px }`; the user clock has `padding-right: 12px`.
        if (widget.clockFirst && clock != null) ...[
          Padding(padding: const EdgeInsets.only(right: 12), child: clock),
          const SizedBox(width: 8),
        ],
        copy,
        // The assistant tail: the gap plus `.endInfo`'s own 8px margin.
        if (!widget.clockFirst && clock != null)
          Padding(padding: const EdgeInsets.only(left: 16), child: clock),
      ],
    );
    if (!hoverCapable) return row;
    return AnimatedOpacity(
      opacity: widget.revealed || _focused ? 1 : 0,
      duration: const Duration(milliseconds: 80),
      child: row,
    );
  }
}

/// Tracks the pointer over a whole message so its [MessageActions] can show
/// on hover. With [always] (the newest rows) or on a touch platform the
/// actions are simply there.
class HoverReveal extends StatefulWidget {
  const HoverReveal({super.key, required this.builder, this.always = false});

  final Widget Function(BuildContext context, bool revealed) builder;
  final bool always;

  @override
  State<HoverReveal> createState() => _HoverRevealState();
}

class _HoverRevealState extends State<HoverReveal> with HoverCapable {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.always || !hoverCapable) {
      return widget.builder(context, true);
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}
