import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import '../helpers/reported_sidebar_fixture.dart';

final Map<String, ParityCase> reportedSidebarCases = {
  'reported-sidebar.root': ParityCase(
    widgets: const [
      'dsh_feature_sidebar:SidebarRoot',
      'dsh_feature_session:WorkspaceBrowser',
      'dsh_feature_settings:SettingsLauncherRow',
    ],
    framed: false,
    build: (ctx) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        key: const ValueKey('reported-sidebar-frame'),
        width: (ctx.props['width'] as num?)?.toDouble() ?? 280,
        height: (ctx.props['height'] as num?)?.toDouble() ?? 800,
        child: ReportedSidebarFixture(
          i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
          platform: ctx.props['platform'] == 'linux'
              ? ShellPlatform.other
              : ShellPlatform.darwin,
          collapsed: ctx.props['collapsed'] == true,
          width: (ctx.props['width'] as num?)?.toDouble() ?? 280,
        ),
      ),
    ),
  ),
};
