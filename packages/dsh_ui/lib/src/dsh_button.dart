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

/// Published CSS profiles layered on the common button interaction model.
enum DshButtonProfile { primitive, addAction, iconAction, infoAction }

/// Physical corners used by DSH's left-to-right compound add control.
enum DshButtonJoin { none, left, right }

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
/// 0.4, hairline 0.5) are generated in `dsh_recipes.g.dart`.
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
    this.profile = DshButtonProfile.primitive,
    this.join = DshButtonJoin.none,
  }) : assert(
         profile == DshButtonProfile.primitive ||
             (height == null &&
                 horizontalPadding == null &&
                 radius == null &&
                 labelStyle == null),
         'Published button profiles own their metrics and typography.',
       ),
       assert(
         join == DshButtonJoin.none || profile == DshButtonProfile.addAction,
       );

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
  final DshButtonProfile profile;
  final DshButtonJoin join;

  /// Key of the painted surface (fill, border, radius); for tests.
  static const Key surfaceKey = ValueKey<String>('dshButtonSurface');

  /// Key of the focus ring; present only while keyboard focus is visible.
  static const Key focusRingKey = ValueKey<String>('dshButtonFocusRing');

  /// Opacity of a disabled button (`Button.module.css` `.button:disabled`).
  static const double disabledOpacity = DshButtonRecipe.disabledOpacity;

  @override
  State<DshButton> createState() => _DshButtonState();
}

