import 'package:flutter/material.dart'
    show TextField, InputBorder, InputDecoration, Material, MaterialType;
import 'package:flutter/services.dart'
    show TextEditingValue, TextInputAction, TextInputFormatter;
import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_pixel_snap.dart';
import 'dsh_recipes.g.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// Token-styled text input (fill `--dsw-specific-input-major`, hairline
/// `--dsw-alias-border-l3`, radius `--dsw-radius-lg`).
class DshTextField extends StatelessWidget {
  const DshTextField({
    super.key,
    required this.controller,
    this.placeholder,
    this.focusNode,
    this.onSubmitted,
    this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
    this.obscure = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.errorText,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String? placeholder;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final int minLines;
  final int? maxLines;
  final bool obscure;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? errorText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final style = theme
        .textStyle('--dsw-font-base-16')
        .copyWith(color: theme.labelPrimary);
    final hasError = errorText != null;
    final borderColor = hasError
        ? theme.color('--dsw-alias-state-error-primary')
        : theme.borderL3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DshDecoratedBox(
          decoration: BoxDecoration(
            color: theme.color('--dsw-specific-input-major'),
            border: Border.all(
              color: borderColor,
              width: dshHairlineOf(context),
            ),
            borderRadius: BorderRadius.circular(theme.radiusLg),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DshSpace.md,
              vertical: DshSpace.sm,
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              autofocus: autofocus,
              obscureText: obscure,
              minLines: obscure ? 1 : minLines,
              maxLines: obscure ? 1 : maxLines,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              style: style,
              cursorColor: theme.focusRingColor,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: placeholder,
                hintStyle: style.copyWith(
                  color: theme.color('--dsw-alias-label-tertiary'),
                ),
              ),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: DshSpace.xs),
            child: DshChromeText(
              errorText!,
              style: theme
                  .textStyle('--dsw-font-xxs-12')
                  .copyWith(
                    color: theme.color('--dsw-alias-state-error-primary'),
                  ),
            ),
          ),
      ],
    );
  }
}

/// The published single-line `Input` atom. The optional [icon] precedes the
/// editable control; [onCommit] is useful for settings which persist on blur.
/// Supply [controller] for a controlled input, or [value] for an internally
/// owned controller which resets when the persisted value changes.
enum DshInputProfile { standard, modelSearch }

class DshInput extends StatefulWidget {
  const DshInput({
    super.key,
    this.controller,
    this.focusNode,
    this.value = '',
    this.onCommit,
    this.onChanged,
    this.onSubmitted,
    this.placeholder,
    this.semanticLabel,
    this.icon,
    this.maxLength,
    this.keyboardType,
    this.enabled = true,
    this.autofocus = false,
    this.profile = DshInputProfile.standard,
    this.reserveSearchClear = false,
  }) : assert(maxLength == null || maxLength >= 0);

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String value;
  final ValueChanged<String>? onCommit, onChanged, onSubmitted;
  final String? placeholder, semanticLabel;
  final Widget? icon;
  final int? maxLength;
  final TextInputType? keyboardType;
  final bool enabled, autofocus;
  final DshInputProfile profile;
  final bool reserveSearchClear;

  @override
  State<DshInput> createState() => _DshInputState();
}

