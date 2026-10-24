import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// dsh's `.hint` of the chat view (`ChatView.module.css`): the line shown above
/// the (still empty) flow while a session opens, `chat.loadingHistory`. The
/// tertiary label colour, the secondary content size (13px).
class LoadingHint extends StatelessWidget {
  const LoadingHint(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshChromeText(
      label,
      // `.hint`: 13px on an 18px line.
      style: theme
          .textStyle('--dsw-font-xs-13')
          .copyWith(
            color: theme.color('--dsw-alias-label-tertiary'),
            height: 18 / 13,
          ),
    );
  }
}
