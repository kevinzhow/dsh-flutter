import 'package:dsh_theme/dsh_theme.dart' show SizeScale;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_icon.dart';
import 'dsh_icon_data.dart';
import 'dsh_icons.g.dart';
import 'dsh_recipes.g.dart';
import 'dsh_snapped_box.dart';
import 'dsh_status_dot.dart';
import 'dsh_text_baseline.dart';
import 'dsh_tooltip.dart';
import 'theme_access.dart';

enum DshMenuItemProfile {
  standard,
  addPlugin,
  dock,
  sidebarLauncher,
  modelCell,
  modelOption,
}

/// An effective shortcut supplied by the action owner, not a default binding.
class DshMenuShortcut {
  const DshMenuShortcut({required this.keys, this.aria});
  final List<String> keys;
  final String? aria;
}

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
    this.shortcut,
    this.autofocus = false,
    this.onDismiss,
    this.value,
    this.trailing,
    this.active = false,
    this.onHover,
    this.onFocusChange,
    this.focusVisible,
    this.pending = false,
  }) : assert(description == null || profile == DshMenuItemProfile.addPlugin);
  final String label;
  final String? description;
  final DshIconData? icon;
  final VoidCallback? onPressed;
  final bool disabled, danger, selected, selectionFill, dense, compact;
  final DshMenuItemProfile profile;
  final FocusNode? focusNode;
  final DshMenuShortcut? shortcut;
  final bool autofocus;
  final VoidCallback? onDismiss;
  final String? value;
  final Widget? trailing;
  final bool active;
  final VoidCallback? onHover;
  final ValueChanged<bool>? onFocusChange;

  /// Source focus intent for programmatic entry, applied only while this row
  /// actually owns focus. Null keeps the default input-modality presentation.
  final bool? focusVisible;
  final bool pending;
  @override
  State<DshMenuItemButton> createState() => _DshMenuItemButtonState();
}

class _DshMenuItemButtonState extends State<DshMenuItemButton> {
  bool _hover = false, _focusVisible = false, _focused = false;
  final _ownedFocus = FocusNode();
  bool get _enabled => !widget.disabled && widget.onPressed != null;
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocus;

