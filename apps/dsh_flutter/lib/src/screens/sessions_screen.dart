import 'package:dsh_feature_session/dsh_feature_session.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../app_controller.dart';
import 'connection_bar.dart';
import 'security_chip.dart';

/// The session list pane with its toolbar (new session, settings, disconnect)
/// and the reconnect banner. Hosts no navigation: [onOpen] decides what
/// opening a row does (push a route on a phone, fill the detail pane on a
/// tablet).
class SessionsPane extends StatelessWidget {
  const SessionsPane({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onSettings,
  });

  final AppController controller;
  final ValueChanged<String> onOpen;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final i18n = controller.i18n;
    String a(String key) => i18n.t(appNamespace, key);
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DshSpace.lg,
              DshSpace.sm,
              DshSpace.sm,
              DshSpace.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a('sessions.title'),
                        key: const ValueKey('sessions-title'),
                        style: theme
                            .textStyle('--dsw-font-l-20')
                            .copyWith(color: theme.labelPrimary),
                      ),
                      if (controller.hostOrigin != null)
                        Text(
                          controller.hostOrigin!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme
                              .textStyle('--dsw-font-xxs-12')
                              .copyWith(
                                color: theme.color(
                                  '--dsw-alias-label-tertiary',
                                ),
                              ),
                        ),
                      if (controller.hostOrigin != null)
                        SecurityChip(controller: controller),
                    ],
                  ),
                ),
                DshIconButton(
                  key: const ValueKey('sessions-new'),
                  icon: Icons.add,
                  plain: true,
                  semanticLabel: a('sessions.new'),
                  onPressed: controller.createSession,
                ),
                DshIconButton(
                  key: const ValueKey('sessions-settings'),
                  icon: Icons.tune,
                  plain: true,
                  semanticLabel: i18n.t('settings', 'trigger'),
                  onPressed: onSettings,
                ),
              ],
            ),
          ),
        ),
        ConnectionBar(controller: controller),
        if (controller.createError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DshSpace.lg),
            child: Text(
              '${a('sessions.createFailed')}: ${controller.createError}',
              key: const ValueKey('create-error'),
              style: theme
                  .textStyle('--dsw-font-xxs-12')
                  .copyWith(
                    color: theme.color('--dsw-alias-state-error-primary'),
                  ),
            ),
          ),
        Expanded(
          child: SessionListView(
            snapshot: controller.sessionList,
            i18n: i18n,
            onOpen: onOpen,
            onRefresh: controller.refreshSessions,
            onNew: controller.createSession,
          ),
        ),
      ],
    );
  }
}
