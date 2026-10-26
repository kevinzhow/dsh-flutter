import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import 'dsh_corners.dart' show DshCornerDecoration, DshSurface;
import 'dsh_pixel_snap.dart';
import 'dsh_recipes.g.dart';
import 'dsh_snapped_box.dart';

/// Visual family of a [DshButton], as dsh's `ButtonVariant`.
enum DshButtonVariant {
  /// Solid brand fill (`--dsw-alias-button-primary-*`).
  primary,

  /// Transparent until hovered or pressed (`--dsw-alias-interactive-bg-*`).
  ghost,

  /// Transparent with a 0.5px `--dsw-alias-border-l3` stroke.
  outline,

  /// Translucent tool bar fill (`--dsw-alias-button-tool-bar-*`).
  toolbar,
}

/// Size of a [DshButton]: `md` is a 36px control with `--dsw-radius-md` corners,
/// `sm` a 28px control with `--dsw-radius-sm` corners.
enum DshButtonSize {
  /// 36px tall, 14px text.
  md,

  /// 28px tall, 12px text.
  sm,
}

/// Token-styled button, ported from dsh's `Button.tsx` / `Button.module.css`.
///
/// Every colour, radius, focus ring width and text style comes from the
/// [DshThemeData] extension of the ambient `Theme`; the widget never looks at
/// which pack produced it. States: default, hover, pressed, disabled
/// (`onPressed == null`), and a keyboard-only focus ring that uses
/// `--dsw-focus-ring-width` and dsh's focus colour (`--dsw-alias-state-business-primary`).
///
/// Component constants that dsh keeps in the component sheet rather than in a
/// token (heights 36/28, paddings 14/10, icon box 16, gap 4, disabled opacity
/// 0.4, hairline 0.5) stay here.
class DshButton extends StatefulWidget {
  /// Creates a button. [onPressed] null disables it.
  const DshButton({
    super.key,
    required this.child,
    this.onPressed,
    this.variant = DshButtonVariant.ghost,
    this.size = DshButtonSize.md,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.height,
    this.horizontalPadding,
    this.labelStyle,
    this.radius,
  });

  /// Label, usually a `Text`; it inherits the button's text style and colour.
  final Widget child;

  /// Called on tap, Enter or Space; null disables the button.
  final VoidCallback? onPressed;

  /// Visual family (default ghost, as in dsh).
  final DshButtonVariant variant;

  /// Size (default md).
  final DshButtonSize size;

  /// Optional leading 16px icon.
  final Widget? icon;

  /// Focus node for focus management.
  final FocusNode? focusNode;

  /// Whether the button takes focus when first built.
  final bool autofocus;

  /// Accessibility label; defaults to the child's text.
  final String? semanticLabel;

  /// Component-level CSS overrides; omitted values retain primitive metrics.
  final double? height, horizontalPadding, radius;
  final TextStyle? labelStyle;

  /// Key of the painted surface (fill, border, radius); for tests.
  static const Key surfaceKey = ValueKey<String>('dshButtonSurface');

  /// Key of the focus ring; present only while keyboard focus is visible.
  static const Key focusRingKey = ValueKey<String>('dshButtonFocusRing');

  /// Opacity of a disabled button (`Button.module.css` `.button:disabled`).
  static const double disabledOpacity = DshButtonRecipe.disabledOpacity;

  @override
  State<DshButton> createState() => _DshButtonState();
}

