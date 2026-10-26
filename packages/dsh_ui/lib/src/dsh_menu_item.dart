import 'package:dsh_theme/dsh_theme.dart' show SizeScale;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_icon.dart';
import 'dsh_icon_data.dart';
import 'dsh_icons.g.dart';
import 'dsh_recipes.g.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

enum DshMenuItemProfile { standard, addPlugin, dock }

/// One canonical menu row. Source profiles own geometry; callers supply the
/// label, optional description/icon and action instead of styling a button.
class DshMenuItemButton extends StatefulWidget {
  const DshMenuItemButton({
    super.key,
    required this.label,
    this.description,
    this.icon,
    this.onPressed,
    this.disabled = false,
    this.danger = false,
    this.selected = false,
    this.selectionFill = false,
    this.dense = false,
    this.compact = false,
    this.profile = DshMenuItemProfile.standard,
    this.focusNode,
    this.autofocus = false,
    this.onDismiss,
  }) : assert(description == null || profile == DshMenuItemProfile.addPlugin);
  final String label;
  final String? description;
  final DshIconData? icon;
  final VoidCallback? onPressed;
  final bool disabled, danger, selected, selectionFill, dense, compact;
  final DshMenuItemProfile profile;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onDismiss;
  @override
  State<DshMenuItemButton> createState() => _DshMenuItemButtonState();
}

class _DshMenuItemButtonState extends State<DshMenuItemButton> {
  bool _hover = false, _focusVisible = false;
  bool get _enabled => !widget.disabled && widget.onPressed != null;

