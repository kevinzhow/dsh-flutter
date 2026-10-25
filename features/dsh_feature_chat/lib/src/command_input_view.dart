import 'dart:math' as math;

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

class GoalCommandInputView extends StatelessWidget {
  const GoalCommandInputView({
    super.key,
    required this.data,
    required this.i18n,
  });
  final CommandInputData data;
  final DshI18n i18n;
  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Semantics(
      label: i18n.t('goal', 'commandInput.aria'),
      container: true,
      child: Align(
        heightFactor: 1,
        alignment: AlignmentDirectional.centerEnd,
        child: LayoutBuilder(
          builder: (context, constraints) => ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(
                DshChatContent.of(context) * .702,
                constraints.maxWidth * .82,
              ),
            ),
            child: DshDecoratedBox(
              decoration: theme.cornerDecoration(
                theme.radiusXl,
                color: theme.color('--dsw-specific-bubble'),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text.rich(
                  TextSpan(
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .copyWith(color: theme.labelPrimary, height: 22 / 14),
                    children: [
                      const WidgetSpan(child: SizedBox(width: 2)),
                      TextSpan(
                        text: '/goal',
                        style: theme
                            .fixedCodeStyle(size: 14, line: 22)
                            .copyWith(
                              color: theme.color(
                                '--dsw-alias-state-business-primary',
                              ),
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const WidgetSpan(child: SizedBox(width: 2)),
                      TextSpan(text: data.text.substring('/goal'.length)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
