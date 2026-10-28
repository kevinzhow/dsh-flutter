import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

const _stats = SessionStats(
  turns: 231,
  steps: 2901,
  llmMs: 37673000,
  toolMs: 9394000,
  ttftMs: 95000,
  ttftSteps: 10,
  decodeMs: 10000,
  decodeTokens: 1460,
);
const _usage = TokenUsage(
  uncachedInputTokens: 9000000,
  cacheReadTokens: 150000000,
  cacheWriteTokens: 1000000,
  outputTokens: 1600000,
);

Widget _build(ParityContext ctx) {
  final locale = DshI18n(DshLocale.fromTag(ctx.locale));
  final pill = ctx.props['stat'] == 'usage'
      ? usagePill(_usage, locale)!
      : activityPill(_stats, locale)!;
  return ShellScope(
    chrome: ShellChrome(
      platform: ctx.props['platform'] == 'darwin'
          ? ShellPlatform.darwin
          : ShellPlatform.other,
    ),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 100,
          height: 44,
          child: ColoredBox(color: ctx.theme.interactiveBgHover),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 188,
          height: 44,
          child: ColoredBox(
            color: ctx.theme.color('--dsw-specific-bubble-highlight'),
          ),
        ),
        Positioned(
          top: 112,
          child: DshChromeText(
            'Synthetic conversation · ${ctx.locale.startsWith('zh') ? '验证与提交' : 'Validation and delivery'}',
            style: ctx.theme
                .fixedTextStyle(size: 14, line: 22)
                .copyWith(color: ctx.theme.labelPrimary),
          ),
        ),
        Positioned(
          top: 210,
          child: DshChromeText(
            'Session projection data · 231 turns · 2901 steps',
            style: ctx.theme
                .fixedTextStyle(size: 14, line: 22)
                .copyWith(color: ctx.theme.labelPrimary),
          ),
        ),
        Positioned(
          bottom: 0,
          left: ctx.props['edge'] == true ? null : 0,
          right: ctx.props['edge'] == true ? 0 : null,
          child: parityItem('stats-trigger', StatPillView(pill: pill)),
        ),
      ],
    ),
  );
}

final Map<String, ParityCase> reportedStatsCases = {
  'reported.stats': ParityCase(
    widgets: const [
      'dsh_feature_chat:StatPillView',
      'dsh_ui:DshStatPanel',
      'dsh_ui:DshPopoverSurface',
    ],
    build: _build,
  ),
};