class _DshButtonState extends State<DshButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focusVisible = false;

  bool get _enabled => widget.onPressed != null;

  @override
  void didUpdateWidget(DshButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) {
      _hovered = false;
      _pressed = false;
      _focusVisible = false;
    }
  }

  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<DshThemeData>();
    if (theme == null) {
      throw FlutterError(
        'DshButton needs a DshThemeData in Theme.of(context).extensions. '
        'Build one with resolveTheme() and pass it as ThemeData(extensions: [...]).',
      );
    }
    final small = widget.size == DshButtonSize.sm;
    final radius =
        widget.radius ??
        theme.number(
          small
              ? DshButtonRecipe.smallRadiusToken
              : DshButtonRecipe.radiusToken,
        );
    final rawFill = _fill(theme);
    // A disabled button is one translucent group (`opacity: 0.4` on the whole
    // button), so its fill must stay translucent inside the group: the group
    // composites onto the page, not the fill.
    Color paint(Color c, {Color? over}) => _enabled
        ? DshSurface.paint(context, c, over: over)
        : DshSurface.quantizeAlpha(c);
    final fill = rawFill == null ? null : paint(rawFill);
    final foreground = widget.variant == DshButtonVariant.primary
        ? theme.color(DshButtonRecipe.primaryLabelToken)
        : theme.color(DshButtonRecipe.labelToken);
    final textStyle = theme
        .textStyle(
          small ? DshButtonRecipe.smallFontToken : DshButtonRecipe.fontToken,
        )
        .copyWith(color: foreground, decoration: TextDecoration.none)
        .merge(widget.labelStyle);
    // `.outline { border: 0.5px solid }` on a border-box button of fixed
    // height: Blink snaps the border to whole device pixels
    // ([dshHairlineOf]: one device pixel on a phone, a whole CSS pixel in the
    // emulated capture) and it widens the box (the content width is padding +
    // label + both borders).
    final outlined = widget.variant == DshButtonVariant.outline;
    final borderWidth = outlined
        ? dshBorderWidthOf(context, DshButtonRecipe.outlineWidth)
        : 0.0;
    // Chromium paints the background under the border too, so the hairline
    // lands on the fill when there is one.
    // Chromium paints the background under the border too, so the hairline
    // lands on the fill when there is one.
    final borderColor = outlined
        ? paint(
            theme.color(DshButtonRecipe.outlineToken),
            over: fill != null && fill.a >= 1 ? fill : null,
          )
        : null;

    final surface = DshDecoratedBox(
      key: DshButton.surfaceKey,
      decoration: theme.cornerDecoration(
        radius,
        color: fill,
        borderColor: borderColor,
        borderWidth: borderWidth,
      ),
      child: Container(
        height:
            widget.height ??
            (small ? DshButtonRecipe.smallHeight : DshButtonRecipe.height),
        padding: EdgeInsets.symmetric(
          horizontal:
              (widget.horizontalPadding ??
                  (small
                      ? DshButtonRecipe.smallPadding
                      : DshButtonRecipe.padding)) +
              borderWidth,
        ),
        child: DefaultTextStyle.merge(
          style: textStyle,
          child: IconTheme(
            data: IconThemeData(
              color: foreground,
              size: DshButtonRecipe.iconSize,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  SizedBox(
                    width: DshButtonRecipe.iconSize,
                    height: DshButtonRecipe.iconSize,
                    child: Center(child: widget.icon),
                  ),
                  const SizedBox(width: DshButtonRecipe.gap),
                ],
                Flexible(child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );

    final ringWidth = theme.focusRingWidth;
    // dsh sets `outline-width` only; the button keeps the UA's `outline-style:
    // auto`, which Chromium draws centred on the border edge (half the width
    // outside, half inside), not outside it as a plain outline would.
    final ringReach = ringWidth / 2;
    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        surface,
        if (_focusVisible && _enabled)
          Positioned(
            left: -ringReach,
            top: -ringReach,
            right: -ringReach,
            bottom: -ringReach,
            child: IgnorePointer(
              child: DshDecoratedBox(
                key: DshButton.focusRingKey,
                decoration: theme.cornerDecoration(
                  radius + ringReach,
                  borderColor: theme.focusRingColor,
                  borderWidth: ringWidth,
                ),
              ),
            ),
          ),
      ],
    );

    // Hover is tracked here, not through FocusableActionDetector, which only
    // reports hover while the focus highlight mode is "traditional".
    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      onTap: widget.onPressed,
      child: MouseRegion(
        onEnter: (_) => _set(() => _hovered = true),
        onExit: (_) => _set(() => _hovered = false),
        child: FocusableActionDetector(
          enabled: _enabled,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          mouseCursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) => _set(() => _focusVisible = value),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _enabled ? (_) => _set(() => _pressed = true) : null,
            onTapUp: _enabled ? (_) => _set(() => _pressed = false) : null,
            onTapCancel: _enabled ? () => _set(() => _pressed = false) : null,
            onTap: widget.onPressed,
            child: Opacity(
              opacity: _enabled ? 1 : DshButton.disabledOpacity,
              child: stack,
            ),
          ),
        ),
      ),
    );
  }

  Color? _fill(DshThemeData theme) {
    final active = _enabled && _pressed;
    final hover = _enabled && (_hovered || _pressed);
    switch (widget.variant) {
      case DshButtonVariant.primary:
        return theme.color(
          hover
              ? DshButtonRecipe.primaryHoverToken
              : DshButtonRecipe.primaryToken,
        );
      case DshButtonVariant.ghost:
        if (active) return theme.color(DshButtonRecipe.activeToken);
        return hover ? theme.color(DshButtonRecipe.hoverToken) : null;
      case DshButtonVariant.outline:
        return hover ? theme.color(DshButtonRecipe.outlineHoverToken) : null;
      case DshButtonVariant.toolbar:
        return theme.color(
          hover
              ? DshButtonRecipe.toolbarHoverToken
              : DshButtonRecipe.toolbarToken,
        );
    }
  }
}
