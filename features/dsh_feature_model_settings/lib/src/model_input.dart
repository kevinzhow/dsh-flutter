import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart'
    show TextField, InputDecoration, InputBorder, Material, MaterialType;
import 'package:flutter/widgets.dart';

/// ModelsSection.module.css's 32px input. Credentials never enable keyboard
/// suggestions, including while their draft is revealed.
class ModelSettingsInput extends StatefulWidget {
  const ModelSettingsInput({
    super.key,
    required this.controller,
    this.placeholder,
    this.errorText,
    this.semanticLabel,
    this.obscure = false,
    this.enabled = true,
    this.secret = false,
    this.onChanged,
    this.trailing,
  });
  final TextEditingController controller;
  final String? placeholder, errorText, semanticLabel;
  final bool obscure, enabled, secret;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;
  @override
  State<ModelSettingsInput> createState() => _ModelSettingsInputState();
}

class _ModelSettingsInputState extends State<ModelSettingsInput> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final style = theme
        .textStyle('--dsw-font-s-14')
        .copyWith(color: theme.labelPrimary);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          onFocusChange: (v) {
            if (mounted) setState(() => focused = v);
          },
          child: Material(
            type: MaterialType.transparency,
            child: DshDecoratedBox(
              decoration: BoxDecoration(
                color: theme.color('--dsw-alias-bg-layer-1'),
                borderRadius: BorderRadius.circular(theme.radiusMd),
                border: Border.all(
                  width: .5,
                  color: theme.color(
                    widget.errorText != null
                        ? '--dsw-alias-state-error-primary'
                        : focused
                        ? '--dsw-alias-state-business-primary'
                        : '--dsw-alias-border-l4',
                  ),
                ),
              ),
              child: SizedBox(
                height: 32,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: MergeSemantics(
                          child: Semantics(
                            label: widget.semanticLabel,
                            textField: true,
                            obscured: widget.obscure,
                            child: TextField(
                              controller: widget.controller,
                              enabled: widget.enabled,
                              obscureText: widget.obscure,
                              enableSuggestions: !widget.secret,
                              autocorrect: !widget.secret,
                              style: style,
                              onChanged: widget.onChanged,
                              cursorColor: theme.focusRingColor,
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.only(
                                  right: widget.trailing == null ? 0 : 30,
                                ),
                                hintText: widget.placeholder,
                                hintStyle: style.copyWith(
                                  color: theme.color(
                                    '--dsw-alias-label-dimmed',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.trailing != null)
                      Positioned(
                        right: 1,
                        top: 1,
                        bottom: 1,
                        width: 32,
                        child: widget.trailing!,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              liveRegion: true,
              child: Text(
                widget.errorText!,
                style: theme
                    .textStyle('--dsw-font-xxs-12')
                    .copyWith(
                      color: theme.color('--dsw-alias-state-error-primary'),
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

const _eyeContour =
    'M1.5 8C2.9 5.25 5.25 3.5 8 3.5C10.75 3.5 13.1 5.25 14.5 8C13.1 10.75 10.75 12.5 8 12.5C5.25 12.5 2.9 10.75 1.5 8Z';
const modelKeyEye = DshIconData(
  viewBox: 16,
  size: 16,
  strokeWidth: 1.3,
  shapes: [
    DshIconShape(
      '${_eyeContour}M10 8C10 9.1 9.1 10 8 10C6.9 10 6 9.1 6 8C6 6.9 6.9 6 8 6C9.1 6 10 6.9 10 8Z',
      cap: DshIconCap.round,
    ),
  ],
);
const modelKeyEyeOff = DshIconData(
  viewBox: 16,
  size: 16,
  strokeWidth: 1.3,
  shapes: [
    DshIconShape('${_eyeContour}M2.5 2.5L13.5 13.5', cap: DshIconCap.round),
  ],
);
