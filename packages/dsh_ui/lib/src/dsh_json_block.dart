import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dsh_disclosure_reset.dart';
import 'dsh_corners.dart';
import 'dsh_snapped_box.dart';
import 'dsh_pixel_snap.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// The upstream JsonBlock fallback; foreign payloads stay available without
/// eagerly formatting or materializing their whole body.
class DshJsonBlock extends StatefulWidget {
  const DshJsonBlock({
    super.key,
    required this.label,
    required this.payload,
    required this.truncatedLabel,
    this.defaultOpen = false,
  });
  final String label;
  final Object? payload;
  final String Function(int total) truncatedLabel;
  final bool defaultOpen;
  @override
  State<DshJsonBlock> createState() => _DshJsonBlockState();
}

class _DshJsonBlockState extends State<DshJsonBlock> {
  late bool _open = widget.defaultOpen;
  String get body {
    String value;
    try {
      value = const JsonEncoder.withIndent('  ').convert(widget.payload);
    } on Object {
      value = '${widget.payload}';
    }
    return value.length > 20000
        ? '${value.substring(0, 20000)}\n${widget.truncatedLabel(value.length)}'
        : value;
  }

  void toggle() {
    DshDisclosureChange(!_open, context).dispatch(context);
    setState(() => _open = !_open);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            excludeSemantics: true,
            onTap: toggle,
            expanded: _open,
            label: widget.label,
            child: FocusableActionDetector(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              },
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    toggle();
                    return null;
                  },
                ),
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: toggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: DshChromeText(
                    '${_open ? '▾' : '▸'} ${widget.label}',
                    style: theme
                        .fixedCodeStyle(size: 12, line: 18)
                        .copyWith(color: theme.labelSecondary),
                  ),
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: DshDecoratedBox(
                  decoration: theme.cornerDecoration(
                    theme.radiusLg,
                    color: theme.color('--dsw-alias-markdown-code-block'),
                    borderColor: theme.color('--dsw-alias-border-l1'),
                    borderWidth: dshBorderWidthOf(context, .5),
                  ),
                  child: SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.all(8),
                    child: DshChromeText(
                      body,
                      style: theme
                          .fixedCodeStyle(size: 11, line: 16)
                          .copyWith(color: theme.labelPrimary),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
