import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart'
    show TextEditingValue, TextInputAction, TextInputFormatter;
import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_diff_block.dart' show blendLikeChromium;
import 'dsh_icon.dart';
import 'dsh_icon_data.dart';
import 'dsh_icons.g.dart';
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
    return DshChromeBaseline(
      style: style,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        textAlign: textAlign,
        style: style,
        strutStyle: dshStrut(style),
      ),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: line
            ? Border(
                bottom: BorderSide(
                  color: theme.color('--dsw-alias-border-l2'),
                  width: dshHairline,
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
          child: Container(
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
          child: Container(
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
          child: Container(
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

/// A two-state toggle (dsh `Switch`): a 36x20 capsule with a 16px thumb.
class DshSwitch extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final enabled = onChanged != null;
    final track = value
        ? theme.color('--dsw-alias-brand-primary')
        : theme.color('--dsw-alias-border-l3');
    final thumb = value
        ? theme.color('--dsw-alias-label-primary-foreground')
        : theme.color('--dsw-alias-switch-thumb');
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            width: 36,
            height: 20,
            padding: const EdgeInsets.all(2),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: thumb, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// The single-line text input atom of dsh (`Input`): 32px, a 0.5px
/// `border-l4` stroke on `bg-layer-1`, `md` corners; the stroke turns to the
/// business colour while focused. [onCommit] runs on blur or Enter.
class DshFieldInput extends StatefulWidget {
  const DshFieldInput({
    super.key,
    required this.value,
    required this.onCommit,
    this.placeholder,
    this.semanticLabel,
    this.maxLength,
    this.enabled = true,
  });

  /// The persisted value the field shows; a change resets the field (dsh
  /// keys the input on it).
  final String value;
  final ValueChanged<String> onCommit;
  final String? placeholder;
  final String? semanticLabel;
  final int? maxLength;
  final bool enabled;

  @override
  State<DshFieldInput> createState() => _DshFieldInputState();
}

class _DshFieldInputState extends State<DshFieldInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      final focused = _focus.hasFocus;
      if (focused == _focused) return;
      setState(() => _focused = focused);
      if (!focused) widget.onCommit(_controller.text);
    });
  }

  @override
  void didUpdateWidget(DshFieldInput old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final style = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(color: theme.labelPrimary);
    return Semantics(
      label: widget.semanticLabel,
      textField: true,
      child: Container(
        // dsh's input is content-box: 32px of content inside a 1px border.
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: theme.cornerDecoration(
          theme.radiusMd,
          color: theme.color('--dsw-alias-bg-layer-1'),
          borderColor: _focused
              ? theme.focusRingColor
              : theme.color('--dsw-alias-border-l4'),
          borderWidth: dshHairline,
        ),
        alignment: Alignment.center,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // The placeholder shows while the field is empty (dsh `::placeholder`).
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) =>
                    value.text.isEmpty && widget.placeholder != null
                    ? IgnorePointer(
                        child: Text(
                          widget.placeholder!,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: style.copyWith(
                            color: theme.color('--dsw-alias-label-dimmed'),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              EditableText(
                controller: _controller,
                focusNode: _focus,
                readOnly: !widget.enabled,
                maxLines: 1,
                style: style,
                cursorColor: theme.focusRingColor,
                backgroundCursorColor: theme.labelSecondary,
                selectionColor: theme.focusRingColor.withValues(alpha: 0.3),
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: widget.maxLength == null
                    ? null
                    : [_MaxLength(widget.maxLength!)],
                onSubmitted: (_) => _focus.unfocus(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaxLength extends TextInputFormatter {
  _MaxLength(this.max);
  final int max;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.text.length <= max ? newValue : oldValue;
}

/// A checkbox with its label (dsh `Checkbox`, the acknowledgement of the risk
/// dialog): a 16px box in the brand colour.
class DshCheckbox extends StatelessWidget {
  const DshCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final enabled = onChanged != null;
    final style = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(color: theme.labelPrimary);
    return Semantics(
      checked: value,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value
                        ? theme.color('--dsw-alias-brand-primary')
                        : null,
                    border: Border.all(
                      color: value
                          ? theme.color('--dsw-alias-brand-primary')
                          : theme.borderL3,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: value
                      ? DshIcon(
                          DshIcons.check,
                          size: 12,
                          color: theme.labelPrimaryForeground,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: style)),
            ],
          ),
        ),
      ),
    );
  }
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