class _DshInputState extends State<DshInput> {
  late TextEditingController _controller;
  late FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? TextEditingController(text: widget.value);
    _focus = widget.focusNode ?? FocusNode();
    _focused = _focus.hasFocus;
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    final focused = _focus.hasFocus;
    if (focused == _focused) return;
    setState(() => _focused = focused);
    if (!focused) widget.onCommit?.call(_controller.text);
  }

  @override
  void didUpdateWidget(DshInput old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller == null) _controller.dispose();
      _controller =
          widget.controller ?? TextEditingController(text: widget.value);
    } else if (widget.controller == null &&
        old.value != widget.value &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
    if (old.focusNode != widget.focusNode) {
      _focus.removeListener(_focusChanged);
      if (old.focusNode == null) _focus.dispose();
      _focus = widget.focusNode ?? FocusNode();
      _focused = _focus.hasFocus;
      _focus.addListener(_focusChanged);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    if (widget.focusNode == null) _focus.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final modelSearch = widget.profile == DshInputProfile.modelSearch;
    final style =
        (modelSearch
                ? theme.fixedTextStyle(
                    size: DshModelMenuRecipe.searchFontSize,
                    line: DshModelMenuRecipe.searchFontSize,
                  )
                : theme.textStyle(DshInputRecipe.fontToken))
            .copyWith(
              color: theme.color(DshInputRecipe.labelToken),
              height: modelSearch
                  ? kTextHeightNone
                  : DshInputRecipe.lineHeight / DshInputRecipe.fontSize,
            );
    final border = modelSearch
        ? 0.0
        : dshBorderWidthOf(context, DshInputRecipe.borderWidth);
    final fill = modelSearch
        ? const Color(0)
        : theme.color(DshInputRecipe.fillToken);
    // The reference leaves Chromium's input `padding: 1px 2px` intact. Its
    // block axis is centered by the wrapper; these are its inline insets.
    const browserInputInlineInset = 2.0;
    return Semantics(
      label: widget.semanticLabel,
      textField: true,
      enabled: widget.enabled,
      child: ExcludeFocus(
        excluding: !widget.enabled,
        child: IgnorePointer(
          ignoring: !widget.enabled,
          child: Container(
            height: modelSearch ? null : DshInputRecipe.height + 2 * border,
            padding: modelSearch
                ? EdgeInsets.fromLTRB(
                    DshModelMenuRecipe.searchHorizontalPadding,
                    DshModelMenuRecipe.searchVerticalPadding,
                    widget.reserveSearchClear
                        ? DshModelMenuRecipe.searchQueryRightPadding
                        : DshModelMenuRecipe.searchHorizontalPadding,
                    DshModelMenuRecipe.searchVerticalPadding,
                  )
                : const EdgeInsets.symmetric(
                    horizontal: DshInputRecipe.padding,
                  ),
            decoration: theme.cornerDecoration(
              theme.number(
                modelSearch
                    ? DshModelMenuRecipe.radiusToken
                    : DshInputRecipe.radiusToken,
              ),
              color: fill,
              borderColor: modelSearch
                  ? null
                  : _focused
                  ? theme.color(DshInputRecipe.focusBorderToken)
                  : DshSurface.paint(
                      context,
                      theme.color(DshInputRecipe.borderToken),
                      over: fill,
                    ),
              borderWidth: border,
            ),
            alignment: Alignment.center,
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  SizedBox.square(
                    dimension: DshInputRecipe.iconSize,
                    child: IconTheme.merge(
                      data: IconThemeData(
                        size: DshInputRecipe.iconSize,
                        color: theme.color(DshInputRecipe.iconToken),
                      ),
                      child: widget.icon!,
                    ),
                  ),
                  const SizedBox(width: DshInputRecipe.gap),
                ],
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: modelSearch ? 0 : browserInputInlineInset,
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _controller,
                            builder: (context, value, _) =>
                                value.text.isEmpty && widget.placeholder != null
                                ? IgnorePointer(
                                    child: DshChromeText(
                                      widget.placeholder!,
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: style.copyWith(
                                        color: theme.color(
                                          DshInputRecipe.placeholderToken,
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          EditableText(
                            controller: _controller,
                            focusNode: _focus,
                            readOnly: !widget.enabled,
                            autofocus: widget.autofocus,
                            maxLines: 1,
                            style: style,
                            cursorColor: theme.focusRingColor,
                            backgroundCursorColor: theme.labelSecondary,
                            selectionColor: theme.focusRingColor.withValues(
                              alpha: 0.3,
                            ),
                            keyboardType: widget.keyboardType,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            enableSuggestions: false,
                            inputFormatters: widget.maxLength == null
                                ? null
                                : [_InputMaxLength(widget.maxLength!)],
                            onChanged: widget.onChanged,
                            onSubmitted: (text) {
                              if (widget.onCommit != null) _focus.unfocus();
                              widget.onSubmitted?.call(text);
                            },
                          ),
                        ],
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

class _InputMaxLength extends TextInputFormatter {
  _InputMaxLength(this.max);
  final int max;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final old = oldValue.text, next = newValue.text;
    if (next.length <= max || next == old || next.length < old.length) {
      return newValue;
    }
    var prefix = 0;
    while (prefix < old.length &&
        prefix < next.length &&
        old.codeUnitAt(prefix) == next.codeUnitAt(prefix)) {
      prefix++;
    }
    // Do not split a surrogate pair when two different characters share its
    // first code unit.
    if (prefix > 0 &&
        prefix < old.length &&
        prefix < next.length &&
        _isHighSurrogate(next.codeUnitAt(prefix - 1)) &&
        (_isLowSurrogate(old.codeUnitAt(prefix)) ||
            _isLowSurrogate(next.codeUnitAt(prefix)))) {
      prefix--;
    }
    var suffix = 0;
    while (suffix < old.length - prefix &&
        suffix < next.length - prefix &&
        old.codeUnitAt(old.length - suffix - 1) ==
            next.codeUnitAt(next.length - suffix - 1)) {
      suffix++;
    }
    if (suffix > 0 &&
        old.length - suffix > 0 &&
        next.length - suffix > 0 &&
        _isLowSurrogate(next.codeUnitAt(next.length - suffix)) &&
        (_isHighSurrogate(old.codeUnitAt(old.length - suffix - 1)) ||
            _isHighSurrogate(next.codeUnitAt(next.length - suffix - 1)))) {
      suffix--;
    }
    final insertionEnd = next.length - suffix;
    final available = max - prefix - suffix;
    if (available < 0) return oldValue;
    var keep = available.clamp(0, insertionEnd - prefix);
    if (keep > 0 &&
        prefix + keep < insertionEnd &&
        _isHighSurrogate(next.codeUnitAt(prefix + keep - 1)) &&
        _isLowSurrogate(next.codeUnitAt(prefix + keep))) {
      keep--;
    }
    final result =
        next.substring(0, prefix + keep) + next.substring(insertionEnd);
    final removed = insertionEnd - prefix - keep;
    int adjusted(int offset) {
      if (offset < 0 || offset <= prefix) return offset;
      if (offset >= insertionEnd) return offset - removed;
      return offset.clamp(prefix, prefix + keep);
    }

    final selection = newValue.selection;
    return newValue.copyWith(
      text: result,
      selection: selection.copyWith(
        baseOffset: adjusted(selection.baseOffset),
        extentOffset: adjusted(selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }

  static bool _isHighSurrogate(int value) => value >= 0xd800 && value <= 0xdbff;
  static bool _isLowSurrogate(int value) => value >= 0xdc00 && value <= 0xdfff;
}
