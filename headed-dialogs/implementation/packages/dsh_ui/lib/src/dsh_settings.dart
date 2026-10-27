import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_control_focus_modality.dart';
import 'dsh_diff_block.dart' show blendLikeChromium;
import 'dsh_icon.dart';
import 'dsh_icon_data.dart';
import 'dsh_icons.g.dart';
import 'dsh_pixel_snap.dart';
import 'dsh_recipes.g.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// Marks the subtree that ends a settings column: dsh's section CSS strips the
/// trailing separator of the last row of the column
/// (`GeneralSection.module.css`, `FontSettingsGroup.module.css`). A row asks
/// [DshColumnEnd.of] instead of being told, since its slot occupant cannot know
/// where the column ends.
class DshColumnEnd extends InheritedWidget {
  const DshColumnEnd({super.key, required super.child});

  /// Whether [context] sits in the last item of a settings column.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DshColumnEnd>() != null;

  @override
  bool updateShouldNotify(DshColumnEnd oldWidget) => false;
}

/// One line (or a wrapped paragraph) of dsh text with Chromium's baseline and
/// a fixed line height, as the settings rows paint their literal 14/22 and
/// 12/18 lines.
class DshLineText extends StatelessWidget {
  const DshLineText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return DshChromeText(
      text,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textAlign: textAlign,
      style: style,
    );
  }
}

/// Width from which a settings row keeps dsh's horizontal layout (text left,
/// control right). dsh's rows are drawn for the 564px content column of its
/// 800px settings panel; at phone widths its own CSS leaves the text column a
/// few dozen pixels wide, so a narrower row stacks its control under the text.
const double dshSettingsRowWide = 480;

/// A preference row of the settings General section: a title and a
/// description on the left, the control on the right, a hairline below (dsh
/// `FontSizeRow.module.css` `.row`, `PermissionRow.module.css` `.row`). The
/// column that stacks the rows drops the separator of the last one
/// ([separator]). Below [dshSettingsRowWide] the control moves under the text
/// ([stackedControl] widens it to the full width).
class DshSettingsRow extends StatelessWidget {
  const DshSettingsRow({
    super.key,
    required this.title,
    required this.description,
    required this.control,
    this.alert = false,
    this.separator,
    this.stackedControl = false,
  });

  final String title;
  final String description;

  /// Whether [description] reports a failure (announced as an alert).
  final bool alert;
  final Widget control;

  /// Whether to draw the hairline below; by default it is drawn unless the row
  /// ends its column ([DshColumnEnd]).
  final bool? separator;

  /// Whether the control takes the full width when the row stacks (a text
  /// field), instead of keeping its own width at the start.
  final bool stackedControl;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final line = separator ?? !DshColumnEnd.of(context);
    Widget text(EdgeInsetsGeometry padding) => Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DshLineText(
            title,
            style: theme
                .textStyle('--dsw-font-s-14')
                .copyWith(color: theme.labelPrimary),
          ),
          const SizedBox(height: 4),
          Semantics(
            liveRegion: alert,
            child: DshLineText(
              description,
              style: theme
                  .textStyle('--dsw-font-xxs-12')
                  .copyWith(
                    color: alert
                        ? theme.color('--dsw-alias-state-error-primary')
                        : theme.color('--dsw-alias-label-tertiary'),
                  ),
            ),
          ),
        ],
      ),
    );
    // A Container: the border takes room below the padding, as CSS's does.
    return DshContainer(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: line
            ? Border(
                bottom: BorderSide(
                  color: DshSurface.paint(
                    context,
                    theme.color('--dsw-alias-border-l2'),
                  ),
                  width: dshHairlineOf(context),
                ),
              )
            : null,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < dshSettingsRowWide) {
            return Column(
              crossAxisAlignment: stackedControl
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.start,
              children: [
                text(EdgeInsets.zero),
                const SizedBox(height: 12),
                control,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: text(const EdgeInsets.only(right: 48))),
              const SizedBox(width: 8),
              control,
            ],
          );
        },
      ),
    );
  }
}

/// The preset selector pill of a settings row (dsh `PermissionRow.module.css`
/// `.selector`): a 36px module-platform pill with the current label and a
/// chevron.
class DshSelectorPill extends StatefulWidget {
  const DshSelectorPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
  });

  final String label;

  /// Null disables the pill.
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  State<DshSelectorPill> createState() => _DshSelectorPillState();
}

