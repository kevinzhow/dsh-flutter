import 'package:flutter/material.dart'
    show TextField, InputBorder, InputDecoration;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';

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
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.color('--dsw-specific-input-major'),
            border: Border.all(color: borderColor, width: 0.5),
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
