import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// The expanded input/output card (dsh `.ioCard`): the code-block surface with
/// an IN section and an OUT section separated by a hairline, each capped at
/// 150px and scrolling alone.
class IoCard extends StatelessWidget {
  const IoCard({
    super.key,
    required this.inputLabel,
    required this.outputLabel,
    this.input,
    this.output,
    this.error = false,
    this.commandInput = false,
  });

  final String inputLabel;
  final String outputLabel;
  final String? input;
  final String? output;
  final bool error;

  /// Render the input as a wrapped command (background shell launches).
  final bool commandInput;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final style = theme.textStyle('--dsw-font-markdown-code-block-small');
    Widget section(String label, String text, Color color) => ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 150),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              DshChromeText(
                label,
                style: style.copyWith(
                  color: theme.color('--dsw-alias-label-caption'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: DshChromeText(text, style: style.copyWith(color: color)),
              ),
            ],
          ),
        ),
      ),
    );
    return DshContainer(
      key: const ValueKey('io-card'),
      decoration: context.dshOutlined(
        theme.radiusLg,
        fill: theme.color('--dsw-alias-markdown-code-block'),
        border: theme.color('--dsw-alias-border-l1'),
      ),
      child: theme.clipCorners(
        theme.radiusLg,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (input != null)
              section(inputLabel, input!, theme.labelSecondary),
            if (input != null && output != null)
              Container(
                height: dshHairlineOf(context),
                color: theme.color('--dsw-alias-border-l2'),
              ),
            if (output != null)
              section(
                outputLabel,
                output!,
                error
                    ? theme.color('--dsw-alias-state-error-primary')
                    : theme.labelSecondary,
              ),
          ],
        ),
      ),
    );
  }
}