class _DshSelectorPillState extends State<DshSelectorPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final enabled = widget.onPressed != null;
    final style = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(color: theme.labelPrimary);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: DshContainer(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: theme.cornerDecoration(
              theme.radiusMd,
              color: _hovered && enabled
                  ? blendLikeChromium(
                      theme.interactiveBgHover,
                      DshSurface.of(context),
                    )
                  : theme.color('--dsw-alias-bg-module-platform'),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: DshLineText(widget.label, style: style, maxLines: 1),
                ),
                const SizedBox(width: 12),
                DshIcon(DshIcons.chevronDown, color: theme.labelPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A px stepper (dsh `FontSizeRow.module.css`): a 36px pill with the centred
/// value, an arrow column anchored to its right edge that appears on hover or
/// focus, and a `px` label after it. [alwaysShowArrows] keeps the arrows
/// visible where there is no hover (touch).
class DshStepper extends StatefulWidget {
  const DshStepper({
    super.key,
    required this.value,
    required this.unit,
    required this.increaseLabel,
    required this.decreaseLabel,
    required this.onIncrease,
    required this.onDecrease,
    this.alwaysShowArrows = false,
    this.trailing,
    this.upKey,
    this.downKey,
  });

  final int value;
  final String unit;
  final String increaseLabel;
  final String decreaseLabel;

  /// Null disables the up arrow (the maximum is reached).
  final VoidCallback? onIncrease;

  /// Null disables the down arrow (the minimum is reached).
  final VoidCallback? onDecrease;
  final bool alwaysShowArrows;

  /// Control after the unit label (the disclosure button of the text row).
  final Widget? trailing;

  /// Keys of the two arrows (tests and the parity tool address them).
  final Key? upKey;
  final Key? downKey;

  @override
  State<DshStepper> createState() => _DshStepperState();
}

class _DshStepperState extends State<DshStepper> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final show = _hovered || widget.alwaysShowArrows;
    final valueStyle = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(
          color: theme.labelPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    final unitStyle = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(color: theme.labelSecondary);
    Widget arrow(
      DshIconData icon,
      String label,
      VoidCallback? onPressed,
      Key key,
    ) {
      return Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: DshContainer(
            width: 17,
            height: 12,
            alignment: Alignment.center,
            decoration: theme.cornerDecoration(
              theme.number('--dsw-radius-xs'),
              color: Color.alphaBlend(
                theme.color('--dsw-alias-bg-layer-1').withValues(alpha: 0.75),
                theme.color('--dsw-alias-bg-module-platform'),
              ),
            ),
            child: DshIcon(
              icon,
              size: 9,
              color: onPressed == null
                  ? theme.color('--dsw-alias-label-caption')
                  : theme.labelPrimary,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: DshContainer(
            constraints: const BoxConstraints(minWidth: 72),
            height: 36,
            decoration: theme.cornerDecoration(
              theme.radiusMd,
              color: theme.color('--dsw-alias-bg-module-platform'),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 72,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      child: DshLineText(
                        '${widget.value}',
                        style: valueStyle,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  child: Opacity(
                    opacity: show ? 1 : 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        arrow(
                          DshIcons.chevronUp,
                          widget.increaseLabel,
                          widget.onIncrease,
                          widget.upKey ?? const ValueKey('stepper-up'),
                        ),
                        const SizedBox(height: 2),
                        arrow(
                          DshIcons.chevronDown,
                          widget.decreaseLabel,
                          widget.onDecrease,
                          widget.downKey ?? const ValueKey('stepper-down'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        DshLineText(widget.unit, style: unitStyle, maxLines: 1),
        if (widget.trailing != null) ...[
          const SizedBox(width: 8),
          widget.trailing!,
        ],
      ],
    );
  }
}

/// A controlled two-state toggle using the published dsh `Switch` recipe.
class DshSwitch extends StatefulWidget {
  const DshSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;

  /// Null disables the switch.
  final ValueChanged<bool>? onChanged;

  /// Accessible name; owned by the render site.
  final String label;

  @override
  State<DshSwitch> createState() => _DshSwitchState();
}

class _DshSwitchState extends State<DshSwitch> {
  final FocusNode _focus = FocusNode(debugLabel: 'dsh switch');
  bool _focused = false;
  bool _focusVisible = false;

  bool get _enabled => widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    DshControlFocusModality.instance.acquire(_modalityChanged);
  }

  void _modalityChanged() {
    if (mounted) setState(() {});
  }

  void _activate() => widget.onChanged?.call(!widget.value);

  @override
  void didUpdateWidget(DshSwitch old) {
    super.didUpdateWidget(old);
    if (!_enabled) _focusVisible = false;
  }

  @override
  void dispose() {
    DshControlFocusModality.instance.release(_modalityChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final track = theme.color(
      widget.value
          ? DshSwitchRecipe.onTrackToken
          : DshSwitchRecipe.offTrackToken,
    );
    final thumb = theme.color(
      widget.value
          ? DshSwitchRecipe.onThumbToken
          : DshSwitchRecipe.offThumbToken,
    );
    final ringWidth = theme.number(DshSwitchRecipe.focusWidthToken);
    final ringColor =
        theme.colors[DshSwitchRecipe.focusToken] ??
        theme.color(DshSwitchRecipe.focusFallbackToken);
    final ringReach = ringWidth + DshSwitchRecipe.focusOffset;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: DshSwitchRecipe.transitionMs.round());
    return Semantics(
      container: true,
      toggled: widget.value,
      enabled: _enabled,
      focused: _focused,
      label: widget.label,
      onTap: _enabled ? _activate : null,
      onFocus: _enabled ? _focus.requestFocus : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: _focus,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onFocusChange: (value) => setState(() => _focused = value),
        onShowFocusHighlight: (value) => setState(() => _focusVisible = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? _activate : null,
          child: Opacity(
            opacity: _enabled ? 1 : DshSwitchRecipe.disabledOpacity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DshContainer(
                  width: DshSwitchRecipe.width,
                  height: DshSwitchRecipe.height,
                  padding: const EdgeInsets.all(DshSwitchRecipe.padding),
                  decoration: BoxDecoration(
                    color: track,
                    borderRadius: BorderRadius.circular(DshSwitchRecipe.radius),
                  ),
                  child: AnimatedAlign(
                    alignment: widget.value
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    duration: duration,
                    curve: Curves.ease,
                    child: DshContainer(
                      key: const ValueKey('dsh-switch-thumb'),
                      width: DshSwitchRecipe.thumbSize,
                      height: DshSwitchRecipe.thumbSize,
                      decoration: BoxDecoration(
                        color: thumb,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                if (_focusVisible &&
                    _enabled &&
                    !DshControlFocusModality.instance.pointerOwnsFocus)
                  Positioned(
                    left: -ringReach,
                    top: -ringReach,
                    right: -ringReach,
                    bottom: -ringReach,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: const ValueKey('dsh-switch-focus-ring'),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            DshSwitchRecipe.radius,
                          ),
                          border: Border.all(
                            color: ringColor,
                            width: ringWidth,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Source profiles for the primitive and the risk dialog's acknowledgement.
enum DshCheckboxProfile { primitive, riskAcknowledgement }

/// Controlled, labeled checkbox matching the published dsh profile.
class DshCheckbox extends StatefulWidget {
  const DshCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.profile = DshCheckboxProfile.primitive,
    this.autofocus = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  final DshCheckboxProfile profile;
  final bool autofocus;

  @override
  State<DshCheckbox> createState() => _DshCheckboxState();
}

class _DshCheckboxState extends State<DshCheckbox> {
  final FocusNode _focus = FocusNode(debugLabel: 'dsh checkbox');
  bool _focused = false;
  bool _focusVisible = false;
  bool _automaticFocusSuppressed = false;
  bool _boxHovered = false;
  bool _boxPressed = false;

  static final _automaticFocusNavigation = {
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  bool get _enabled => widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _automaticFocusSuppressed = widget.autofocus;
    DshControlFocusModality.instance.acquire(_modalityChanged);
    HardwareKeyboard.instance.addHandler(_automaticFocusKey);
  }

  void _modalityChanged() {
    if (mounted) setState(() {});
  }

  void _activate() => widget.onChanged?.call(!widget.value);

  bool _automaticFocusKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (_automaticFocusSuppressed &&
        _focus.hasPrimaryFocus &&
        event is KeyDownEvent &&
        _automaticFocusNavigation.contains(event.logicalKey) &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      setState(() => _automaticFocusSuppressed = false);
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_automaticFocusKey);
    DshControlFocusModality.instance.release(_modalityChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final risk = widget.profile == DshCheckboxProfile.riskAcknowledgement;
    final style = theme
        .fixedTextStyle(
          size: risk
              ? DshCheckboxRecipe.riskFontSize
              : DshCheckboxRecipe.fontSize,
          line: risk
              ? DshCheckboxRecipe.riskLineHeight
              : DshCheckboxRecipe.lineHeight,
        )
        .copyWith(
          color: theme.color(
            risk
                ? DshCheckboxRecipe.riskLabelToken
                : DshCheckboxRecipe.labelToken,
          ),
        );
    final accent = theme.color(
      risk ? DshCheckboxRecipe.riskAccentToken : DshCheckboxRecipe.accentToken,
    );
    final ringWidth = theme.number(DshCheckboxRecipe.focusWidthToken);
    final ringColor =
        theme.colors[DshCheckboxRecipe.focusToken] ??
        theme.color(DshCheckboxRecipe.focusFallbackToken);
    final ringReach = ringWidth + DshCheckboxRecipe.focusOffset;
    final nativeState = !_enabled
        ? _CheckboxPaintState.disabled
        : _boxPressed
        ? _CheckboxPaintState.pressed
        : _boxHovered
        ? _CheckboxPaintState.hover
        : _CheckboxPaintState.normal;
    final box = Stack(
      clipBehavior: Clip.none,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _boxHovered = true),
          onExit: (_) => setState(() => _boxHovered = false),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => setState(() => _boxPressed = true),
            onPointerUp: (_) => setState(() => _boxPressed = false),
            onPointerCancel: (_) => setState(() => _boxPressed = false),
            child: SizedBox(
              key: const ValueKey('dsh-checkbox-box'),
              width: DshCheckboxRecipe.size,
              height: DshCheckboxRecipe.size,
              child: CustomPaint(
                painter: _DshCheckboxPainter(
                  checked: widget.value,
                  dark: theme.brightness == Brightness.dark,
                  state: nativeState,
                  accent: accent,
                ),
              ),
            ),
          ),
        ),
        if (_focusVisible &&
            _enabled &&
            !_automaticFocusSuppressed &&
            !DshControlFocusModality.instance.pointerOwnsFocus)
          Positioned(
            left: -ringReach,
            top: -ringReach,
            right: -ringReach,
            bottom: -ringReach,
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('dsh-checkbox-focus-ring'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: ringColor, width: ringWidth),
                ),
              ),
            ),
          ),
      ],
    );
    return Semantics(
      container: true,
      checked: widget.value,
      enabled: _enabled,
      focused: _focused,
      label: widget.label,
      onTap: _enabled ? _activate : null,
      onFocus: _enabled ? _focus.requestFocus : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: _focus,
        autofocus: widget.autofocus,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onFocusChange: (value) => setState(() {
          _focused = value;
          if (!value) _automaticFocusSuppressed = false;
        }),
        onShowFocusHighlight: (value) => setState(() => _focusVisible = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter):
              DoNothingAndStopPropagationIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter):
              DoNothingAndStopPropagationIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? _activate : null,
          child: Opacity(
            opacity: _enabled || risk ? 1 : DshCheckboxRecipe.disabledOpacity,
            child: Row(
              mainAxisSize: risk ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: risk
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: risk ? DshCheckboxRecipe.riskInputTop : 0,
                  ),
                  child: box,
                ),
                SizedBox(
                  width: risk
                      ? DshCheckboxRecipe.riskGap
                      : DshCheckboxRecipe.gap,
                ),
                Flexible(child: DshChromeText(widget.label, style: style)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _CheckboxPaintState { normal, hover, pressed, disabled }

/// Geometry follows Chromium 145's native control (The Chromium Authors;
/// license in tool/design-system/upstream/chromium/LICENSE); the palette is
/// sampled from that browser at both supported reference densities.
class _DshCheckboxPainter extends CustomPainter {
  const _DshCheckboxPainter({
    required this.checked,
    required this.dark,
    required this.state,
    required this.accent,
  });

  final bool checked, dark;
  final _CheckboxPaintState state;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final disabled = state == _CheckboxPaintState.disabled;
    final fill = Color(
      dark
          ? (disabled
                ? DshCheckboxNativeRecipe.darkOffDisabledFill
                : DshCheckboxNativeRecipe.darkOffFill)
          : (disabled
                ? DshCheckboxNativeRecipe.lightOffDisabledFill
                : DshCheckboxNativeRecipe.lightOffFill),
    );
    final edge = Color(switch ((dark, state)) {
      (false, _CheckboxPaintState.normal) =>
        DshCheckboxNativeRecipe.lightOffBorderNormal,
      (false, _CheckboxPaintState.hover) =>
        DshCheckboxNativeRecipe.lightOffBorderHover,
      (false, _CheckboxPaintState.pressed) =>
        DshCheckboxNativeRecipe.lightOffBorderPressed,
      (false, _CheckboxPaintState.disabled) =>
        DshCheckboxNativeRecipe.lightOffBorderDisabled,
      (true, _CheckboxPaintState.normal) =>
        DshCheckboxNativeRecipe.darkOffBorderNormal,
      (true, _CheckboxPaintState.hover) =>
        DshCheckboxNativeRecipe.darkOffBorderHover,
      (true, _CheckboxPaintState.pressed) =>
        DshCheckboxNativeRecipe.darkOffBorderPressed,
      (true, _CheckboxPaintState.disabled) =>
        DshCheckboxNativeRecipe.darkOffBorderDisabled,
    });
    final mark = Color(
      dark
          ? (disabled
                ? DshCheckboxNativeRecipe.darkOnDisabledMark
                : DshCheckboxNativeRecipe.darkOnMark)
          : (disabled
                ? DshCheckboxNativeRecipe.lightOnDisabledMark
                : DshCheckboxNativeRecipe.lightOnMark),
    );
    final Color checkedFill;
    if (disabled) {
      checkedFill = Color(
        dark
            ? DshCheckboxNativeRecipe.darkOnDisabledFill
            : DshCheckboxNativeRecipe.lightOnDisabledFill,
      );
    } else if (state == _CheckboxPaintState.normal) {
      checkedFill = accent;
    } else {
      final hsl = HSLColor.fromColor(accent);
      final direction =
          (state == _CheckboxPaintState.pressed ? 1 : -1) * (dark ? -1 : 1);
      checkedFill = hsl
          .withLightness(
            (hsl.lightness +
                    direction * DshCheckboxNativeRecipe.accentLightnessAdjust)
                .clamp(0, 1),
          )
          .toColor();
    }
    final rect = Offset.zero & size;
    const radius = Radius.circular(DshCheckboxNativeRecipe.radius);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(
          DshCheckboxNativeRecipe.borderWidth *
              DshCheckboxNativeRecipe.backgroundInsetRatio,
        ),
        radius,
      ),
      paint..color = fill,
    );
    if (checked) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        paint..color = checkedFill,
      );
      final path = Path()
        ..moveTo(
          size.width * DshCheckboxNativeRecipe.checkStartX,
          size.height * DshCheckboxNativeRecipe.checkStartY,
        )
        ..relativeLineTo(
          size.width * DshCheckboxNativeRecipe.checkStepX,
          size.height * DshCheckboxNativeRecipe.checkStepY,
        )
        ..lineTo(
          size.width * (1 - DshCheckboxNativeRecipe.checkEndXFromRight),
          size.height * DshCheckboxNativeRecipe.checkEndY,
        );
      canvas.drawPath(
        path,
        paint
          ..color = mark
          ..style = PaintingStyle.stroke
          ..strokeWidth =
              size.height * DshCheckboxNativeRecipe.checkStrokeRatio,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.deflate(DshCheckboxNativeRecipe.borderWidth / 2),
          radius,
        ),
        paint
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = DshCheckboxNativeRecipe.borderWidth,
      );
    }
  }

  @override
  bool shouldRepaint(_DshCheckboxPainter old) =>
      checked != old.checked ||
      dark != old.dark ||
      state != old.state ||
      accent != old.accent;
}

/// Rebuilds [builder] whenever [changes] emits: the bridge between a model's
/// synchronous change stream (an `Observable`) and a widget that reads the
/// model's current value in [builder].
class DshWatch extends StatelessWidget {
  const DshWatch({super.key, required this.changes, required this.builder});

  final Stream<Object?> changes;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: changes,
    builder: (context, _) => builder(context),
  );
}

/// Whether the composer's tool row is narrow (dsh's `@container (max-width:
/// 460px)` rule): a control that carries a glyph then drops its text label.
class DshComposerRow extends InheritedWidget {
  const DshComposerRow({
    super.key,
    required this.compact,
    required super.child,
  });

  final bool compact;

  /// The composer row's compactness at [context] (false outside a composer).
  static bool compactOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DshComposerRow>()?.compact ??
      false;

  @override
  bool updateShouldNotify(DshComposerRow oldWidget) =>
      oldWidget.compact != compact;
}
