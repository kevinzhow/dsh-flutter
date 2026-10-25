import 'dart:async';
import 'dart:math' as math;

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class WorkspaceHoverGroup {
  VoidCallback? close;
  bool blocked = false;
}

/// Desktop row previews share an 800ms initial dwell, keep pointer grace over
/// the gap/card, suppress under menus, and copy only their documented value.
class WorkspaceHoverCard extends StatefulWidget {
  const WorkspaceHoverCard({
    super.key,
    required this.child,
    required this.content,
    required this.group,
    required this.copiedLabel,
    this.copyText,
    this.disabled = false,
  });
  final Widget child;
  final WidgetBuilder content;
  final WorkspaceHoverGroup group;
  final String? copyText;
  final String copiedLabel;
  final bool disabled;
  @override
  State<WorkspaceHoverCard> createState() => _WorkspaceHoverCardState();
}

class _WorkspaceHoverCardState extends State<WorkspaceHoverCard> {
  final portal = OverlayPortalController();
  Timer? timer, copiedTimer;
  bool copied = false;
  void close() {
    timer?.cancel();
    copiedTimer?.cancel();
    copied = false;
    if (portal.isShowing) portal.hide();
    if (widget.group.close == close) widget.group.close = null;
  }

  void enter() {
    timer?.cancel();
    if (widget.disabled || widget.group.blocked) return;
    final previous = widget.group.close;
    timer = Timer(Duration(milliseconds: previous == null ? 800 : 0), () {
      if (!mounted || widget.disabled || widget.group.blocked) return;
      previous?.call();
      widget.group.close = close;
      portal.show();
    });
  }

  void leave() {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 200), close);
  }

  Future<void> copy() async {
    final text = widget.copyText;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => copied = true);
    copiedTimer?.cancel();
    copiedTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => copied = false);
    });
  }

  @override
  void didUpdateWidget(WorkspaceHoverCard old) {
    super.didUpdateWidget(old);
    if (widget.disabled && portal.isShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.disabled) close();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    copiedTimer?.cancel();
    if (widget.group.close == close) widget.group.close = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: portal,
    overlayChildBuilder: (overlayContext) {
      final box = context.findRenderObject()! as RenderBox;
      final anchor = box.localToGlobal(Offset.zero) & box.size;
      final theme = context.dsh;
      return CustomSingleChildLayout(
        delegate: _Position(anchor),
        child: MouseRegion(
          onEnter: (_) {
            timer?.cancel();
          },
          onExit: (_) => leave(),
          child: FocusableActionDetector(
            enabled: widget.copyText != null,
            onFocusChange: (focused) {
              if (focused) {
                timer?.cancel();
              } else {
                leave();
              }
            },
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  unawaited(copy());
                  return null;
                },
              ),
            },
            child: GestureDetector(
              onTap: widget.copyText == null ? null : () => unawaited(copy()),
              child: DshContainer(
                key: const ValueKey('workspace-hover-card'),
                width: 244,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.color('--dsw-static-neutral-bluish-850'),
                  borderRadius: BorderRadius.circular(theme.radiusLg),
                  boxShadow: theme.boxShadow('--dsw-shadow-lv3'),
                ),
                child: DefaultTextStyle(
                  style: theme
                      .textStyle('--dsw-font-s-14')
                      .copyWith(
                        color: theme.color('--dsw-static-neutral-bluish-00'),
                        height: 20 / 14,
                      ),
                  child: Stack(
                    children: [
                      Opacity(
                        opacity: copied ? 0 : 1,
                        child: SingleChildScrollView(
                          child: widget.content(overlayContext),
                        ),
                      ),
                      if (copied)
                        Positioned.fill(
                          child: Align(
                            alignment: AlignmentDirectional.topStart,
                            child: Semantics(
                              liveRegion: true,
                              child: DshChromeText(widget.copiedLabel),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    child: MouseRegion(
      onEnter: (_) => enter(),
      onExit: (_) => leave(),
      child: widget.child,
    ),
  );
}

class _Position extends SingleChildLayoutDelegate {
  _Position(this.anchor);
  final Rect anchor;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: math.min(244, math.max(0, constraints.maxWidth - 16)),
      ).copyWith(maxHeight: math.max(0, constraints.maxHeight - 16));
  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    anchor.right + 8,
    anchor.top.clamp(8, math.max(8, size.height - childSize.height - 8)),
  );
  @override
  bool shouldRelayout(_Position old) => old.anchor != anchor;
}
