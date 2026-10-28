import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_feature_model_selection/testing.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> reportedModelCases = {
  'reported-model.menu': ParityCase(
    widgets: const ['dsh_feature_model_selection:ModelSeat'],
    framed: false,
    build: (ctx) {
      final chrome = ShellChrome(
        platform: ctx.props['platform'] == 'darwin'
            ? ShellPlatform.darwin
            : ShellPlatform.other,
      );
      return ShellScope(
        chrome: chrome,
        child: FrameInsetsScope(
          insets: frameInsetsFor(chrome, sidebarCollapsed: false),
          child: ColoredBox(
            color: ctx.theme.bgBase,
            child: SizedBox.expand(
              key: const ValueKey('reported-model-viewport'),
              child: ReportedModelFixture(
                i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
              ),
            ),
          ),
        ),
      );
    },
  ),
};
