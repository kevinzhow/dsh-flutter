import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dsh_control_focus_modality.dart';
import 'dsh_pixel_snap.dart';
import 'dsh_recipes.g.dart';
import 'dsh_snapped_box.dart';
import 'theme_access.dart';

/// The published Pill: a static capsule, or a button when [onPressed] is set.
///
/// [pressed] exposes the optional pressed state used by category filters;
/// [active] controls the independent visual state, as in the source component.
/// [height] and [color] are used by the terminal status's source overrides.
class DshPill extends StatefulWidget {
  const DshPill({
    super.key,
    required this.child,
    this.color,
    this.height = DshPillRecipe.height,
    this.active = false,
    this.pressed,
    this.onPressed,
    this.enabled = true,
    this.focusNode,
    this.semanticLabel,
  });

  final Widget child;
  final Color? color;
  final double height;
  final bool active, enabled;
  final bool? pressed;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final String? semanticLabel;

  static const Key surfaceKey = ValueKey<String>('dsh-pill-surface');
  static const Key focusRingKey = ValueKey<String>('dsh-pill-focus-ring');

  @override
  State<DshPill> createState() => _DshPillState();
}

class _DshPillState extends State<DshPill> {
  final FocusNode _ownedFocus = FocusNode(debugLabel: 'dsh pill');
  bool _hovered = false, _focused = false, _focusVisible = false;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocus;
  bool get _interactive => widget.onPressed != null;
  bool get _enabled => _interactive && widget.enabled;

  @override
  void initState() {
    super.initState();
    DshControlFocusModality.instance.acquire(_modalityChanged);
  }

  void _modalityChanged() => _set(() {});

  @override
  void didUpdateWidget(DshPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) _focused = _focusVisible = false;
  }

  @override
  void dispose() {
    DshControlFocusModality.instance.release(_modalityChanged);
    _ownedFocus.dispose();
    super.dispose();
  }

  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    // The hover selector has greater specificity than the active selector.
    final fill = _interactive && _hovered
        ? DshPillRecipe.hoverToken
        : widget.active
        ? DshPillRecipe.activeFillToken
        : DshPillRecipe.fillToken;
    final radius = BorderRadius.circular(DshPillRecipe.radius);
    final surface = DshContainer(
      key: DshPill.surfaceKey,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: DshPillRecipe.padding),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: theme.color(fill), borderRadius: radius),
      child: DefaultTextStyle.merge(
        style: theme
            .textStyle(DshPillRecipe.fontToken)
            .copyWith(
              color:
                  widget.color ??
                  theme.color(
                    widget.active
                        ? DshPillRecipe.activeLabelToken
                        : DshPillRecipe.labelToken,
                  ),
            ),
        child: widget.child,
      ),
    );
    final ringWidth = dshBorderWidthOf(context, theme.focusRingWidth);
    final ringReach = ringWidth / 2;
    final body = Stack(
      clipBehavior: Clip.none,
      children: [
        IntrinsicWidth(child: surface),
        if (widget.active)
          Positioned.fill(
            child: IgnorePointer(
              child: DshDecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: theme.color(DshPillRecipe.activeBorderToken),
                    width: DshPillRecipe.activeBorderWidth,
                  ),
                ),
              ),
            ),
          ),
        if (_enabled &&
            _focusVisible &&
            _focusNode.hasPrimaryFocus &&
            !DshControlFocusModality.instance.pointerOwnsFocus)
          Positioned(
            left: -ringReach,
            top: -ringReach,
            right: -ringReach,
            bottom: -ringReach,
            child: IgnorePointer(
              child: DshDecoratedBox(
                key: DshPill.focusRingKey,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    DshPillRecipe.radius + ringReach,
                  ),
                  border: Border.all(
                    color: theme.focusRingColor,
                    width: ringWidth,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (!_interactive) return body;
    return MergeSemantics(
      child: Semantics(
        container: true,
        button: true,
        enabled: _enabled,
        // Android maps `toggled` to a switch. A category is a button whose
        // selection is announced, so preserve its button role on native clients.
        selected: widget.pressed,
        focused: _focused,
        label: widget.semanticLabel,
        excludeSemantics: widget.semanticLabel != null,
        onTap: _enabled ? widget.onPressed : null,
        onFocus: _enabled ? _focusNode.requestFocus : null,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _set(() => _hovered = true),
          onExit: (_) => _set(() => _hovered = false),
          child: FocusableActionDetector(
            enabled: _enabled,
            focusNode: _focusNode,
            onFocusChange: (value) => _set(() => _focused = value),
            onShowFocusHighlight: (value) => _set(() => _focusVisible = value),
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  if (_enabled) widget.onPressed!();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: _enabled ? widget.onPressed : null,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
