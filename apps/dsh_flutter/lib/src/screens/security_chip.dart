import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import '../app_controller.dart';

/// How the connection to the host is protected, always visible beside the host
/// address: plain http says so in the warning colour, https says encrypted
/// (and, for a host with a certificate the user confirmed, that the
/// certificate is a trusted one).
class SecurityChip extends StatelessWidget {
  const SecurityChip({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final security = controller.security;
    final plain = security == LinkSecurity.plain;
    final color = plain
        ? theme.color('--dsw-alias-state-warn-label')
        : theme.color('--dsw-alias-label-tertiary');
    final text = controller.i18n.t(appNamespace, switch (security) {
      LinkSecurity.plain => 'security.plain',
      LinkSecurity.encrypted => 'security.encrypted',
      LinkSecurity.pinned => 'security.pinned',
    });
    return Row(
      key: ValueKey('security-${security.name}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        DshIcon(
          plain ? CharcoalIcons.warning : CharcoalIcons.lock,
          size: 12,
          color: color,
        ),
        const SizedBox(width: DshSpace.xs),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyle('--dsw-font-xxs-12').copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
