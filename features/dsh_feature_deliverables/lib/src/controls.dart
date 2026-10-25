import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Keyboard-capable card surface. Overlay actions are sibling controls so a
/// preview gesture cannot also invoke a native application.
class DeliveryTap extends StatefulWidget {
  const DeliveryTap({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.fill = false,
    this.padding = EdgeInsets.zero,
  });
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool fill;
  final EdgeInsets padding;
  @override
  State<DeliveryTap> createState() => _DeliveryTapState();
}

class _DeliveryTapState extends State<DeliveryTap> {
  bool hovered = false, focused = false;
  final focus = FocusNode();
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onTap,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): widget.onTap,
          const SingleActivator(LogicalKeyboardKey.space): widget.onTap,
        },
        child: Focus(
          focusNode: focus,
          onFocusChange: (v) => setState(() => focused = v),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => hovered = true),
            onExit: (_) => setState(() => hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                focus.requestFocus();
                widget.onTap();
              },
              child: DshContainer(
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: hovered || focused
                      ? theme.color('--dsw-alias-interactive-bg-hover')
                      : widget.fill
                      ? theme.color(
                          theme.brightness == Brightness.dark
                              ? '--dsw-static-neutral-850'
                              : '--dsw-static-neutral-50',
                        )
                      : null,
                  border: focused
                      ? Border.all(
                          color: theme.color(
                            '--dsw-alias-state-business-primary',
                          ),
                          width: 2,
                        )
                      : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