  @override
  void didUpdateWidget(DshMenuItemButton old) {
    super.didUpdateWidget(old);
    if (!_enabled) _hover = _focusVisible = _focused = false;
  }

  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final add = widget.profile == DshMenuItemProfile.addPlugin;
    final dock = widget.profile == DshMenuItemProfile.dock;
    final sidebar = widget.profile == DshMenuItemProfile.sidebarLauncher;
    final cell = widget.profile == DshMenuItemProfile.modelCell;
    final model = cell || widget.profile == DshMenuItemProfile.modelOption;
    final compact = widget.compact && !add && !dock && !sidebar && !model;
    final focusVisible = widget.focusVisible == null
        ? _focusVisible
        : widget.focusVisible! && _focusNode.hasPrimaryFocus;
    final hover =
        _enabled && (_hover || widget.active || (focusVisible && !dock));
    final iconSize = sidebar
        ? DshSidebarLauncherRecipe.menuIconSize
        : compact
        ? DshMenuRecipe.compactIconSize
        : DshMenuRecipe.iconSize;
    final gap = sidebar
        ? DshSidebarLauncherRecipe.menuRowGap
        : model
        ? DshModelMenuRecipe.rowGap
        : add
        ? DshPluginAddMenuRecipe.gap
        : compact
        ? DshMenuRecipe.compactGap
        : DshMenuRecipe.gap;
    final ink = theme.color(
      model && !_enabled
          ? DshModelMenuRecipe.disabledToken
          : dock
          ? DshDockMenuRecipe.labelToken
          : widget.danger
          ? DshMenuRecipe.dangerToken
          : DshMenuRecipe.labelToken,
    );
    var style = theme
        .textStyle(
          model
              ? (cell
                    ? DshModelMenuRecipe.cellFontToken
                    : DshModelMenuRecipe.rowFontToken)
              : compact
              ? DshMenuRecipe.compactFontToken
              : DshMenuRecipe.fontToken,
        )
        .copyWith(
          color: ink,
          fontWeight: model
              ? FontWeight.values[(DshModelMenuRecipe.rowFontWeight ~/ 100) - 1]
              : null,
          height: model
              ? cell
                    ? DshModelMenuRecipe.cellLineHeight /
                          DshModelMenuRecipe.cellFontSize
                    : DshModelMenuRecipe.rowLineHeight /
                          DshModelMenuRecipe.rowFontSize
              : compact
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
      model
          ? DshModelMenuRecipe.radiusToken
          : dock
          ? DshDockMenuRecipe.radiusToken
          : compact
          ? DshMenuRecipe.compactRadiusToken
          : DshMenuRecipe.radiusToken,
    );
    final selectedFill = widget.selected && widget.selectionFill;
    final fill = hover
        ? theme.color(
            model
                ? DshModelMenuRecipe.hoverToken
                : dock
                ? DshDockMenuRecipe.hoverToken
                : widget.danger
                ? (focusVisible
                      ? DshMenuRecipe.dangerFocusToken
                      : DshMenuRecipe.dangerHoverToken)
                : (focusVisible
                      ? DshMenuRecipe.focusToken
                      : DshMenuRecipe.hoverToken),
          )
        : selectedFill
        ? theme.color(DshMenuRecipe.selectedFillToken)
        : null;
    final under = DshSurface.maybeOf(context);
    // Only a declared opaque menu/card ground can be precomposited. Keep the
    // existing translucent paint when the caller's backdrop is unknown.
    final paintedFill = fill == null || under == null || under.a < 1
        ? fill
        : DshSurface.paint(context, fill, over: under);
    final surface = DshContainer(
      height: add ? DshPluginAddMenuRecipe.height : null,
      constraints: dock
          ? null
          : BoxConstraints(
              minHeight: sidebar
                  ? DshSidebarLauncherRecipe.menuRowHeight
                  : model
                  ? DshModelMenuRecipe.rowHeight
                  : add
                  ? DshPluginAddMenuRecipe.height
                  : compact
                  ? DshMenuRecipe.compactHeight
                  : widget.dense
                  ? DshMenuRecipe.denseHeight
                  : DshMenuRecipe.height,
            ),
      padding: EdgeInsets.symmetric(
        horizontal: sidebar
            ? DshSidebarLauncherRecipe.menuRowHorizontalPadding
            : model
            ? cell
                  ? DshModelMenuRecipe.cellHorizontalPadding
                  : DshModelMenuRecipe.rowHorizontalPadding
            : dock
            ? DshDockMenuRecipe.horizontalPadding
            : add
            ? DshPluginAddMenuRecipe.horizontalPadding
            : compact
            ? DshMenuRecipe.compactHorizontalPadding
            : DshMenuRecipe.horizontalPadding,
        vertical: sidebar
            ? DshSidebarLauncherRecipe.menuRowVerticalPadding
            : model
            ? cell
                  ? DshModelMenuRecipe.cellVerticalPadding
                  : DshModelMenuRecipe.rowVerticalPadding
            : dock
            ? DshDockMenuRecipe.verticalPadding
            : add
            ? DshPluginAddMenuRecipe.verticalPadding
            : compact
            ? DshMenuRecipe.compactVerticalPadding
            : widget.dense
            ? DshMenuRecipe.denseVerticalPadding
            : DshMenuRecipe.verticalPadding,
      ),
      decoration: theme.cornerDecoration(radius, color: paintedFill),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            DshIcon(
              widget.icon!,
              size: iconSize,
              color: theme.color(
                sidebar
                    ? DshSidebarLauncherRecipe.menuIconToken
                    : widget.danger
                    ? DshMenuRecipe.dangerIconToken
                    : DshMenuRecipe.iconToken,
              ),
            ),
            SizedBox(width: gap),
          ],
          if (cell)
            DshChromeText(widget.label, maxLines: 1, style: style)
          else
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
                          .textStyle(
                            DshPluginAddMenuRecipe.descriptionFontToken,
                          )
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
          if (widget.value case final value?) ...[
            SizedBox(width: gap),
            Expanded(
              child: DshChromeText(
                value,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(
                  color: theme.color(DshModelMenuRecipe.valueToken),
                ),
              ),
            ),
          ],
          if (widget.shortcut case final shortcut?) ...[
            SizedBox(width: gap),
            DshShortcutKeys(keys: shortcut.keys, menu: true),
          ],
          if (model) ...[
            SizedBox(width: gap),
            if (cell)
              DshIcon(
                DshIcons.chevronRight,
                size: DshModelMenuRecipe.chevronSize,
                color: theme.color(DshModelMenuRecipe.chevronToken),
              )
            else
              SizedBox.square(
                dimension: DshModelMenuRecipe.checkSize,
                child: widget.pending
                    ? const DshStatusDot(DshStatus.running)
                    : widget.selected
                    ? DshIcon(
                        DshIcons.check,
                        size: DshModelMenuRecipe.checkSize,
                        color: theme.color(DshModelMenuRecipe.checkToken),
                      )
                    : null,
              ),
          ] else if (widget.trailing case final trailing?) ...[
            SizedBox(width: gap),
            trailing,
          ] else if (widget.selected && !widget.selectionFill) ...[
            SizedBox(width: gap),
            DshIcon(
              DshIcons.check,
              size: model ? DshModelMenuRecipe.checkSize : iconSize,
              color: theme.color(DshMenuRecipe.checkToken),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      focusable: _enabled,
      focused: _enabled ? _focused : null,
      onFocus: _enabled && defaultTargetPlatform != TargetPlatform.iOS
          ? _focusNode.requestFocus
          : null,
      selected: widget.selected,
      hint: widget.shortcut?.aria,
      label: [
        widget.label,
        if (widget.value != null) widget.value!,
        if (widget.description != null) widget.description!,
      ].join('\n'),
      excludeSemantics: true,
      onTap: _enabled ? widget.onPressed : null,
      child: MouseRegion(
        cursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onEnter: (_) {
          setState(() => _hover = true);
          widget.onHover?.call();
        },
        onExit: (_) => setState(() => _hover = false),
        child: FocusableActionDetector(
          focusNode: _focusNode,
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
          onFocusChange: (value) {
            if (mounted && _focused != value) setState(() => _focused = value);
            widget.onFocusChange?.call(value);
          },
          onShowFocusHighlight: (value) {
            if (mounted) setState(() => _focusVisible = value);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _enabled ? widget.onPressed : null,
            child: Opacity(
              opacity: _enabled || model ? 1 : DshMenuRecipe.disabledOpacity,
              child: (dock && focusVisible && _enabled)
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