/// DSH's add action and optional method picker. Each half owns its background,
/// corner shape, disabled opacity and focus outline; there is no outer clip.
class DshSplitButton extends StatelessWidget {
  const DshSplitButton({
    super.key,
    required this.child,
    required this.more,
    required this.moreLabel,
    this.icon,
    this.onPressed,
    this.onMore,
    this.showMore = true,
    this.focusNode,
    this.moreFocusNode,
  });
  final Widget child, more;
  final Widget? icon;
  final String moreLabel;
  final VoidCallback? onPressed, onMore;
  final bool showMore;
  final FocusNode? focusNode, moreFocusNode;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DshButton(
        profile: DshButtonProfile.addAction,
        variant: DshButtonVariant.primary,
        join: showMore ? DshButtonJoin.left : DshButtonJoin.none,
        icon: icon,
        focusNode: focusNode,
        onPressed: onPressed,
        child: child,
      ),
      if (showMore)
        DshButton(
          profile: DshButtonProfile.addAction,
          variant: DshButtonVariant.primary,
          join: DshButtonJoin.right,
          semanticLabel: moreLabel,
          focusNode: moreFocusNode,
          onPressed: onMore,
          child: more,
        ),
    ],
  );
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
    final small =
        widget.size == DshButtonSize.sm ||
        widget.profile == DshButtonProfile.infoAction;
    final add = widget.profile == DshButtonProfile.addAction;
    final iconAction = widget.profile == DshButtonProfile.iconAction;
    final info = widget.profile == DshButtonProfile.infoAction;
    final compactAction = iconAction || info;
    final radiusToken = compactAction
        ? DshIconActionRecipe.radiusToken
        : add
        ? DshAddButtonRecipe.radiusToken
        : small
        ? DshButtonRecipe.smallRadiusToken
        : DshButtonRecipe.radiusToken;
    final radius = widget.radius ?? theme.number(radiusToken);
    BorderRadius? corners(double r) => switch (widget.join) {
      DshButtonJoin.none => null,
      DshButtonJoin.left => BorderRadius.only(
        topLeft: Radius.circular(r),
        bottomLeft: Radius.circular(r),
      ),
      DshButtonJoin.right => BorderRadius.only(
        topRight: Radius.circular(r),
        bottomRight: Radius.circular(r),
      ),
    };
    final hover = _enabled && (_hovered || _pressed);
    final rawFill = iconAction
        ? hover
              ? theme.color(DshIconActionRecipe.hoverToken)
              : null
        : _fill(theme);
    // A disabled button is one translucent group (`opacity: 0.4` on the whole
    // button), so its fill must stay translucent inside the group: the group
    // composites onto the page, not the fill.
    Color paint(Color c, {Color? over}) => _enabled
        ? DshSurface.paint(context, c, over: over)
        : DshSurface.quantizeAlpha(c);
    final fill = rawFill == null ? null : paint(rawFill);
    final foreground = iconAction
        ? theme.color(
            hover
                ? DshIconActionRecipe.hoverLabelToken
                : DshIconActionRecipe.labelToken,
          )
        : info
        ? theme.color(DshIconActionRecipe.infoLabelToken)
        : widget.variant == DshButtonVariant.primary
        ? theme.color(DshButtonRecipe.primaryLabelToken)
        : theme.color(DshButtonRecipe.labelToken);
    final textStyle = theme
        .textStyle(
          add
              ? DshAddButtonRecipe.fontToken
              : small
              ? DshButtonRecipe.smallFontToken
              : DshButtonRecipe.fontToken,
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
    final borderColor = outlined
        ? paint(
            theme.color(DshButtonRecipe.outlineToken),
            over: fill != null && fill.a >= 1 ? fill : null,
          )
        : null;
    final dividerWidth = add && widget.join == DshButtonJoin.right
        ? dshBorderWidthOf(context, DshAddButtonRecipe.dividerWidth)
        : 0.0;
    final dividerForeground = theme.color(DshAddButtonRecipe.dividerToken);
    final dividerColor = paint(
      dividerForeground.withValues(
        alpha: dividerForeground.a * DshAddButtonRecipe.dividerAlpha,
      ),
      over: fill,
    );
    final profileWidth = compactAction
        ? info
              ? DshIconActionRecipe.infoWidth
              : DshIconActionRecipe.width
        : add && widget.join == DshButtonJoin.right
        ? DshAddButtonRecipe.moreWidth
        : null;

    final surface = DshDecoratedBox(
      key: DshButton.surfaceKey,
      decoration: theme.cornerDecoration(
        radius,
        corners: corners(radius),
        color: fill,
        borderColor: borderColor,
        borderWidth: borderWidth,
      ),
      child: Container(
        width: profileWidth,
        height:
            widget.height ??
            (compactAction
                ? info
                      ? DshIconActionRecipe.infoHeight
                      : DshIconActionRecipe.height
                : add
                ? DshAddButtonRecipe.height
                : small
                ? DshButtonRecipe.smallHeight
                : DshButtonRecipe.height),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (dividerWidth > 0)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: dividerWidth,
                child: ColoredBox(color: dividerColor),
              ),
            Padding(
              padding: EdgeInsets.only(
                left:
                    dividerWidth +
                    (widget.horizontalPadding ??
                        (compactAction || widget.join == DshButtonJoin.right
                            ? 0
                            : add
                            ? DshAddButtonRecipe.padding
                            : (small
                                  ? DshButtonRecipe.smallPadding
                                  : DshButtonRecipe.padding))) +
                    borderWidth,
                right:
                    (widget.horizontalPadding ??
                        (compactAction || widget.join == DshButtonJoin.right
                            ? 0
                            : add
                            ? DshAddButtonRecipe.padding
                            : small
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
          ],
        ),
      ),
    );

    final ringWidth = iconAction
        ? theme.number(DshIconActionRecipe.focusWidthToken)
        : theme.focusRingWidth;
    final ringColor = iconAction
        ? theme.colors[DshIconActionRecipe.focusToken] ??
              theme.color(DshIconActionRecipe.focusFallbackToken)
        : theme.focusRingColor;
    // dsh sets `outline-width` only; the button keeps the UA's `outline-style:
    // auto`, which Chromium draws centred on the border edge (half the width
    // outside, half inside), not outside it as a plain outline would.
    final ringReach = iconAction
        ? ringWidth + DshIconActionRecipe.focusOffset
        : ringWidth / 2;
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
                  corners: corners(radius + ringReach),
                  borderColor: ringColor,
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
              : iconAction
              ? SystemMouseCursors.basic
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
              opacity: _enabled
                  ? 1
                  : iconAction
                  ? DshIconActionRecipe.disabledOpacity
                  : DshButton.disabledOpacity,
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