  @override
  void didUpdateWidget(DshMenuItemButton old) {
    super.didUpdateWidget(old);
    if (!_enabled) _hover = _focusVisible = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final add = widget.profile == DshMenuItemProfile.addPlugin;
    final dock = widget.profile == DshMenuItemProfile.dock;
    final compact = widget.compact && !add && !dock;
    final hover = _enabled && (_hover || (_focusVisible && !dock));
    final iconSize = compact
        ? DshMenuRecipe.compactIconSize
        : DshMenuRecipe.iconSize;
    final gap = add
        ? DshPluginAddMenuRecipe.gap
        : compact
        ? DshMenuRecipe.compactGap
        : DshMenuRecipe.gap;
    final ink = theme.color(
      dock
          ? DshDockMenuRecipe.labelToken
          : widget.danger
          ? DshMenuRecipe.dangerToken
          : DshMenuRecipe.labelToken,
    );
    var style = theme
        .textStyle(
          compact ? DshMenuRecipe.compactFontToken : DshMenuRecipe.fontToken,
        )
        .copyWith(
          color: ink,
          height: compact
              ? DshMenuRecipe.compactLineHeight / DshMenuRecipe.compactFontSize
              : DshMenuRecipe.lineHeight / DshMenuRecipe.fontSize,
        );
    if (dock) {
      final size =
          DshDockMenuRecipe.fontBase +
          SizeScale.tryParse(DshDockMenuRecipe.fontScale)!
              .delta(theme.settings.fontSizes);
      style = theme
          .fixedTextStyle(size: size, line: size)
          .copyWith(color: ink, height: kTextHeightNone);
    }
    final radius = theme.number(
      dock
          ? DshDockMenuRecipe.radiusToken
          : compact
          ? DshMenuRecipe.compactRadiusToken
          : DshMenuRecipe.radiusToken,
    );
    final selectedFill = widget.selected && widget.selectionFill;
    final fill = hover
        ? theme.color(
            dock
                ? DshDockMenuRecipe.hoverToken
                : widget.danger
                ? (_focusVisible
                      ? DshMenuRecipe.dangerFocusToken
                      : DshMenuRecipe.dangerHoverToken)
                : (_focusVisible
                      ? DshMenuRecipe.focusToken
                      : DshMenuRecipe.hoverToken),
          )
        : selectedFill
        ? theme.color(DshMenuRecipe.selectedFillToken)
        : null;
    final surface = DshContainer(
      height: add ? DshPluginAddMenuRecipe.height : null,
      constraints: dock
          ? null
          : BoxConstraints(
              minHeight: add
                  ? DshPluginAddMenuRecipe.height
                  : compact
                  ? DshMenuRecipe.compactHeight
                  : widget.dense
                  ? DshMenuRecipe.denseHeight
                  : DshMenuRecipe.height,
            ),
      padding: EdgeInsets.symmetric(
        horizontal: dock
            ? DshDockMenuRecipe.horizontalPadding
            : add
            ? DshPluginAddMenuRecipe.horizontalPadding
            : compact
            ? DshMenuRecipe.compactHorizontalPadding
            : DshMenuRecipe.horizontalPadding,
        vertical: dock
            ? DshDockMenuRecipe.verticalPadding
            : add
            ? DshPluginAddMenuRecipe.verticalPadding
            : compact
            ? DshMenuRecipe.compactVerticalPadding
            : widget.dense
            ? DshMenuRecipe.denseVerticalPadding
            : DshMenuRecipe.verticalPadding,
      ),
      decoration: theme.cornerDecoration(radius, color: fill),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            DshIcon(
              widget.icon!,
              size: iconSize,
              color: theme.color(
                widget.danger
                    ? DshMenuRecipe.dangerIconToken
                    : DshMenuRecipe.iconToken,
              ),
            ),
            SizedBox(width: gap),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DshChromeText(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
                if (widget.description != null) ...[
                  SizedBox(height: DshPluginAddMenuRecipe.descriptionGap),
                  DshChromeText(
                    widget.description!,
                    maxLines:
                        (DshPluginAddMenuRecipe.descriptionMaxHeight /
                                DshPluginAddMenuRecipe.descriptionLineHeight)
                            .toInt(),
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .textStyle(DshPluginAddMenuRecipe.descriptionFontToken)
                        .copyWith(
                          color: theme.color(
                            DshPluginAddMenuRecipe.descriptionToken,
                          ),
                          height:
                              DshPluginAddMenuRecipe.descriptionLineHeight /
                              DshPluginAddMenuRecipe.descriptionFontSize,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.selected && !widget.selectionFill) ...[
            SizedBox(width: gap),
            DshIcon(
              DshIcons.check,
              size: iconSize,
              color: theme.color(DshMenuRecipe.checkToken),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: _enabled,
      selected: widget.selected,
      label: [
        widget.label,
        if (widget.description != null) widget.description!,
      ].join('\n'),
      excludeSemantics: true,
      onTap: _enabled ? widget.onPressed : null,
      child: MouseRegion(
        cursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: FocusableActionDetector(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          enabled: _enabled,
          shortcuts: {
            const SingleActivator(LogicalKeyboardKey.enter):
                const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.space):
                const ActivateIntent(),
            if (!dock)
              const SingleActivator(LogicalKeyboardKey.tab):
                  const ActivateIntent(),
            if (widget.onDismiss != null) ...{
              const SingleActivator(LogicalKeyboardKey.escape):
                  const DismissIntent(),
              if (!dock)
                const SingleActivator(LogicalKeyboardKey.tab, shift: true):
                    const DismissIntent(),
            },
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (_enabled) widget.onPressed?.call();
                return null;
              },
            ),
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                widget.onDismiss?.call();
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) {
            if (mounted) setState(() => _focusVisible = value);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _enabled ? widget.onPressed : null,
            child: Opacity(
              opacity: _enabled ? 1 : DshMenuRecipe.disabledOpacity,
              child: (dock && _focusVisible && _enabled)
                  ? Stack(
                      clipBehavior: Clip.none,
                      children: [
                        surface,
                        Positioned(
                          left: -theme.focusRingWidth / 2,
                          top: -theme.focusRingWidth / 2,
                          right: -theme.focusRingWidth / 2,
                          bottom: -theme.focusRingWidth / 2,
                          child: IgnorePointer(
                            child: DshDecoratedBox(
                              decoration: theme.cornerDecoration(
                                radius + theme.focusRingWidth / 2,
                                borderColor: theme.focusRingColor,
                                borderWidth: theme.focusRingWidth,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : surface,
            ),
          ),
        ),
      ),
    );
  }
}
